-----------------------------------------------------------------------------------
--
--   サンプルスキーマの作成
--  
--    
--   このSQLスクリプトは、SQLリファクタリング手法を紹介するための基盤となるサンプルスキーマを作成します。 
--   このスクリプトを基に、以降のスクリプトでSQLリファクタリング手法を紹介していきます。 
-- 
--   主な処理内容：
--   　- `SqlRefactoring` データベース（プロジェクト管理システム向け）を作成（存在しない場合）
--   　- 既存のテーブルやストアドプロシージャがある場合、削除（クリーンアップ）
--   　- テーブル作成（user、project、task、teamなど）
--   　- インデックスの作成
--   　- サンプルデータの挿入
--     
-----------------------------------------------------------------------------------

IF NOT EXISTS(SELECT * FROM sys.databases WHERE name = 'SqlRefactoring')
	BEGIN
		CREATE DATABASE SqlRefactoring;
	END
GO

USE SqlRefactoring;
GO

SET NOCOUNT ON;

-- オブジェクトのクリーンアップ
DROP TABLE IF EXISTS task_comment;
DROP TABLE IF EXISTS task_dependency;
DROP TABLE IF EXISTS team_membership;
DROP TABLE IF EXISTS team;
DROP TABLE IF EXISTS task;
DROP TABLE IF EXISTS project;
DROP TABLE IF EXISTS [user];
DROP TABLE IF EXISTS team_membership_role;
DROP TABLE IF EXISTS user_role;
DROP TABLE IF EXISTS task_status;
DROP TABLE IF EXISTS task_priority;
DROP TABLE IF EXISTS project_status;
DROP TABLE IF EXISTS project_priority;
DROP PROCEDURE IF EXISTS usp_update_task_status_BEFORE;
DROP PROCEDURE IF EXISTS usp_update_task_status_AFTER;
DROP PROCEDURE IF EXISTS usp_update_project_status_when_all_tasks_completed_BEFORE;
DROP PROCEDURE IF EXISTS usp_update_project_status_when_all_tasks_completed_AFTER;
GO

-- ルックアップテーブルの作成
CREATE TABLE task_status (
	status_id	INT IDENTITY(1,1) PRIMARY KEY,
	status_name	NVARCHAR(50) NOT NULL
);

CREATE TABLE task_priority (
	priority_id		INT IDENTITY(1,1) PRIMARY KEY,
	priority_name	NVARCHAR(50) NOT NULL
);

CREATE TABLE project_status (
	status_id	INT IDENTITY(1,1) PRIMARY KEY,
	status_name	NVARCHAR(50) NOT NULL
);

CREATE TABLE project_priority (
	priority_id		INT IDENTITY(1,1) PRIMARY KEY,
	priority_name	NVARCHAR(50) NOT NULL
);

CREATE TABLE user_role (
	role_id		INT IDENTITY(1,1) PRIMARY KEY,
	role_name	NVARCHAR(50) NOT NULL
);

CREATE TABLE team_membership_role (
	role_id		INT IDENTITY(1,1) PRIMARY KEY,
	role_name	NVARCHAR(50) NOT NULL
);
GO


-- 通常テーブルの作成
CREATE TABLE [user] (
	user_id            INT IDENTITY(1,1) PRIMARY KEY,
	first_name         NVARCHAR(50) NOT NULL,
	last_name          NVARCHAR(50) NOT NULL,
	email              NVARCHAR(255) NOT NULL UNIQUE,
	phone_number       NVARCHAR(15) NULL,
	registration_date  DATE NOT NULL DEFAULT GETDATE(),
	is_active          BIT NOT NULL DEFAULT 1
);

CREATE TABLE project (
	project_id		INT IDENTITY(1,1) PRIMARY KEY,
	project_name	NVARCHAR(100) NOT NULL,
	start_date		DATE NOT NULL,
	end_date		DATE NULL,
	budget			DECIMAL(15, 2) NULL,
	status_id		INT NOT NULL,
	priority_id		INT NOT NULL
);

CREATE TABLE task (
	task_id				INT IDENTITY(1,1) PRIMARY KEY,
	project_id			INT NOT NULL,
	assigned_to_user_id	INT NULL,
	task_name			NVARCHAR(100) NOT NULL,
	due_date			DATE NULL,
	status_id			INT NOT NULL,
	priority_id			INT NOT NULL,
	CONSTRAINT fk_task_project FOREIGN KEY (project_id) REFERENCES project(project_id),
	CONSTRAINT fk_task_user FOREIGN KEY (assigned_to_user_id) REFERENCES [user](user_id),
	CONSTRAINT fk_task_status FOREIGN KEY (status_id) REFERENCES task_status(status_id),
	CONSTRAINT fk_task_priority FOREIGN KEY (priority_id) REFERENCES task_priority(priority_id)
);

