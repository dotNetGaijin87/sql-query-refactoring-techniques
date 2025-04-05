-----------------------------------------------------------------------------------
-- 
-- 複雑なクエリのリファクタリング (ケーススタディ) 
--   
--        初期クエリ 
--        リファクタリング #1: ループと一時テーブルの排除
--        リファクタリング #2: サブクエリをSELECTからFROM句に移動
--        リファクタリング #3: CTEとウィンドウ関数を使用してクエリを簡素化 
--        リファクタリング #4: ユーザーテーブルアクセスの改善（前処理による集約）
--        リファクタリング #5: CTEの統合によりtaskテーブルのスキャンを1回まで削減
--        リファクタリングのサマリー
--
-----------------------------------------------------------------------------------
USE SqlRefactoring;
GO

--================================================================================                                                      
--  初期クエリ
--================================================================================
CREATE OR ALTER PROCEDURE dbo.MonthlyTaskSummaryReport_v1
    @reportMonth VARCHAR(7) 
AS
BEGIN
    SET NOCOUNT ON;

    -- 入力を月の最初の日に変換
    DECLARE @reportMonthDate DATE = DATEFROMPARTS(LEFT(@reportMonth, 4), RIGHT(@reportMonth, 2), 1);

    CREATE TABLE #TaskSummary (
        report_month        VARCHAR(7),
        day_of_month        INT,
        total_tasks         INT,
        completed_tasks     INT,
        delayed_tasks       INT,
        high_priority_tasks INT,
        user_with_most_tasks NVARCHAR(50),
        total_user_tasks    INT
    );

    DECLARE @day INT = 1;

    WHILE @day <= DAY(EOMONTH(@reportMonthDate))
    BEGIN
        DECLARE @taskCount INT = 0, 
                @completed INT = 0, 
                @delayed INT = 0, 
                @highPriorityCount INT = 0, 
                @topUser NVARCHAR(50), 
                @totalUserTasks INT = 0;

        -- 現在の日付にタスクが存在するか確認
        IF EXISTS (
            SELECT 1 FROM task 
            WHERE due_date >= DATEADD(DAY, @day - 1, @reportMonthDate) 
              AND due_date < DATEADD(DAY, @day, @reportMonthDate)
        )
        BEGIN
            -- 現在の日付におけるタスク数とトップユーザーの取得
            SELECT 
                @taskCount = ISNULL(COUNT(*), 'N/A'),
                @completed = SUM(CASE WHEN ts.status_name = 'Completed' THEN 1 ELSE 0 END),
                @delayed = SUM(CASE WHEN ts.status_name = 'Delayed' THEN 1 ELSE 0 END),
                @highPriorityCount = SUM(CASE WHEN tp.priority_name = 'High' THEN 1 ELSE 0 END)
            FROM task t
            LEFT JOIN task_status ts ON t.status_id = ts.status_id
            LEFT JOIN task_priority tp ON t.priority_id = tp.priority_id
            WHERE t.due_date >= DATEADD(DAY, @day - 1, @reportMonthDate) 
              AND t.due_date < DATEADD(DAY, @day, @reportMonthDate);

            -- 現在の日付における最もタスクが多いユーザーの取得
            SELECT TOP 1 @topUser = u.first_name + ' ' + u.last_name, 
                        @totalUserTasks = COUNT(t.task_id) 
            FROM task t
            JOIN [user] u ON t.assigned_to_user_id = u.user_id
            WHERE t.due_date >= DATEADD(DAY, @day - 1, @reportMonthDate) 
              AND t.due_date < DATEADD(DAY, @day, @reportMonthDate)
            GROUP BY u.first_name, u.last_name
            ORDER BY COUNT(t.task_id) DESC;

        END
        ELSE
        BEGIN
            -- タスクがなければ、デフォルトのデータを挿入
            SET @taskCount = 0;
            SET @completed = 0;
            SET @delayed = 0;
            SET @highPriorityCount = 0;
            SET @topUser = NULL;
            SET @totalUserTasks = 0;
        END

        -- 結果を#TaskSummaryテーブルに挿入
        INSERT INTO #TaskSummary (report_month, day_of_month, total_tasks, completed_tasks, delayed_tasks, high_priority_tasks, user_with_most_tasks, total_user_tasks)
        VALUES (@reportMonth, @day, @taskCount, @completed, @delayed, @highPriorityCount, @topUser, @totalUserTasks);

        SET @day = @day + 1;
    END;

    -- 最終的なタスクサマリーを取得
    SELECT * FROM #TaskSummary;

    -- 一時テーブルを削除
    DROP TABLE #TaskSummary;

