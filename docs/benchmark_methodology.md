# Benchmark methodology

Per run: elapsed time (`SYSTIMESTAMP` in SQL, `time.perf_counter()` in Python), CPU, and `V$MYSTAT` deltas for consistent gets, db block gets, physical reads and redo size, plus the number of rows written as a sanity check. V$MYSTAT is session-wide, so it includes the SQL inside the procedure. Consistent gets are the most stable measure of work done.

Protocol:
1. The same dataset and report month (`DATASET_INFO.REPORT_MONTH`) for every version.
2. Steps 2, 6 and 7 change plans for every version, so each version is measured right after its own step and the batch is labelled `after_stepN`.
3. 1 warm-up run, not recorded, then 5 measured runs. I report the median, plus min and max.
4. Plans are captured in a separate run (`statistics_level = ALL` adds overhead).
5. A timing counts only if `01_verify_correctness.sql` shows PASS.

The numbers are warm-cache: mostly CPU and logical I/O. Cold runs also pay physical I/O, which depends on storage and the OS cache. Flushing the buffer cache needs `ALTER SYSTEM`, which ADB doesn't allow and which shouldn't be done on a shared box. If you measure cold runs, give them their own label, for example `--label cold_after_step4 --warmup 0 --runs 1`.

Other sources of noise: load on shared hosts, adaptive plans and statistics feedback (partly absorbed by the warm-up), the automatic stats job running between steps (check `LAST_ANALYZED`), and ADB service parallelism (use `_tp` or `_low`).
