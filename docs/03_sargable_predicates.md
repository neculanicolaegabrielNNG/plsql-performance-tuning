# Step 3: Sargable predicates

`04_optimization_steps/03_sargable_predicates.sql`, rollback `03_sargable_predicates_rollback.sql`, procedure `REPORT_TOP_CUSTOMERS_V3`.

```sql
-- before
TRUNC(o.order_date, 'MM') = v_month            -- and TO_CHAR(o.order_date, 'YYYY-MM') = ...
-- after: the function goes on the parameter, the column stays bare
o.order_date >= v_month_start AND o.order_date < v_month_end   -- v_month_end = ADD_MONTHS(v_month_start, 1)
```

Oracle can range-scan an index only when the predicate compares the bare column. With a function around it, the value has to be computed for every row or index entry first. The half-open range is also correct for DATEs with a time part, with no `23:59:59` edge cases.

I rejected a function-based index on `TRUNC(order_date, 'MM')`: it would serve only that exact expression and add one more index to maintain. In the plan, `ORDER_DATE` should move from filter to access predicates on `ORDERS_DATE_STATUS_IX` (driver) and `ORDERS_CUST_DATE_IX` (per-customer query). Only the predicates change, so the V2 → V3 difference comes from them alone.