END;
GO

--================================================================================                                                      
--  リファクタリング #1: ループと一時テーブルの排除
--================================================================================
CREATE OR ALTER PROCEDURE dbo.MonthlyTaskSummaryReport_v2
    @reportMonth VARCHAR(7) 
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @reportMonthDate DATE = DATEFROMPARTS(LEFT(@reportMonth, 4), RIGHT(@reportMonth, 2), 1);
    DECLARE @lastDay INT = DAY(EOMONTH(@reportMonthDate));
    WITH DayNumbers AS (
        SELECT v.day_of_month
        FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10),
                     (11), (12), (13), (14), (15), (16), (17), (18), (19), (20),
                     (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31)) v(day_of_month)
        WHERE v.day_of_month <= @lastDay
    )
    SELECT 
        @reportMonth AS report_month,
        d.day_of_month,
        SUM(CASE WHEN t.task_id IS NULL THEN 0 ELSE 1 END) AS total_tasks,
        SUM(CASE WHEN ts.status_name = 'Completed' THEN 1 ELSE 0 END) AS completed_tasks,
        SUM(CASE WHEN ts.status_name = 'Delayed' THEN 1 ELSE 0 END) AS delayed_tasks,
        SUM(CASE WHEN tp.priority_name = 'High' THEN 1 ELSE 0 END) AS high_priority_tasks,    
        (SELECT TOP 1 u.first_name + ' ' + u.last_name
             FROM task t1
             JOIN [user] u ON t1.assigned_to_user_id = u.user_id
             WHERE t1.due_date >= @reportMonthDate AND t1.due_date < DATEADD(MONTH, 1, @reportMonthDate)
               AND DAY(t1.due_date) = d.day_of_month 
             GROUP BY u.first_name, u.last_name
             ORDER BY COUNT(t1.task_id) DESC
        ) AS user_with_most_tasks,      
        ISNULL(
            (SELECT TOP 1 COUNT(t1.task_id)
             FROM task t1
             JOIN [user] u ON t1.assigned_to_user_id = u.user_id
             WHERE t1.due_date >= @reportMonthDate AND t1.due_date < DATEADD(MONTH, 1, @reportMonthDate)
               AND DAY(t1.due_date) = d.day_of_month 
             GROUP BY u.first_name, u.last_name
             ORDER BY COUNT(t1.task_id) DESC), 
            0) AS total_user_tasks
    FROM DayNumbers d
    LEFT JOIN task t ON DAY(t.due_date) = d.day_of_month 
          AND t.due_date BETWEEN @reportMonthDate AND EOMONTH(@reportMonthDate)
    LEFT JOIN task_status ts ON t.status_id = ts.status_id
    LEFT JOIN task_priority tp ON t.priority_id = tp.priority_id
    GROUP BY d.day_of_month
    ORDER BY d.day_of_month;
END;
GO

--                                                   
-- バージョンV1とV2の比較
--
DECLARE @StartTime DATETIME, @EndTime DATETIME;
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v1 '2025-07';
SET @EndTime = GETDATE();
PRINT DATEDIFF(MILLISECOND, @StartTime, @EndTime);


SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v2 '2025-07';
SET @EndTime = GETDATE();
PRINT DATEDIFF(MILLISECOND, @StartTime, @EndTime);
GO

