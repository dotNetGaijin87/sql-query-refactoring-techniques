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

/*  
　　
    クエリ構成上のテーブルは大きく４種類に分類できる：

    - データテーブル
      データテーブルはクエリの核となっている

    - ジャンクションテーブル
      ジャンクションテーブルは多対多の関係を解決するためのものである

    - フィルタリングテーブル
      フィルタリングテーブルは WHERE 句の条件を提供する

　　- 集約データテーブル
　　　集約データテーブルは集約した形でデータを提供する
　 
　　上記のリストに該当しないテーブルは不要なテーブルだと判断できる。
　　今回のリファクタリングでは不要なテーブルを削除してクエリのパフォーマンスを向上させる。
*/

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
JOIN team_membership tm ON tm.user_id = u.user_id        -- 「不要なテーブル 」
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


--------------------------------
-- リファクタリングの効果
--------------------------------
-- BEFORE: 'team_membership':  logical reads 2
-- AFTER:  'team_membership':  logical reads 0
-- 今回の効果が大きくなかったが、不要なテーブルを削除するこでクエリの実行時間が１０倍、１００倍早くなるケースを見たことある。



--================================================================================                                                      
--	リファクタリング＃２：　非効率な結合をサブクエリへの移動
--================================================================================

/*  
    効率的なクエリを作成するためのさまざまな手法があります。
    その中の一つがサブクエリです。

    今回のリファクタリングでは、task_dependencyテーブル（集約データテーブル）とそのGROUP BYをJOIN句内のサブクエリに移動させることで、
    クエリのパフォーマンスを改善させる。 
    　
*/

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


--------------------------------
-- リファクタリングの効果
--------------------------------
-- BEFORE: 
--        'task_dependency': Scan count 5000, logical reads 10646,
--         CPU time = 16 ms
-- 
-- AFTER: 
--　　　   'task_dependency': Scan count 1, logical reads 31
--         CPU time = 0 ms