-----------------------------------------------------------------------------------
--
-- 非効率的な集約のリファクタリング
--    
--        手法＃１０：SELECT文の複数サブクエリをGROUP BYとCASE式に置換
--        手法＃１１：SELECT文の自己結合をウィンドウ関数に置換
-- 
-----------------------------------------------------------------------------------
USE SqlRefactoring;
GO

SET STATISTICS IO ON;


--================================================================================                                                       
--   手法＃１０：SELECT文の複数サブクエリをGROUP BYとCASE式に置換
--================================================================================

--------------------------------
-- BEFORE
--------------------------------
SELECT
    p.project_id,
    p.project_name,    
    (SELECT MIN(due_date)
     FROM task t
     WHERE t.project_id = p.project_id) AS earliest_due_date,
    (SELECT MIN(t.due_date)
     FROM task t
     JOIN task_priority tp ON t.priority_id = tp.priority_id
     WHERE t.project_id = p.project_id
       AND tp.priority_name IN ('High', 'Critical')) AS earliest_high_priority_due_date
FROM project p;

--------------------------------
-- AFTER
--------------------------------
SELECT 
    p.project_id,
    p.project_name,
    MIN(t.due_date) AS earliest_due_date,
    MIN(CASE 
            WHEN tp.priority_name IN ('High', 'Critical') THEN t.due_date 
            ELSE NULL 
        END) AS earliest_high_priority_due_date
FROM project p
JOIN task t ON t.project_id = p.project_id
JOIN task_priority tp ON t.priority_id = tp.priority_id
GROUP BY p.project_id, p.project_name;


--================================================================================                                                       
--   手法＃１１：SELECT文の自己結合をウィンドウ関数に置換
--================================================================================


--------------------------------
-- BEFORE
--------------------------------
SELECT 
    t.task_id,
    ts.status_name,
    tc.created_at AS status_changed_at,
    DATEDIFF(MINUTE, 
             (SELECT MAX(tc2.created_at) 
              FROM task_comment tc2 
              WHERE tc2.task_id = t.task_id 
                AND (tc2.created_at < tc.created_at OR 
                     (tc2.created_at = tc.created_at AND tc2.comment_id < tc.comment_id))),
             tc.created_at) AS time_in_previous_status,
    (SELECT COUNT(*) 
     FROM task_comment tc2 
     WHERE tc2.task_id = t.task_id 
       AND (tc2.created_at < tc.created_at OR 
            (tc2.created_at = tc.created_at AND tc2.comment_id <= tc.comment_id))) AS status_change_order
FROM task t
JOIN task_status ts ON t.status_id = ts.status_id
JOIN task_comment tc ON t.task_id = tc.task_id
WHERE ts.status_name IN ('On Track', 'Delayed') 
ORDER BY t.task_id, tc.created_at, tc.comment_id;


--------------------------------
-- AFTER
--------------------------------
SELECT 
    t.task_id,
    ts.status_name,
    tc.created_at AS status_changed_at,
    DATEDIFF(MINUTE, 
             LAG(tc.created_at) OVER (PARTITION BY t.task_id ORDER BY tc.created_at),
             tc.created_at) AS time_in_previous_status,
    ROW_NUMBER() OVER (PARTITION BY t.task_id ORDER BY tc.created_at) AS status_change_order
FROM task t
JOIN task_status ts ON t.status_id = ts.status_id
JOIN task_comment tc ON t.task_id = tc.task_id
WHERE ts.status_name IN ('On Track', 'Delayed');