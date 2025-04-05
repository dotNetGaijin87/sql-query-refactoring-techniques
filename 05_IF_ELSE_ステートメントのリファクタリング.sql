-----------------------------------------------------------------------------------
--
--    IF ELSE ステートメントのリファクタリング
--       
--        手法＃６：複数IF-ELSEをCASE式で解決
--        手法＃７：防御IFをなくす
--        手法＃８：IF ... IS NULLをISNULL関数で解決
--        手法＃９：優先順位UPDATEをCASE式で解決
--  
-----------------------------------------------------------------------------------
USE SqlRefactoring;
GO
SET STATISTICS IO ON;



--================================================================================                                              
--  手法＃６：複数IF-ELSEをCASE式で解決
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
DECLARE @task_id INT;
DECLARE @due_date DATE;
DECLARE @status_id INT;
DECLARE @current_date DATE = '2025-06-30'; -- 一貫性のため固定日付を使用

DECLARE cur_tasks CURSOR FOR
SELECT task_id, due_date
FROM task
WHERE status_id IN (2, 3, 4);

OPEN cur_tasks;

FETCH NEXT FROM cur_tasks INTO @task_id, @due_date;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET NOCOUNT ON;

    IF @due_date < @current_date
        SET @status_id = 4; -- 遅延
    ELSE IF @due_date < DATEADD(DAY, -1, @current_date)
        SET @status_id = 3; -- 遅延のリスクあり
    ELSE
        SET @status_id = 2; -- 順調

    UPDATE task
        SET status_id = @status_id
    WHERE task_id = @task_id;

    FETCH NEXT FROM cur_tasks INTO @task_id, @due_date;
END;

CLOSE cur_tasks;
DEALLOCATE cur_tasks;
GO


--------------------------------
-- AFTER
--------------------------------
DECLARE @current_date DATE = '2025-06-30'; -- 一貫性のため固定日付を使用

UPDATE task
    SET status_id = 
        CASE 
            WHEN due_date < @current_date THEN 4 -- 遅延
            WHEN due_date < DATEADD(DAY, -1, @current_date) THEN 3 -- 遅延のリスクあり
            ELSE 2 -- 順調
        END
    WHERE status_id IN (2, 3, 4);
GO



--================================================================================                                                  
--   手法＃７：防御IFをなくす
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
DECLARE @task_id INT = 1;
DECLARE @new_user_id INT = 1;
DECLARE @existing_user_id INT;


SELECT @existing_user_id = assigned_to_user_id
FROM task
WHERE task_id = @task_id;

IF @existing_user_id <> @new_user_id
    BEGIN
        UPDATE task
            SET assigned_to_user_id = @new_user_id
        WHERE task_id = @task_id;
    END;

GO

--------------------------------
-- AFTER
--------------------------------
DECLARE @task_id INT = 1;  
DECLARE @new_user_id INT = 5;

UPDATE task
    SET assigned_to_user_id = @new_user_id
WHERE task_id = @task_id
  AND assigned_to_user_id <> @new_user_id;


IF @@ROWCOUNT = 0
    BEGIN
        PRINT 'タスクはすでに指定されたユーザーに割り当てられています';
    END
ELSE
    BEGIN
        PRINT 'タスク番号: ' + CAST(@task_id AS NVARCHAR(20));
        PRINT '割り当てユーザー ID: ' + CAST(@new_user_id AS NVARCHAR(20));
    END
GO


--================================================================================               
--  手法＃８：IF ... IS NULLをISNULL関数で解決
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
DECLARE @project_id INT = 1;
DECLARE @at_risk_task_name NVARCHAR(100);
DECLARE @at_risk_user NVARCHAR(100);
DECLARE @current_date DATE = '2025-06-25'; -- 一貫性のため固定日付を使用

SELECT TOP 1
    @at_risk_task_name = t.task_name
FROM task t
WHERE t.project_id = @project_id
  AND (t.due_date < @current_date
       OR t.due_date BETWEEN @current_date AND DATEADD(DAY, 3, @current_date))
  AND t.status_id = (SELECT status_id FROM task_status WHERE status_name = 'On Track')
ORDER BY t.priority_id DESC, t.due_date ASC;

IF @at_risk_task_name IS NULL
BEGIN
    SET @at_risk_task_name = 'リスクのあるタスクはありません';
END

SELECT @at_risk_task_name AS task_name;
GO

--------------------------------
-- AFTER #1 (ISNULL使用)
--------------------------------
DECLARE @project_id INT = 1;
DECLARE @at_risk_task_name NVARCHAR(100);
DECLARE @at_risk_user NVARCHAR(100);
DECLARE @current_date DATE = '2025-06-25'; -- 一貫性のため固定日付を使用

SELECT @at_risk_task_name = ISNULL(
    (SELECT TOP 1 t.task_name
     FROM task t
     WHERE t.project_id = @project_id
       AND (t.due_date < @current_date
            OR t.due_date BETWEEN @current_date AND DATEADD(DAY, 3, @current_date))
       AND t.status_id = (SELECT status_id FROM task_status WHERE status_name = 'On Track')
     ORDER BY t.priority_id DESC, t.due_date ASC),
    'リスクのあるタスクはありません'
);

