# Step 5: BULK COLLECT and FORALL

`04_optimization_steps/05_bulk_collect_forall.sql`, rollback `05_bulk_collect_forall_rollback.sql`, procedure `REPORT_TOP_CUSTOMERS_V5`.

This covers the case where a report really needs row-level PL/SQL, such as an existing validation package, complex rules or auditing. The pattern:

1. The V4 query does all joining, filtering and ranking as an explicit cursor.
2. `FETCH ... BULK COLLECT ... LIMIT 500` gives one context switch per batch, and LIMIT caps PGA.
3. The row logic runs on the in-memory collection. Here it is a data-quality guard plus building the record.
4. `FORALL ... INSERT ... VALUES l_out(i)` sends the whole batch in one call.
5. One COMMIT. On error the cursor is closed and the transaction is rolled back.

I expect V5 to be about as fast as V4, not faster. When the logic fits in SQL, V4 is the better answer. Record inserts bypass column defaults, so `created_at` is set explicitly. A cursor FOR loop is array-fetched too (100 rows), but that does not fix N+1 when there is SQL inside the loop.
