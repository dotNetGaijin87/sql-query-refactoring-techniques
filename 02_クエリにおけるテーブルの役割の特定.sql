-----------------------------------------------------------------------------------
--   
--  クエリにおけるテーブルの役割の特定の重要性
--
--		リファクタリング＃１：　不要な結合を削除することでのクエリの効率化
--		リファクタリング＃２：　非効率な結合をサブクエリへの移動
--	
-----------------------------------------------------------------------------------
USE SqlRefactoring;
GO

SET STATISTICS IO, TIME ON;

--================================================================================                                                      
--  リファクタリング＃１：　不要な結合を削除することでのクエリの効率化
--================================================================================

--   データテーブル
--   ジャンクションテーブル
--   フィルタリングテーブル
--   集約データテーブル

--------------------------------
-- BEFORE
--------------------------------
SELECT 
	t.task_id,
    t.task_name,
    t.due_date,
    u.first_name + ' ' + u.last_name AS assigned_user,
    ts.status_name,
    tp.priority_name,
    COUNT(DISTINCT td.dependency_id) AS dependency_count
FROM  task t -- データテーブル
JOIN [user] u ON t.assigned_to_user_id = u.user_id       -- データテーブル
JOIN task_status ts ON t.status_id = ts.status_id        -- フィルタリングテーブル
JOIN task_priority tp ON t.priority_id = tp.priority_id  -- フィルタリングテーブル
JOIN project p ON t.project_id = p.project_id            -- ジャンクションテーブル
JOIN project_status ps ON p.status_id = ps.status_id     -- フィルタリングテーブル
LEFT JOIN task_dependency td ON td.task_id = t.task_id   -- 集約データテーブル
JOIN team_membership tm ON tm.user_id = u.user_id        -- ??? 
WHERE ts.status_name = 'On Track' 
  AND tp.priority_name IN ('High', 'Critical')
  AND ps.status_name = 'Active'
  AND u.is_active = 1
GROUP BY t.task_id, t.task_name, t.due_date, u.first_name, u.last_name, ts.status_name, tp.priority_name
ORDER BY t.task_id;
GO

--------------------------------
-- AFTER
--------------------------------
SELECT 
	t.task_id,
    t.task_name,
    t.due_date,
    u.first_name + ' ' + u.last_name AS assigned_user,
    ts.status_name,
    tp.priority_name,
    COUNT(DISTINCT td.dependency_id) AS dependency_count
FROM task t -- データテーブル
JOIN [user] u ON t.assigned_to_user_id = u.user_id       -- データテーブル
JOIN task_status ts ON t.status_id = ts.status_id        -- フィルタリングテーブル
JOIN task_priority tp ON t.priority_id = tp.priority_id  -- フィルタリングテーブル
JOIN project p ON t.project_id = p.project_id            -- ジャンクションテーブル
JOIN project_status ps ON p.status_id = ps.status_id     -- フィルタリングテーブル
LEFT JOIN task_dependency td ON td.task_id = t.task_id   -- 集約データテーブル
WHERE ts.status_name = 'On Track' 
  AND tp.priority_name IN ('High', 'Critical')
  AND ps.status_name = 'Active'
  AND u.is_active = 1
GROUP BY t.task_id, t.task_name, t.due_date, u.first_name, u.last_name, ts.status_name, tp.priority_name
ORDER BY t.task_id;
GO

--================================================================================                                                      
--	リファクタリング＃２：　非効率な結合をサブクエリへの移動
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
SELECT 
	t.task_id,
    t.task_name,
    t.due_date,
    u.first_name + ' ' + u.last_name AS assigned_user,
    ts.status_name,
    tp.priority_name,
    COUNT(DISTINCT td.dependency_id) AS dependency_count
FROM task t -- データテーブル
JOIN [user] u ON t.assigned_to_user_id = u.user_id       -- データテーブル
JOIN task_status ts ON t.status_id = ts.status_id        -- フィルタリングテーブル
JOIN task_priority tp ON t.priority_id = tp.priority_id  -- フィルタリングテーブル
JOIN project p ON t.project_id = p.project_id            -- ジャンクションテーブル
JOIN project_status ps ON p.status_id = ps.status_id     -- フィルタリングテーブル
LEFT JOIN task_dependency td ON td.task_id = t.task_id   -- 集約データテーブル
WHERE ts.status_name = 'On Track' 
  AND tp.priority_name IN ('High', 'Critical')
  AND ps.status_name = 'Active'
  AND u.is_active = 1
GROUP BY t.task_id, t.task_name, t.due_date, u.first_name, u.last_name, ts.status_name, tp.priority_name
ORDER BY t.task_id;
GO


--------------------------------
-- AFTER
--------------------------------
SELECT 
	t.task_id,
    t.task_name,
    t.due_date,
    u.first_name + ' ' + u.last_name AS assigned_user,
    ts.status_name,
    tp.priority_name,
    COALESCE(td_count.dependency_count, 0) AS dependency_count
FROM task t
JOIN [user] u ON t.assigned_to_user_id = u.user_id
JOIN task_status ts ON t.status_id = ts.status_id
JOIN task_priority tp ON t.priority_id = tp.priority_id
JOIN project p ON t.project_id = p.project_id
JOIN project_status ps ON p.status_id = ps.status_id
LEFT JOIN (
	SELECT 
		task_id, 
		COUNT(dependency_id) AS dependency_count
	FROM task_dependency
	GROUP BY task_id
) td_count ON td_count.task_id = t.task_id
WHERE ts.status_name = 'On Track' 
  AND tp.priority_name IN ('High', 'Critical')
  AND ps.status_name = 'Active'
  AND u.is_active = 1
ORDER BY t.task_id;
GO
