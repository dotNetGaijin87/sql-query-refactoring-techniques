# SQLクエリリファクタリング手法

このリポジトリには、SQLクエリのパフォーマンスと可読性を向上させるためのリファクタリング手法を紹介します。

## 内容
スクリプト01 は、サンプルデータベースを作成するスキーマ作成スクリプトです。</br>
スクリプト02 では、クエリ内のテーブルの役割を特定する方法を解説します。</br>
スクリプト03～06 では、さまざまなリファクタリング手法を紹介します。</br>
最後のスクリプト07 は、複雑なクエリのステップごとのリファクタリングを扱うケーススタディです。</br>

## 取り扱っている手法の一覧
- 手法＃１：ウィンドウ関数による無駄なテーブルアクセス削減
- 手法＃２：一時テーブルによる重複スキャン削減
- 手法＃３：CASE式による一括更新
- 手法＃４：最上位クエリでのDISTINCTをサブクエリに移動
- 手法＃５：最上位クエリでのGROUP BYをサブクエリに移動
- 手法＃６：複数IF-ELSEをCASE式で解決
- 手法＃７：防御IFをなくす
- 手法＃８：IF ... IS NULLをISNULL関数で解決
- 手法＃９：優先順位UPDATEをCASE式で解決
- 手法＃１０：SELECT文の複数サブクエリをGROUP BYとCASE式に置換
- 手法＃１１：SELECT文の自己結合をウィンドウ関数に置換

## 例
```SQL
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
```