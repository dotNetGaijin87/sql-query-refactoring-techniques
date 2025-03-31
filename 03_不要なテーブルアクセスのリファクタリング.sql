-----------------------------------------------------------------------------------
--
--   不要なテーブルアクセスのリファクタリング
--       
--		手法＃１：ウィンドウ関数による無駄なテーブルアクセス削減
--		手法＃２：一時テーブルによる重複スキャン削減
--		手法＃３：CASE式による一括更新
-- 
-----------------------------------------------------------------------------------
USE SqlRefactoring;
GO

SET STATISTICS IO ON;

--================================================================================                                                        
--  手法＃１：ウィンドウ関数による無駄なテーブルアクセス削減
--================================================================================

-- 各ユーザーの次のタスクを検索

--------------------------------
-- BEFORE
--------------------------------
SELECT 
    u.user_id, 
    u.first_name, 
    u.last_name, 
    t.task_id, 
    t.task_name, 
    t.due_date, 
    tp.priority_name
FROM [user] u
JOIN task t ON u.user_id = t.assigned_to_user_id
JOIN task_priority tp ON t.priority_id = tp.priority_id
WHERE t.due_date = (
    SELECT MIN(t2.due_date)
    FROM task t2
    WHERE t2.assigned_to_user_id = u.user_id
)
AND t.priority_id = (
    SELECT MAX(t3.priority_id)
    FROM task t3
    WHERE t3.assigned_to_user_id = u.user_id
    AND t3.due_date = (
        SELECT MIN(t4.due_date)
        FROM task t4
        WHERE t4.assigned_to_user_id = u.user_id
    )
)
AND t.task_id = (
    SELECT TOP 1 t5.task_id
    FROM task t5
    WHERE t5.assigned_to_user_id = u.user_id
    AND t5.due_date = (
        SELECT MIN(t6.due_date)
        FROM task t6
        WHERE t6.assigned_to_user_id = u.user_id
    )
    AND t5.priority_id = (
        SELECT MAX(t7.priority_id)
        FROM task t7
        WHERE t7.assigned_to_user_id = u.user_id
        AND t7.due_date = (
            SELECT MIN(t8.due_date)
            FROM task t8
            WHERE t8.assigned_to_user_id = u.user_id
        )
    )
    ORDER BY t5.task_id
)
ORDER BY u.user_id;

--------------------------------
-- AFTER
--------------------------------

SELECT 
    u.user_id, 
    u.first_name, 
    u.last_name, 
    t.task_id, 
    t.task_name, 
    t.due_date, 
    tp.priority_name
FROM [user] u
JOIN (
    SELECT 
        t.assigned_to_user_id, 
        t.task_id, 
        t.task_name, 
        t.due_date, 
        t.priority_id,
        ROW_NUMBER() OVER (
            PARTITION BY t.assigned_to_user_id 
            ORDER BY t.due_date ASC, t.priority_id DESC, t.task_id ASC
        ) AS rn
    FROM task t
    WHERE t.assigned_to_user_id IS NOT NULL
) t ON u.user_id = t.assigned_to_user_id
JOIN task_priority tp ON t.priority_id = tp.priority_id
WHERE t.rn = 1
ORDER BY u.user_id;



--================================================================================                                                        
--  手法＃２：一時テーブルによる重複スキャン削減
--================================================================================


--------------------------------
-- BEFORE
--------------------------------
WITH FilteredTasks AS (
    SELECT 
        t.assigned_to_user_id, 
        t.task_name, 
        t.due_date, 
        t.priority_id,
        p.project_name,
        ps.status_name,
        tp.priority_name,
        COALESCE(tc.comment_count, 0) AS comment_count
    FROM task t
	LEFT JOIN project p ON t.project_id = p.project_id
	LEFT JOIN project_status ps ON p.status_id = ps.status_id
	LEFT JOIN task_priority tp ON t.priority_id = tp.priority_id
	LEFT JOIN (
		SELECT task_id, 
				COUNT(*) AS comment_count
		FROM task_comment
		GROUP BY task_id
	) tc ON t.task_id = tc.task_id
    WHERE p.status_id = (SELECT status_id FROM project_status WHERE status_name = 'Active')
),

