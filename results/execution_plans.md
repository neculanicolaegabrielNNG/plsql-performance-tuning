# Execution plans (template)

Paste the relevant parts of the captured plans here and write what they show. Sources:

- `plans/step1_explain_plan.txt` ... `plans/step4_explain_plan.txt`: EXPLAIN PLAN, written by the step scripts. These are estimates only.
- `plans/<VERSION>_plan.txt`: DBMS_XPLAN.DISPLAY_CURSOR with `ALLSTATS LAST`, written by `05_benchmark/03_capture_plan.sql <VERSION>`. These are the plans that actually ran.

Columns to read in an `ALLSTATS LAST` plan:

| Column | Meaning | Why it matters here |
|---|---|---|
| Starts | how many times the plan line was executed | shows the N in N+1 |
| E-Rows | rows the optimizer expected | wrong estimates cause wrong plans |
| A-Rows | rows actually produced | compare with E-Rows |
| Buffers | logical reads (consistent gets) by the line | where the work is |
| A-Time | actual time spent in the line | where the time is |

---

## SLOW / V1 (after step 1)

Plan of the driver, the per-customer query and the last-payment query:

```
TBD
```

Observations: TBD

## V2 (after step 2, indexes)

```
TBD
```

Observations: TBD

## V3 (after step 3, sargable predicates)

```
TBD
```

Observations: TBD

## V4 (after step 4, set-based)

```
TBD
```

Observations: TBD

## V5 (after step 5, BULK COLLECT / FORALL)

```
TBD
```

Observations: TBD

## V6 (after step 6, statistics)

```
TBD
```

E-Rows vs A-Rows before (V4) and after (V6) statistics: TBD

Hint needed? TBD (state the evidence if yes)

## V7 / V7P (optional step 7)

```
TBD
```

Observations: TBD
