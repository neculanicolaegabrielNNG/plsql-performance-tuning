# Benchmark comparison (template)

Fill this in after running the benchmark. Do not estimate: every `TBD` must be replaced by a measured value or stay `TBD`.

## Environment

| Item | Value |
|---|---|
| Oracle version and edition | TBD |
| Platform (local container / Autonomous Database / other) | TBD |
| CPU / memory available to the database | TBD |
| SCALE used | TBD |
| Rows: CUSTOMERS / PRODUCTS / ORDERS / ORDER_ITEMS / PAYMENTS | TBD / TBD / TBD / TBD / TBD |
| Report month | TBD |
| Date of the runs | TBD |
| Runs per version | 1 warm-up + 5 measured (median reported) |
| Cache state | warm (see "Cold vs warm cache" in the README) |

## Results

"Schema state" is the label used for the run (for example `after_step2`). Indexes, statistics and the materialized view change the plans of every version, so each version is measured right after its own step (see the benchmark protocol in the README).

| Version | Schema state | What changed | Median elapsed (s) | Min (s) | Max (s) | Median consistent gets | Median CPU (s) | Speed-up vs SLOW | Correctness |
|---|---|---|---|---|---|---|---|---|---|
| SLOW | after_step1 | baseline, all mistakes | TBD | TBD | TBD | TBD | TBD | 1.0 | reference |
| V1 | after_step1 | instrumentation only | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V2 | after_step2 | + indexes on join keys | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V3 | after_step3 | + sargable date range | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V4 | after_step4 | set-based SQL + analytic ranking | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V5 | after_step5 | BULK COLLECT / FORALL | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V6 | after_step6 | + optimizer statistics | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V7 (optional) | after_step7 | materialized view | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| V7P (optional) | after_step7 | partitioned copy of ORDERS | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

## Optional control measurements

| Version | Schema state | Purpose | Median elapsed (s) | Median consistent gets |
|---|---|---|---|---|
| SLOW | after_step2 | effect of the indexes alone on the original code | TBD | TBD |
| V4 | after_step6 | effect of statistics alone on the set-based query | TBD | TBD |

## Observations

- TBD (for example: which step gave the largest gain and why, based on the plans).