--================================================================================                                                      
--  リファクタリング #2: サブクエリをSELECTからFROM句に移動
--================================================================================
CREATE OR ALTER PROCEDURE dbo.MonthlyTaskSummaryReport_v3
    @reportMonth VARCHAR(7) 
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @firstDayDate DATE = DATEFROMPARTS(LEFT(@reportMonth, 4), RIGHT(@reportMonth, 2), 1);
    DECLARE @lastDayDate DATE = EOMONTH(@firstDayDate);

    WITH DayNumbers AS (
        SELECT v.day_of_month
        FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10),
                     (11), (12), (13), (14), (15), (16), (17), (18), (19), (20),
                     (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31)) v(day_of_month)
        WHERE v.day_of_month <= DAY(EOMONTH(@lastDayDate))
    )
    SELECT 
        @reportMonth AS report_month,
        d.day_of_month,
        SUM(CASE WHEN t.task_id IS NULL THEN 0 ELSE 1 END) AS total_tasks,
        SUM(CASE WHEN ts.status_name = 'Completed' THEN 1 ELSE 0 END) AS completed_tasks,
        SUM(CASE WHEN ts.status_name = 'Delayed' THEN 1 ELSE 0 END) AS delayed_tasks,
        SUM(CASE WHEN tp.priority_name = 'High' THEN 1 ELSE 0 END) AS high_priority_tasks,     
        ut.user_with_most_tasks,     
        ISNULL(ut.total_user_tasks, 0) AS total_user_tasks
    FROM DayNumbers d
        LEFT JOIN task t ON DAY(t.due_date) = d.day_of_month 
              AND t.due_date BETWEEN @firstDayDate AND @lastDayDate
        LEFT JOIN task_status ts ON t.status_id = ts.status_id
        LEFT JOIN task_priority tp ON t.priority_id = tp.priority_id
        LEFT JOIN (
            SELECT 
                DAY(t1.due_date) AS day_of_month,
                u.first_name + ' ' + u.last_name AS user_with_most_tasks,
                COUNT(t1.task_id) AS total_user_tasks
            FROM task t1
            JOIN [user] u ON t1.assigned_to_user_id = u.user_id
            WHERE t1.due_date BETWEEN @firstDayDate AND @lastDayDate
            GROUP BY DAY(t1.due_date), u.first_name, u.last_name
            HAVING COUNT(t1.task_id) = (
                SELECT MAX(task_count) 
                FROM (
                    SELECT COUNT(t2.task_id) AS task_count
                    FROM task t2
                    WHERE t2.due_date BETWEEN @firstDayDate AND @lastDayDate
                      AND DAY(t2.due_date) = DAY(t1.due_date)
                    GROUP BY t2.assigned_to_user_id
                ) AS task_counts
            )) AS ut ON DAY(t.due_date) = ut.day_of_month
    GROUP BY d.day_of_month, user_with_most_tasks, total_user_tasks
    ORDER BY d.day_of_month;
END
GO

--                                                   
-- バージョンV2とV3の比較
--
SET STATISTICS IO,TIME ON;

EXEC MonthlyTaskSummaryReport_v2 '2025-07';
GO
EXEC MonthlyTaskSummaryReport_v3 '2025-07';
GO



