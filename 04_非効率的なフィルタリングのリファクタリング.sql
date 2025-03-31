-----------------------------------------------------------------------------------
--
--	非効率的なフィルタリングのリファクタリング
--       
--		手法＃４：最上位クエリでのDISTINCTをサブクエリに移動
--		手法＃５：最上位クエリでのGROUP BYをサブクエリに移動
-- 
-----------------------------------------------------------------------------------
USE SqlRefactoring;
GO

SET STATISTICS IO ON;

--================================================================================                                                       
--  手法＃４：最上位クエリでのDISTINCTをサブクエリに移動
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
SELECT DISTINCT 
	   u.user_id, 
	   u.first_name, 
	   u.last_name
FROM [user] u
JOIN task t ON u.user_id = t.assigned_to_user_id
JOIN project p ON t.project_id = p.project_id
JOIN project_status ps ON p.status_id = ps.status_id
JOIN team_membership tm ON u.user_id = tm.user_id
JOIN team tteam ON tm.team_id = tteam.team_id
WHERE ps.status_name = 'Active'
  AND tteam.team_name = 'Team_3'
ORDER BY user_id;

--------------------------------
-- AFTER
--------------------------------
SELECT 
	u.user_id, 
	u.first_name, 
	u.last_name
FROM [user] u
JOIN team_membership tm ON u.user_id = tm.user_id
JOIN team tteam ON tm.team_id = tteam.team_id
JOIN (
	SELECT DISTINCT t.assigned_to_user_id
	FROM task t
	JOIN project p ON t.project_id = p.project_id
	JOIN project_status ps ON p.status_id = ps.status_id
	WHERE ps.status_name = 'Active'
) AS active_tasks ON u.user_id = active_tasks.assigned_to_user_id
WHERE tteam.team_name = 'Team_3'
ORDER BY user_id;


--================================================================================                                                       
--  手法＃５：最上位クエリでのGROUP BYをサブクエリに移動
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
SELECT TOP 5 
    u.user_id,
    u.first_name, 
    u.last_name, 
    COALESCE(COUNT(DISTINCT t.task_id), 0) AS total_tasks,
    COALESCE(AVG(CAST(DATEDIFF(DAY, t.due_date, '2025-08-12') AS FLOAT)), 0) AS avg_completion_days,
    COUNT(DISTINCT tc.comment_id) AS total_comments
FROM [user] u
JOIN task_comment tc ON u.user_id = tc.user_id
JOIN task t ON u.user_id = t.assigned_to_user_id
JOIN task_status ts ON t.status_id = ts.status_id
JOIN task_priority tp ON t.priority_id = tp.priority_id
WHERE ts.status_name = 'Completed' 
  AND tp.priority_name IN ('High', 'Critical')
GROUP BY u.user_id, u.first_name, u.last_name
ORDER BY COUNT(DISTINCT t.task_id) DESC, u.user_id ASC;


--------------------------------
-- AFTER
--------------------------------
SELECT  
    tc.user_id, 
    u.first_name, 
    u.last_name, 
    ts.total_tasks,
    ts.avg_completion_days,
    COUNT(tc.comment_id) AS total_comments
FROM [user] u 
JOIN task_comment tc ON tc.user_id = u.user_id
JOIN (
    SELECT TOP 5 
        t.assigned_to_user_id,
        COUNT(t.task_id) AS total_tasks,
        AVG(CAST(DATEDIFF(DAY, t.due_date, '2025-08-12') AS FLOAT)) AS avg_completion_days
    FROM task t
    JOIN task_status ts ON t.status_id = ts.status_id
    JOIN task_priority tp ON t.priority_id = tp.priority_id
    WHERE ts.status_name = 'Completed' 
      AND tp.priority_name IN ('High', 'Critical')
    GROUP BY t.assigned_to_user_id
    ORDER BY total_tasks DESC
) ts ON u.user_id = ts.assigned_to_user_id
GROUP BY tc.user_id, u.first_name, u.last_name, ts.total_tasks, ts.avg_completion_days
ORDER BY ts.total_tasks DESC, tc.user_id;
