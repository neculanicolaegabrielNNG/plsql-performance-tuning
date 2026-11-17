-- Runs one version once and spools DISPLAY_CURSOR (ALLSTATS LAST) of its costliest cursors
-- to results/plans/<VERSION>_plan.txt. Usage: @05_benchmark/03_capture_plan.sql V4
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET LINESIZE 250
SET PAGESIZE 100
SET LONG 1000000
SET TRIMSPOOL ON
SET TRIMOUT ON

DEFINE version_code = '&1'

VARIABLE run_start VARCHAR2(19)

-- Like GATHER_PLAN_STATISTICS for every statement, without editing the procedures.
-- Adds overhead, so never time a run made this way.
ALTER SESSION SET statistics_level = ALL;

BEGIN
    :run_start := TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS');
    perf_bench.run_report('&version_code', perf_bench.dataset_month, 100);
END;
/

ALTER SESSION SET statistics_level = TYPICAL;

SPOOL results/plans/&version_code._plan.txt

PROMPT ===== Cursors executed by &version_code (EXECUTIONS are cumulative since the cursor was loaded) =====
COLUMN sql_id      FORMAT A13
COLUMN executions  FORMAT 999,999,990
COLUMN elapsed_s   FORMAT 999,990.99
COLUMN buffer_gets FORMAT 999,999,999,990
COLUMN sql_text    FORMAT A90
SELECT s.sql_id,
       s.child_number,
       s.executions,
       ROUND(s.elapsed_time / 1e6, 2) AS elapsed_s,
       s.buffer_gets,
       SUBSTR(s.sql_text, 1, 90) AS sql_text
  FROM v$sql s
 WHERE s.parsing_schema_name = USER
   AND s.last_active_time >= TO_DATE(:run_start, 'YYYY-MM-DD HH24:MI:SS')
   AND s.command_type IN (2, 3, 6, 7)
   AND LOWER(s.sql_text) NOT LIKE '%v$sql%'
 ORDER BY s.elapsed_time DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT ===== Plans (ALLSTATS LAST) of the 6 most expensive cursors =====
SET PAGESIZE 0
SELECT t.plan_table_output
  FROM (SELECT s.sql_id, s.child_number
          FROM v$sql s
         WHERE s.parsing_schema_name = USER
           AND s.last_active_time >= TO_DATE(:run_start, 'YYYY-MM-DD HH24:MI:SS')
           AND s.command_type IN (2, 3, 6, 7)
           AND LOWER(s.sql_text) NOT LIKE '%v$sql%'
         ORDER BY s.elapsed_time DESC
         FETCH FIRST 6 ROWS ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST +PEEKED_BINDS')) t;

SPOOL OFF
SET PAGESIZE 100
PROMPT Plan written to results/plans/&version_code._plan.txt
