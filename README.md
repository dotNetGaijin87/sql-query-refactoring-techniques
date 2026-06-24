# SQL クエリリファクタリング手法

SQL Server（T-SQL）のクエリを **BEFORE / AFTER** で書き換え、**実行プラン**と **論理読み取り数**で
「なぜ速くなるのか」を可視化するリポジトリです。

## 手法一覧

| #   | 手法                                               | 場所                                                        |
| :-- | :------------------------------------------------- | :---------------------------------------------------------- |
| 1   | ウィンドウ関数で無駄なテーブルアクセスを削減       | [03](03_不要なテーブルアクセスのリファクタリング.sql#L16)   |
| 2   | 一時テーブルで重複スキャンを削減                   | [03](03_不要なテーブルアクセスのリファクタリング.sql#L107)  |
| 3   | CASE 式で一括更新                                  | [03](03_不要なテーブルアクセスのリファクタリング.sql#L207)  |
| 4   | 最上位の DISTINCT をサブクエリへ                   | [04](04_非効率的なフィルタリングのリファクタリング.sql#L15) |
| 5   | 最上位の GROUP BY をサブクエリへ                   | [04](04_非効率的なフィルタリングのリファクタリング.sql#L57) |
| 6   | 複数 IF-ELSE を CASE 式に（カーソル → 集合ベース） | [05](05_IF_ELSE_ステートメントのリファクタリング.sql#L18)   |
| 7   | 防御 IF をなくす                                   | [05](05_IF_ELSE_ステートメントのリファクタリング.sql#L79)   |
| 8   | `IF ... IS NULL` を `ISNULL` に                    | [05](05_IF_ELSE_ステートメントのリファクタリング.sql#L128)  |
| 9   | 優先順位 UPDATE を CASE 式に                       | [05](05_IF_ELSE_ステートメントのリファクタリング.sql#L208)  |
| 10  | 複数サブクエリを GROUP BY + CASE に                | [06](06_非効率的な集約のリファクタリング.sql#L16)           |
| 11  | 自己結合をウィンドウ関数に                         | [06](06_非効率的な集約のリファクタリング.sql#L53)           |

## ハイライト：手法＃11（自己結合 → ウィンドウ関数）

相関サブクエリの自己結合が `task_comment`（20 万行）を繰り返しスキャンするため論理読み取りは **1,535,494**。
`LAG()` / `ROW_NUMBER()` に置き換えると **1,714** まで激減します（**約 900 分の 1**、CPU 2,130 → 395 ms）。

<table>
<thead>
<tr>
<th width="50%">🐢 BEFORE — 相関サブクエリによる自己結合</th>
<th width="50%">🚀 AFTER — ウィンドウ関数（LAG / ROW_NUMBER）</th>
</tr>
</thead>
<tbody>

<tr><td colspan="2" align="center"><b>① SQL コード</b></td></tr>
<tr>
<td>

```sql
-- 行ごとに相関サブクエリが task_comment を読み直す
SELECT t.task_id, ts.status_name, tc.created_at AS status_changed_at,
    DATEDIFF(MINUTE,
        (SELECT MAX(tc2.created_at) FROM task_comment tc2
         WHERE tc2.task_id = t.task_id
           AND (tc2.created_at < tc.created_at
                OR (tc2.created_at = tc.created_at
                    AND tc2.comment_id < tc.comment_id))),
        tc.created_at) AS time_in_previous_status,
    (SELECT COUNT(*) FROM task_comment tc2
     WHERE tc2.task_id = t.task_id
       AND (tc2.created_at < tc.created_at
            OR (tc2.created_at = tc.created_at
                AND tc2.comment_id <= tc.comment_id))) AS status_change_order
FROM task t
JOIN task_status ts ON t.status_id = ts.status_id
JOIN task_comment tc ON t.task_id = tc.task_id
WHERE ts.status_name IN ('On Track', 'Delayed')
ORDER BY t.task_id, tc.created_at, tc.comment_id;
```

</td>
<td>

```sql
-- task_comment は 1 回のスキャンで、計算はパーティション内で完結
SELECT t.task_id, ts.status_name, tc.created_at AS status_changed_at,
    DATEDIFF(MINUTE,
        LAG(tc.created_at) OVER (
            PARTITION BY t.task_id ORDER BY tc.created_at),
        tc.created_at) AS time_in_previous_status,
    ROW_NUMBER() OVER (
        PARTITION BY t.task_id ORDER BY tc.created_at) AS status_change_order
FROM task t
JOIN task_status ts ON t.status_id = ts.status_id
JOIN task_comment tc ON t.task_id = tc.task_id
WHERE ts.status_name IN ('On Track', 'Delayed')
ORDER BY t.task_id, tc.created_at, tc.comment_id;
```

</td>
</tr>

<tr><td colspan="2" align="center"><b>② 実行プラン（Execution plan）</b><br><sub>SQL Server がクエリを内部でどう処理するかを示す図。データは右 → 左に流れる（クリックで拡大）</sub></td></tr>
<tr>
<td><a href="docs/execution-plans/img/t11_before.png"><img src="docs/execution-plans/img/t11_before.png" width="100%" alt="BEFORE の実行プラン（クリックで拡大）"></a></td>
<td><a href="docs/execution-plans/img/t11_after.png"><img src="docs/execution-plans/img/t11_after.png" width="100%" alt="AFTER の実行プラン（クリックで拡大）"></a></td>
</tr>

<tr><td colspan="2" align="center"><b>③ 計測値（論理読み取り ／ CPU ／ 実行時間）</b></td></tr>
<tr>
<td align="center">論理読み取り <b>1,535,494</b> ／ CPU 2,130 ms ／ 1.10 s</td>
<td align="center">論理読み取り <b>1,714</b> ／ CPU 395 ms ／ 0.11 s</td>
</tr>

</tbody>
</table>

> **実行プランの図の見方**：各ボックスは「物理演算子／対象オブジェクト／推定行数・コスト%」。
> 青＝スキャン、オレンジ＝結合、赤＝ソート、紫＝スプール。データの流れは右 → 左。
> 図は **推定実行プラン**（`SET SHOWPLAN_XML`）。

## 使い方

1. `01_スキーマの作成.sql` を実行してサンプル DB `SqlRefactoring` を作成。
2. `02` 以降を番号順に開き、BEFORE / AFTER を実行して比較。
3. `SET STATISTICS IO, TIME ON;` を有効にし、主に **論理読み取り数** で評価。

## もっと見る

- 全手法の **BEFORE / AFTER 実行プラン**＋計測値 → **[docs/execution-plans/](docs/execution-plans/)**
- 複雑なクエリを段階的に書き換える **ケーススタディ（v1 → v6）** → [07\_複雑なクエリのリファクタリング.sql](07_複雑なクエリのリファクタリング.sql)

## 動作環境・ライセンス

- Microsoft SQL Server 2019 以降（補足例で 2022 の `GENERATE_SERIES` を使用）／ SSMS または Azure Data Studio
- [MIT License](LICENSE)
