# results/plans/

Plan files are written here by the SQL scripts (run them from the project root so the relative `SPOOL` path resolves):

- `step1_explain_plan.txt` ... `step4_explain_plan.txt`: from `04_optimization_steps/0N_*.sql` (EXPLAIN PLAN, estimates only).
- `<VERSION>_plan.txt`: from `05_benchmark/03_capture_plan.sql <VERSION>` (DISPLAY_CURSOR, ALLSTATS LAST, the plans that actually ran).

The folder is empty until you run the scripts. This README keeps it in the repository, because SQL*Plus cannot spool into a folder that does not exist.
