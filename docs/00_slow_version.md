# Slow version

`03_slow_version/01_report_top_customers_slow.sql` is correct and is the reference for every other version. The mistakes are marked `slow #n` in the code.

| # | Mistake | Why it hurts | Fixed in |
|---|---|---|---|
| 1 | Row-by-row cursor with SELECTs inside (N+1) | N customers mean N (and 2N) separate executions, each with a context switch | step 4 (step 5 if PL/SQL is needed) |
| 2 | `TO_CHAR`/`TRUNC` on `order_date` in WHERE | computed for every row, so no index on the date can narrow the search | step 3 |
| 3 | `SELECT *` | reads columns nobody needs and rules out covering indexes | step 4 |
| 4 | No indexes on `ORDERS.CUSTOMER_ID`, `PAYMENTS.ORDER_ID` | every per-customer query is a full scan | step 2 |
| 5 | Correlated subqueries | repeated per row instead of one join and aggregation | step 4 |
| 6 | COMMIT after every row | a log file sync per row, a half-finished report is visible, partial data on failure | step 4 |
| – | No optimizer statistics | dynamic sampling only, poor with skewed data | step 6 |

The work is roughly *(customers in the month) × (rows in ORDERS + PAYMENTS)*. Both factors grow with SCALE, so the cost grows quadratically. It looks fine on 1,000 rows and is unusable at SCALE = 1.