--================================================================================                                                      
-- リファクタリング #3: CTEとウィンドウ関数を使用してクエリを簡素化 
--================================================================================
CREATE OR ALTER PROCEDURE dbo.MonthlyTaskSummaryReport_v4
    @reportMonth VARCHAR(7) 
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @firstDayDate DATE = DATEFROMPARTS(LEFT(@reportMonth, 4), RIGHT(@reportMonth, 2), 1);
    DECLARE @lastDayDate DATE = EOMONTH(@firstDayDate);

    WITH DayNumbers AS (
        SELECT v.day_of_month
        FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10),
                     (11), (12), (13), (14), (15), (16), (17), (18), (19), (20),
                     (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31)) v(day_of_month)
        WHERE v.day_of_month <= DAY(@lastDayDate)
    ),
    TaskSummary AS (
        SELECT 
            DAY(t.due_date) AS day_of_month,
            COUNT(t.task_id) AS total_tasks,
            SUM(CASE WHEN ts.status_name = 'Completed' THEN 1 ELSE 0 END) AS completed_tasks,
            SUM(CASE WHEN ts.status_name = 'Delayed' THEN 1 ELSE 0 END) AS delayed_tasks,
            SUM(CASE WHEN tp.priority_name = 'High' THEN 1 ELSE 0 END) AS high_priority_tasks
        FROM task t
        JOIN task_status ts ON t.status_id = ts.status_id
        JOIN task_priority tp ON t.priority_id = tp.priority_id
        WHERE t.due_date BETWEEN @firstDayDate AND @lastDayDate
        GROUP BY DAY(t.due_date)
    ),
    TopUsers AS (    
        SELECT 
            DAY(t.due_date) AS day_of_month,
            u.first_name + ' ' + u.last_name AS user_with_most_tasks,
            COUNT(t.task_id) AS total_user_tasks,
            ROW_NUMBER() OVER (PARTITION BY DAY(t.due_date) ORDER BY COUNT(t.task_id) DESC) AS rn
        FROM task t
        JOIN [user] u ON t.assigned_to_user_id = u.user_id
        WHERE t.due_date BETWEEN @firstDayDate AND @lastDayDate
        GROUP BY DAY(t.due_date), u.first_name, u.last_name
    )
    SELECT 
        @reportMonth AS report_month,
        d.day_of_month,
        ISNULL(ts.total_tasks, 0) AS total_tasks,
        ISNULL(ts.completed_tasks, 0) AS completed_tasks,
        ISNULL(ts.delayed_tasks, 0) AS delayed_tasks,
        ISNULL(ts.high_priority_tasks, 0) AS high_priority_tasks,
        tu.user_with_most_tasks,
        ISNULL(tu.total_user_tasks, 0) AS total_user_tasks
    FROM DayNumbers d
    LEFT JOIN TaskSummary ts ON d.day_of_month = ts.day_of_month
    LEFT JOIN TopUsers tu ON d.day_of_month = tu.day_of_month 
    WHERE tu.rn = 1
    ORDER BY d.day_of_month;
END;
GO

--                                                   
-- バージョンV3とV4の比較
--

EXEC MonthlyTaskSummaryReport_v3 '2025-07';
GO
EXEC MonthlyTaskSummaryReport_v4 '2025-07';
GO


--================================================================================                                                      
-- リファクタリング #4: ユーザーテーブルアクセスの改善（前処理による集約）
--================================================================================
CREATE OR ALTER PROCEDURE dbo.MonthlyTaskSummaryReport_v5
    @reportMonth VARCHAR(7) 
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @firstDayDate DATE = DATEFROMPARTS(LEFT(@reportMonth, 4), RIGHT(@reportMonth, 2), 1);
    DECLARE @lastDayDate DATE = EOMONTH(@firstDayDate);

    WITH DayNumbers AS (
        SELECT v.day_of_month
        FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10),
                     (11), (12), (13), (14), (15), (16), (17), (18), (19), (20),
                     (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31)) v(day_of_month)
        WHERE v.day_of_month <= DAY(@lastDayDate)
    ),
    TaskSummary AS (
        SELECT 
            DAY(t.due_date) AS day_of_month,
            COUNT(t.task_id) AS total_tasks,
            SUM(CASE WHEN ts.status_name = 'Completed' THEN 1 ELSE 0 END) AS completed_tasks,
            SUM(CASE WHEN ts.status_name = 'Delayed' THEN 1 ELSE 0 END) AS delayed_tasks,
            SUM(CASE WHEN tp.priority_name = 'High' THEN 1 ELSE 0 END) AS high_priority_tasks
        FROM task t
        JOIN task_status ts ON t.status_id = ts.status_id
        JOIN task_priority tp ON t.priority_id = tp.priority_id
        WHERE t.due_date BETWEEN @firstDayDate AND @lastDayDate
        GROUP BY DAY(t.due_date)
    ),
    TopUsers AS (
        SELECT 
            utc.day_of_month,
            u.first_name + ' ' + u.last_name AS user_with_most_tasks,
            utc.total_user_tasks,
            ROW_NUMBER() OVER (PARTITION BY utc.day_of_month ORDER BY utc.total_user_tasks DESC) AS rn
        FROM (
            SELECT 
                DAY(t.due_date) AS day_of_month,
                t.assigned_to_user_id,
                COUNT(t.task_id) AS total_user_tasks
            FROM task t
            WHERE t.due_date BETWEEN @firstDayDate AND @lastDayDate
            GROUP BY DAY(t.due_date), t.assigned_to_user_id
        ) AS utc JOIN [user] u ON utc.assigned_to_user_id = u.user_id
    )
    SELECT 
        @reportMonth AS report_month,
        d.day_of_month,
        ISNULL(ts.total_tasks, 0) AS total_tasks,
        ISNULL(ts.completed_tasks, 0) AS completed_tasks,
        ISNULL(ts.delayed_tasks, 0) AS delayed_tasks,
        ISNULL(ts.high_priority_tasks, 0) AS high_priority_tasks,
        tu.user_with_most_tasks,
        ISNULL(tu.total_user_tasks, 0) AS total_user_tasks
    FROM DayNumbers d
    LEFT JOIN TaskSummary ts ON d.day_of_month = ts.day_of_month
    LEFT JOIN TopUsers tu ON d.day_of_month = tu.day_of_month
    WHERE tu.rn = 1
    ORDER BY d.day_of_month;
