# Step 4: Set-based rewrite

`04_optimization_steps/04_set_based_rewrite.sql`, rollback `04_set_based_rewrite_rollback.sql`, procedure `REPORT_TOP_CUSTOMERS_V4`.

After steps 2 and 3 each statement is cheap, but there are still thousands of them. A single `INSERT ... SELECT` lets the optimizer read each table once, choose hash join or nested loops by volume, aggregate in one pass and rank with one sort, all in one context switch.

```
month_sales    one month of ORDERS (covering index) join ORDER_ITEMS (PK), GROUP BY customer
ranked         ROW_NUMBER() OVER (ORDER BY orders_total DESC, customer_id)
top_customers  rank_no <= p_top_n
last_payment   top N only: ORDERS_CUST_DATE_IX -> PAYMENTS_ORDER_IX
```

This removes N+1, `SELECT *`, the correlated subqueries, the per-row COMMIT and the stage table. The main choice is to compute the all-time last payment only for the N surviving rows. `ROW_NUMBER()` and not `RANK()`, because ties would break the "top N rows" contract. `COUNT(DISTINCT order_id)`, because the join repeats each order once per line. `SUM() OVER` appears only in the revenue-share query at the end; for per-customer totals `GROUP BY` is the right tool.
