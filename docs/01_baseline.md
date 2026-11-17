# Step 1: Baseline

`04_optimization_steps/01_baseline_explain_plan.sql`, rollback `01_baseline_rollback.sql`, procedure `REPORT_TOP_CUSTOMERS_V1`.

V1 is SLOW with instrumentation and no SQL changes:
- `DBMS_APPLICATION_INFO` module/action, visible in `V$SESSION`, `V$SQL` and ASH,
- counters for customers visited, candidates, SQL executions in loops and COMMITs,
- phase timings with `DBMS_UTILITY.GET_TIME`.

The script also spools EXPLAIN PLAN for the three loop statements to `results/plans/step1_explain_plan.txt`. Things to look for: `TABLE ACCESS FULL` on ORDERS/PAYMENTS inside per-customer statements, `ORDER_DATE` appearing only in filter predicates, and "dynamic sampling used". The "SQL executions inside loops" counter is the N in N+1.

EXPLAIN PLAN does not execute the statement or peek binds, so it shows estimates. `05_benchmark/03_capture_plan.sql` shows the plan that actually ran, with `Starts`, `A-Rows` and `Buffers`.