CREATE TABLE task_comment (
	comment_id   INT IDENTITY(1,1) PRIMARY KEY,
	task_id      INT NOT NULL,
	user_id      INT NOT NULL,
	comment_text NVARCHAR(500) NOT NULL,
	created_at   DATETIME NOT NULL DEFAULT GETDATE(),
	CONSTRAINT fk_task_comment_task FOREIGN KEY (task_id) REFERENCES task(task_id),
	CONSTRAINT fk_task_comment_user FOREIGN KEY (user_id) REFERENCES [user](user_id)
);
GO

CREATE TABLE team (
	team_id	INT IDENTITY(1,1) PRIMARY KEY,
	team_name NVARCHAR(100) NOT NULL
);

CREATE TABLE team_membership (
	team_membership_id INT IDENTITY(1,1) PRIMARY KEY,
	team_id            INT NOT NULL,
	user_id            INT NOT NULL,
	role_id            INT NOT NULL,
	CONSTRAINT fk_team_membership_team FOREIGN KEY (team_id) REFERENCES team(team_id),
	CONSTRAINT fk_team_membership_user FOREIGN KEY (user_id) REFERENCES [user](user_id),
	CONSTRAINT fk_team_membership_role FOREIGN KEY (role_id) REFERENCES team_membership_role(role_id)
);

CREATE TABLE task_dependency (
	dependency_id      INT IDENTITY(1,1) PRIMARY KEY,
	task_id            INT NOT NULL,
	depends_on_task_id INT NOT NULL,
	CONSTRAINT fk_task_dependency_task FOREIGN KEY (task_id) REFERENCES task(task_id),
	CONSTRAINT fk_task_dependency_dependent_task FOREIGN KEY (depends_on_task_id) REFERENCES task(task_id),
	CONSTRAINT chk_task_dependency_no_self_dependency CHECK (task_id <> depends_on_task_id)
);
GO


-- インデックスの作成
CREATE INDEX idx_task_project ON task (project_id);
CREATE INDEX idx_task_status_priority ON task (status_id, priority_id);
CREATE INDEX idx_task_assigned_user ON task (assigned_to_user_id);
CREATE INDEX idx_task_due_date ON task (due_date);
CREATE INDEX idx_task_comment_user_id ON task_comment (user_id);
CREATE INDEX idx_task_comment_task_id ON task_comment (task_id);
CREATE INDEX idx_task_dependency_task ON task_dependency (task_id);
CREATE INDEX idx_task_dependency_depends_on_task ON task_dependency (depends_on_task_id);
CREATE INDEX idx_project_name ON project (project_name);
CREATE INDEX idx_project_status ON project (status_id);
CREATE INDEX idx_project_start_date ON project ([start_date]);
CREATE NONCLUSTERED INDEX idx_project_status_id_start_date_project_name　ON project (status_id, [start_date]) INCLUDE (project_name);
CREATE INDEX idx_user_email ON [user] (email);
CREATE INDEX idx_team_name ON team (team_name);
CREATE INDEX idx_team_membership_team_user ON team_membership (team_id, user_id);


-- サンプルデータの挿入
INSERT INTO team_membership_role (role_name) VALUES 
('Team Member'),
('Team Lead'),
('Project Manager');

INSERT INTO user_role (role_name) VALUES 
('Admin'),
('User'),
('Viewer');

INSERT INTO task_status (status_name) VALUES 
('Not Started'),
('On Track'),
('Risk of Delay'),
('Delayed'),
('Completed'),
('Cancelled');

INSERT INTO task_priority (priority_name) VALUES 
('Low'),
('Medium'),
('High'),
('Critical');

INSERT INTO project_status (status_name) VALUES 
('Proposed'),
('Active'),
('Delayed'),
('Completed'),
('Cancelled');

INSERT INTO project_priority (priority_name) VALUES 
('Low'),
('Medium'),
('High'),
('Critical');



DECLARE @current_date DATETIME = CAST('2025-06-30' AS DATE);

INSERT INTO [user] (first_name, last_name, email, phone_number, registration_date, is_active)
SELECT 
    'UserFirstName' + CAST(user_id AS NVARCHAR(10)),
    'UserLastName' + CAST(user_id AS NVARCHAR(10)),
    'user' + CAST(user_id AS NVARCHAR(10)) + '@example.com',
    '123-456-0000',
    DATEADD(DAY, user_id % 10, @current_date),
    1
FROM (
    SELECT TOP 100 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS user_id
    FROM master.dbo.spt_values
) AS user_ids;


