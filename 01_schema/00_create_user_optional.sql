-- Optional, run as DBA (ADMIN on Autonomous): creates the demo schema.
-- Prompts for name, password (hidden, never stored) and default tablespace.
SET VERIFY OFF
SET FEEDBACK ON

ACCEPT demo_user CHAR DEFAULT 'PERF_DEMO' PROMPT 'Schema name [PERF_DEMO]: '
ACCEPT demo_pwd  CHAR PROMPT 'Password for the new schema: ' HIDE
ACCEPT demo_tbs  CHAR DEFAULT 'USERS' PROMPT 'Default tablespace [USERS] (use DATA on Autonomous Database): '

CREATE USER &demo_user IDENTIFIED BY "&demo_pwd"
    DEFAULT TABLESPACE &demo_tbs
    QUOTA UNLIMITED ON &demo_tbs;

-- CREATE SEQUENCE: identity column in BENCHMARK_RUNS. CREATE MATERIALIZED VIEW: step 7a only.
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE, CREATE VIEW,
      CREATE SEQUENCE, CREATE MATERIALIZED VIEW
   TO &demo_user;

-- V$ views for the benchmark and DISPLAY_CURSOR. Where direct grants are refused
-- (some managed services), SELECT_CATALOG_ROLE is enough: PERF_BENCH uses invoker
-- rights and dynamic SQL.
GRANT SELECT ON sys.v_$mystat                 TO &demo_user;
GRANT SELECT ON sys.v_$statname               TO &demo_user;
GRANT SELECT ON sys.v_$sql                    TO &demo_user;
GRANT SELECT ON sys.v_$sql_plan               TO &demo_user;
GRANT SELECT ON sys.v_$sql_plan_statistics_all TO &demo_user;
GRANT SELECT ON sys.v_$session                TO &demo_user;

UNDEFINE demo_pwd
PROMPT Done. Connect as the new schema and run @01_schema/01_create_tables.sql
