# Step 6: Statistics, hints only with evidence

`04_optimization_steps/06_statistics_and_hints.sql`, rollback `06_statistics_and_hints_rollback.sql`, procedure `REPORT_TOP_CUSTOMERS_V6` (V4's query, no hints).

Until this step the tables have no statistics, because they are deleted after the load. Every estimate therefore comes from dynamic sampling, and with whale customers and uneven statuses that can go badly wrong.

- `estimate_percent => AUTO_SAMPLE_SIZE`: accurate NDV at low cost.
- `method_opt => 'FOR ALL COLUMNS SIZE AUTO'`: histograms only on skewed columns used in predicates. Column usage was recorded while the earlier versions ran.
- `cascade => TRUE`, and `no_invalidate => FALSE`, so the benchmark doesn't keep running old plans for hours.
- The previous stats are exported to `STATS_BACKUP` first, so the rollback is exact.

No hint by default. I would add one only if `ALLSTATS LAST` still shows E-Rows far from A-Rows after stats, better stats (histograms, extended stats) don't fix it, and the evidence is in `results/execution_plans.md`. A SQL plan baseline or SQL patch is preferable to a hard-coded hint. V4 `after_step4` vs V6 `after_step6` runs the same SQL, so the difference comes from statistics alone.