END;
GO


--                                                   
-- バージョンV4とV5の比較
--
EXEC MonthlyTaskSummaryReport_v4 '2025-07';
GO
EXEC MonthlyTaskSummaryReport_v5 '2025-07';
GO

--================================================================================                                                      
-- リファクタリング #5: CTEの統合によりtaskテーブルのスキャンを1回まで削減
--================================================================================
CREATE OR ALTER PROCEDURE dbo.MonthlyTaskSummaryReport_v6
    @reportMonth VARCHAR(7) 
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @firstDayDate DATE = DATEFROMPARTS(LEFT(@reportMonth, 4), RIGHT(@reportMonth, 2), 1);
    DECLARE @lastDayDate DATE = EOMONTH(@firstDayDate);

    WITH DayNumbers AS (
        SELECT v.day_of_month
        FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10),
                     (11), (12), (13), (14), (15), (16), (17), (18), (19), (20),
                     (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31)) v(day_of_month)
        WHERE v.day_of_month <= DAY(@lastDayDate)
    ),
    TaskData AS (
        SELECT 
            day_of_month,
            assigned_to_user_id,
            total_tasks,
            completed_tasks,
            delayed_tasks,
            high_priority_tasks,
            total_user_tasks,
            ROW_NUMBER() OVER (PARTITION BY day_of_month ORDER BY total_user_tasks DESC) AS rn
        FROM (        
            SELECT 
                DAY(t.due_date) AS day_of_month,
                t.assigned_to_user_id,
                COUNT(*) AS total_tasks,
                SUM(CASE WHEN ts.status_name = 'Completed' THEN 1 ELSE 0 END) AS completed_tasks,
                SUM(CASE WHEN ts.status_name = 'Delayed' THEN 1 ELSE 0 END) AS delayed_tasks,
                SUM(CASE WHEN tp.priority_name = 'High' THEN 1 ELSE 0 END) AS high_priority_tasks,
                COUNT(*) AS total_user_tasks
            FROM task t
            JOIN task_status ts ON t.status_id = ts.status_id
            JOIN task_priority tp ON t.priority_id = tp.priority_id
            WHERE t.due_date BETWEEN @firstDayDate AND @lastDayDate
            GROUP BY DAY(t.due_date), t.assigned_to_user_id
        ) AS aa
    )
    SELECT 
        @reportMonth AS report_month,
        d.day_of_month,
        ISNULL(td.total_tasks, 0) AS total_tasks,
        ISNULL(td.completed_tasks, 0) AS completed_tasks,
        ISNULL(td.delayed_tasks, 0) AS delayed_tasks,
        ISNULL(td.high_priority_tasks, 0) AS high_priority_tasks,
        u.first_name + ' ' + u.last_name AS user_with_most_tasks,
        ISNULL(td.total_user_tasks, 0) AS total_user_tasks
    FROM DayNumbers d
    LEFT JOIN TaskData td ON d.day_of_month = td.day_of_month AND td.rn = 1
    LEFT JOIN [user] u ON td.assigned_to_user_id = u.user_id
    ORDER BY d.day_of_month;