SELECT @at_risk_task_name AS task_name;

--------------------------------
-- AFTER #2 (ISNULL使用)
--------------------------------
SELECT TOP 1 @at_risk_task_name = t.task_name
FROM task t
WHERE t.project_id = @project_id
  AND (t.due_date < @current_date
       OR t.due_date BETWEEN @current_date AND DATEADD(DAY, 3, @current_date))
  AND t.status_id = (SELECT status_id FROM task_status WHERE status_name = 'On Track')
ORDER BY t.priority_id DESC, t.due_date ASC;

SELECT ISNULL(@at_risk_task_name, 'リスクのあるタスクはありません') AS task_name;

--------------------------------
-- AFTER #3 (COALESCE使用)
--------------------------------
SELECT @at_risk_task_name = COALESCE(
    (SELECT TOP 1 t.task_name
     FROM task t
     WHERE t.project_id = @project_id
       AND (t.due_date < @current_date
            OR t.due_date BETWEEN @current_date AND DATEADD(DAY, 3, @current_date))
       AND t.status_id = (SELECT status_id FROM task_status WHERE status_name = 'On Track')
     ORDER BY t.priority_id DESC, t.due_date ASC),
    'リスクのあるタスクはありません'
);
SELECT @at_risk_task_name AS task_name;
GO


--================================================================================                                                         
--  手法＃９：優先順位UPDATEをCASE式で解決
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
CREATE OR ALTER PROCEDURE assign_task_to_user_before
    @user_id INT,
    @assigned_task_id INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- クリティカル優先度のタスクをチェック
    SELECT TOP 1 @assigned_task_id = task_id
    FROM task
    WHERE priority_id = (SELECT priority_id FROM task_priority WHERE priority_name = 'Critical')
      AND assigned_to_user_id IS NULL
    ORDER BY task_id;

    IF @assigned_task_id IS NOT NULL
    BEGIN
        UPDATE task
            SET assigned_to_user_id = @user_id
        WHERE task_id = @assigned_task_id;

        RETURN;
    END

    -- 高優先度のタスクをチェック
    SELECT TOP 1 @assigned_task_id = task_id
    FROM task
    WHERE priority_id = (SELECT priority_id FROM task_priority WHERE priority_name = 'High')
      AND assigned_to_user_id IS NULL
    ORDER BY task_id;

    IF @assigned_task_id IS NOT NULL
    BEGIN
        UPDATE task
            SET assigned_to_user_id = @user_id
        WHERE task_id = @assigned_task_id;

        RETURN;
    END

    -- 中優先度のタスクをチェック
    SELECT TOP 1 @assigned_task_id = task_id
    FROM task
    WHERE priority_id = (SELECT priority_id FROM task_priority WHERE priority_name = 'Medium')
      AND assigned_to_user_id IS NULL
    ORDER BY task_id;

    IF @assigned_task_id IS NOT NULL
    BEGIN
        UPDATE task
            SET assigned_to_user_id = @user_id
        WHERE task_id = @assigned_task_id;

        RETURN;
    END

    -- 任意のタスク（低優先度の場合）
    SELECT TOP 1 @assigned_task_id = task_id
    FROM task
    WHERE assigned_to_user_id IS NULL
    ORDER BY task_id;

    IF @assigned_task_id IS NOT NULL
    BEGIN
        UPDATE task
            SET assigned_to_user_id = @user_id
        WHERE task_id = @assigned_task_id;

        RETURN;
    END

END;

GO

--------------------------------
-- AFTER
--------------------------------

CREATE OR ALTER PROCEDURE assign_task_to_user_after
    @user_id INT,
    @assigned_task_id INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- 割り当てられたタスクIDのテーブル変数を宣言
    DECLARE @AssignedTask TABLE (task_id INT);

    -- 最も優先度が高い利用可能なタスクを割り当て
    UPDATE t
        SET t.assigned_to_user_id = @user_id
    OUTPUT INSERTED.task_id INTO @AssignedTask
    FROM task t
    WHERE t.task_id = (
        SELECT TOP 1 t2.task_id
        FROM task t2
            INNER JOIN task_priority tp2 ON t2.priority_id = tp2.priority_id
        WHERE t2.assigned_to_user_id IS NULL
        ORDER BY 
            CASE tp2.priority_name
                WHEN 'Critical' THEN 1
                WHEN 'High'     THEN 2
                WHEN 'Medium'   THEN 3
                ELSE 4 -- 低い優先度
            END,
            t2.task_id -- 同じ優先度の場合のタイブレーカー
    );

    -- 割り当てられたタスクIDを取得
    SELECT @assigned_task_id = task_id FROM @AssignedTask;
END;

--------------------------------
-- 使用例
--------------------------------

-- Before
DECLARE @task_id1 INT;
EXEC assign_task_to_user_before @user_id = 1, @assigned_task_id = @task_id1 OUTPUT;
SELECT @task_id1 AS AssignedTask;


-- After
DECLARE @task_id2 INT;
EXEC assign_task_to_user_after @user_id = 1, @assigned_task_id = @task_id2 OUTPUT;
SELECT @task_id2 AS AssignedTask;