OverdueTasks AS (
    SELECT ft.*, 'Overdue' AS TaskType
    FROM FilteredTasks ft
    WHERE ft.due_date < '2025-08-18'
),

HighPriorityTasks AS (
	SELECT ft.*, 'High Priority' AS TaskType
    FROM FilteredTasks ft
    WHERE ft.priority_id = (SELECT priority_id FROM task_priority WHERE priority_name = 'High')
),

TasksWithComments AS (
	SELECT ft.*, 'Has Comment' AS TaskType
    FROM FilteredTasks ft
    WHERE ft.comment_count > 0
)

SELECT * FROM OverdueTasks
UNION ALL
SELECT * FROM HighPriorityTasks
UNION ALL
SELECT * FROM TasksWithComments
ORDER BY assigned_to_user_id;


--------------------------------
-- AFTER
--------------------------------
DROP TABLE IF EXISTS #FilteredTasks;

SELECT 
	t.assigned_to_user_id, 
	t.task_name, 
	t.due_date, 
	t.priority_id,
	p.project_name,
	ps.status_name,
	tp.priority_name,
	COALESCE(tc.comment_count, 0) AS comment_count
INTO #FilteredTasks
FROM task t
	LEFT JOIN project p ON t.project_id = p.project_id
	LEFT JOIN project_status ps ON p.status_id = ps.status_id
	LEFT JOIN task_priority tp ON t.priority_id = tp.priority_id
	LEFT JOIN (
		SELECT task_id, 
			   COUNT(*) AS comment_count
		FROM task_comment
		GROUP BY task_id
	) tc ON t.task_id = tc.task_id
WHERE p.status_id = (SELECT status_id FROM project_status WHERE status_name = 'Active');


SELECT ft.*, 'Overdue' AS TaskType
FROM #FilteredTasks ft
WHERE ft.due_date < '2025-08-18'
UNION ALL
SELECT ft.*, 'High Priority' AS TaskType
FROM #FilteredTasks ft
WHERE ft.priority_id = (SELECT priority_id FROM task_priority WHERE priority_name = 'High')
UNION ALL
SELECT ft.*, 'Has Comment' AS TaskType
FROM #FilteredTasks ft
WHERE ft.comment_count > 0
ORDER BY ft.assigned_to_user_id;



--================================================================================                                                       
--  手法＃３：CASE式による一括更新
--================================================================================


DECLARE @ACTIVE_STATUS INT = (SELECT status_id FROM project_status WHERE status_name = 'Active'); 
DECLARE @DELAYED_STATUS INT = (SELECT status_id FROM project_status WHERE status_name = 'Delayed'); 
DECLARE @MEDIUM_PRIORITY INT = (SELECT status_id FROM project_status WHERE status_name = 'Medium'); 
DECLARE @HIGH_PRIORITY INT = (SELECT status_id FROM project_status WHERE status_name = 'High');


--------------------------------
-- BEFORE
--------------------------------
UPDATE project
	SET status_id = @DELAYED_STATUS
WHERE status_id IN (@ACTIVE_STATUS)
  AND end_date < '2025-08-30';

UPDATE project
	SET priority_id = @HIGH_PRIORITY
WHERE priority_id IN (@MEDIUM_PRIORITY)
  AND budget > 100000;


--------------------------------
-- AFTER
--------------------------------
UPDATE project
	SET status_id = 
		CASE 
			WHEN status_id = @ACTIVE_STATUS AND end_date < '2025-08-30' THEN @DELAYED_STATUS
			ELSE status_id
		END,
	priority_id = 
		CASE 
			WHEN priority_id = @MEDIUM_PRIORITY AND budget > 100000 THEN @HIGH_PRIORITY
			ELSE priority_id
		END
WHERE (status_id = @ACTIVE_STATUS AND end_date < '2025-08-30')
   OR (priority_id = @MEDIUM_PRIORITY AND budget < 100000);