END;
GO

--                                                   
-- バージョンV5とV6の比較
--
EXEC MonthlyTaskSummaryReport_v5 '2025-07';
GO
EXEC MonthlyTaskSummaryReport_v6 '2025-07';
GO



--================================================================================                                                      
--  リファクタリングのサマリー
--================================================================================


--
-- 全バージョンパフォーマンスの比較
--
SET STATISTICS IO,TIME OFF;

DECLARE @StartTime DATETIME, @EndTime DATETIME;
--
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v1 '2025-07';
SET @EndTime = GETDATE();
PRINT 'V1: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(20)) + ' ms';
--
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v2 '2025-07';
SET @EndTime = GETDATE();
PRINT 'V2: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(20)) + ' ms';
--
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v3 '2025-07';
SET @EndTime = GETDATE();
PRINT 'V3: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(20)) + ' ms';
--
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v4 '2025-07';
SET @EndTime = GETDATE();
PRINT 'V4: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(20)) + ' ms';
--
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v5 '2025-07';
SET @EndTime = GETDATE();
PRINT 'V5: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(20)) + ' ms';
--
SET @StartTime = GETDATE();
EXEC MonthlyTaskSummaryReport_v6 '2025-07';
SET @EndTime = GETDATE();
PRINT 'V6: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(20)) + ' ms';


--
-- 全バージョンが同じデータを返すかどうかの確認
--
DECLARE  @reportMonth VARCHAR(7)= '2025-07';

CREATE TABLE #Temp_v1 (report_month VARCHAR(7), day_of_month INT, total_tasks INT, completed_tasks INT, delayed_tasks INT, high_priority_tasks INT, user_with_most_tasks NVARCHAR(50), total_user_tasks INT);
INSERT INTO #Temp_v1
EXEC dbo.MonthlyTaskSummaryReport_v1 @reportMonth;

CREATE TABLE #Temp_v2 (report_month VARCHAR(7), day_of_month INT, total_tasks INT, completed_tasks INT, delayed_tasks INT, high_priority_tasks INT, user_with_most_tasks NVARCHAR(50), total_user_tasks INT);
INSERT INTO #Temp_v2
EXEC dbo.MonthlyTaskSummaryReport_v2 @reportMonth;

CREATE TABLE #Temp_v3 (report_month VARCHAR(7), day_of_month INT, total_tasks INT, completed_tasks INT, delayed_tasks INT, high_priority_tasks INT, user_with_most_tasks NVARCHAR(50), total_user_tasks INT);
INSERT INTO #Temp_v3
EXEC dbo.MonthlyTaskSummaryReport_v3 @reportMonth;

CREATE TABLE #Temp_v4 (report_month VARCHAR(7), day_of_month INT, total_tasks INT, completed_tasks INT, delayed_tasks INT, high_priority_tasks INT, user_with_most_tasks NVARCHAR(50), total_user_tasks INT);
INSERT INTO #Temp_v4
EXEC dbo.MonthlyTaskSummaryReport_v4 @reportMonth;

CREATE TABLE #Temp_v5 (report_month VARCHAR(7), day_of_month INT, total_tasks INT, completed_tasks INT, delayed_tasks INT, high_priority_tasks INT, user_with_most_tasks NVARCHAR(50), total_user_tasks INT);
INSERT INTO #Temp_v5
EXEC dbo.MonthlyTaskSummaryReport_v5 @reportMonth;

(SELECT * FROM #Temp_v1
EXCEPT
SELECT * FROM #Temp_v2
EXCEPT
SELECT * FROM #Temp_v3
EXCEPT
SELECT * FROM #Temp_v4
EXCEPT
SELECT * FROM #Temp_v5)

UNION ALL

(SELECT * FROM #Temp_v5
EXCEPT
SELECT * FROM #Temp_v4
EXCEPT
SELECT * FROM #Temp_v3
EXCEPT
SELECT * FROM #Temp_v2
EXCEPT
SELECT * FROM #Temp_v1)


DROP TABLE #Temp_v1, #Temp_v2, #Temp_v3, #Temp_v4, #Temp_v5;