WITH project_ids AS (
    SELECT 1 AS project_id
    UNION ALL
    SELECT project_id + 1
    FROM project_ids
    WHERE project_id < 10000
)
INSERT INTO project (project_name, start_date, end_date, budget, status_id, priority_id)
SELECT 
    'Project_' + CAST(project_id AS NVARCHAR(10)),
    DATEADD(DAY, project_id % 123, @current_date),
    CASE 
        WHEN project_id % 7 = 0 THEN DATEADD(DAY, (project_id % 123) + 7, @current_date) 
        ELSE NULL 
    END,
    100000.00 + project_id,
    CASE 
        WHEN project_id % 5 = 1 THEN 1
        WHEN project_id % 5 = 2 THEN 2
        WHEN project_id % 5 = 3 THEN 3
        WHEN project_id % 5 = 4 THEN 4
        ELSE 5                   
    END,  
    CASE 
        WHEN project_id % 4 = 1 THEN 1
        WHEN project_id % 4 = 2 THEN 2
        WHEN project_id % 4 = 3 THEN 3
        ELSE 4                    
    END
FROM project_ids
OPTION (MAXRECURSION 0);


WITH task_ids AS (
    SELECT TOP 50000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS task_id
    FROM master.dbo.spt_values AS t1
    CROSS JOIN master.dbo.spt_values AS t2
)
INSERT INTO task (project_id, assigned_to_user_id, task_name, due_date, status_id, priority_id)
SELECT 
    (task_id % 10000) + 1 AS project_id,
    CASE 
        WHEN task_id % 10 = 0 THEN 1
        WHEN task_id % 7 = 0 THEN (task_id % 20) + 1
        WHEN task_id % 5 = 0 THEN (task_id % 50) + 1 
        ELSE (task_id % 100) + 1
    END AS assigned_to_user_id,
    'Task_' + CAST(task_id AS NVARCHAR(10)) AS task_name,
    CASE 
        WHEN (task_id % 3 = 0) THEN DATEADD(DAY, (task_id % 30), @current_date)
        WHEN (task_id % 7 = 0) THEN DATEADD(DAY, (task_id % 90), @current_date)
        ELSE DATEADD(DAY, (task_id % 60), @current_date)
    END AS due_date,
    ((task_id % 5) + 1) AS status_id,
    ((task_id % 4) + 1) AS priority_id
FROM task_ids;


WITH comment_ids AS (
    SELECT TOP 200000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS comment_id
    FROM master.dbo.spt_values t1
    CROSS JOIN master.dbo.spt_values t2
)
INSERT INTO task_comment (task_id, user_id, comment_text, created_at)
SELECT 
    t.task_id,  
    ((comment_id % 100) + 1) AS user_id,
    'Comment_' + CAST(comment_id AS NVARCHAR(10)), 
    DATEADD(DAY, 
        ISNULL(comment_id % NULLIF(DATEDIFF(DAY, p.start_date, t.due_date), 0), 1),
        p.start_date
    ) 
FROM comment_ids
JOIN task t ON ((comment_id % 50000) + 1) = t.task_id 
JOIN project p ON t.project_id = p.project_id
OPTION (MAXRECURSION 0);


WITH team_ids AS (
    SELECT 1 AS team_id
    UNION ALL
    SELECT team_id + 1 FROM team_ids WHERE team_id < 50
)
INSERT INTO team (team_name)
SELECT 'Team_' + CAST(team_id AS NVARCHAR(10))
FROM team_ids
OPTION (MAXRECURSION 0);

DECLARE @task_id INT = 2;
DECLARE @dependency_id INT;

WHILE @task_id <= 10000
BEGIN
    IF @task_id % 5 = 0
    BEGIN

        INSERT INTO task_dependency (task_id, depends_on_task_id)
        VALUES (@task_id, @task_id - 1);
        INSERT INTO task_dependency (task_id, depends_on_task_id)
        VALUES (@task_id, @task_id - 2);
        INSERT INTO task_dependency (task_id, depends_on_task_id)
        VALUES (@task_id, @task_id - 3);
    END

    ELSE IF @task_id % 3 = 0
    BEGIN
        INSERT INTO task_dependency (task_id, depends_on_task_id)
        VALUES (@task_id, @task_id - 1);
        INSERT INTO task_dependency (task_id, depends_on_task_id)
        VALUES (@task_id, @task_id - 2);
    END
    ELSE
    BEGIN
        INSERT INTO task_dependency (task_id, depends_on_task_id)
        VALUES (@task_id, @task_id - 1);
    END

    SET @task_id = @task_id + 1;
END
GO

DECLARE @user_id INT = 1;
DECLARE @total_users INT = 100;
DECLARE @total_teams INT = 50;

WHILE @user_id <= @total_users
BEGIN
    DECLARE @team_id INT = (@user_id % @total_teams) + 1;
    INSERT INTO team_membership (team_id, user_id, role_id)
    VALUES 
    (
        @team_id, 
        @user_id, 
        CASE 
            WHEN @user_id % 5 = 1 THEN 2 
            WHEN @user_id % 10 = 0 THEN 3
            ELSE 1
        END
    );
    SET @user_id = @user_id + 1;
END
GO