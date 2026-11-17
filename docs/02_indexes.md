# Step 2: Indexes

`04_optimization_steps/02_indexes.sql`, rollback `02_indexes_rollback.sql`, procedure `REPORT_TOP_CUSTOMERS_V2` (SLOW logic unchanged).

This is the cheapest fix because it needs no code change, and it targets the biggest cost in the baseline: full scans inside statements that run N times.

| Index | Columns | Why |
|---|---|---|
| `ORDERS_CUST_DATE_IX` | `(customer_id, order_date)` | join key and FK index; after step 3 one range scan returns one customer's month. Also used by the last-payment lookup. |
| `ORDERS_DATE_STATUS_IX` | `(order_date, status, customer_id, order_id)` | covering index for the month filter: range column first, status filtered in the index, no table access |
| `PAYMENTS_ORDER_IX` | `(order_id)` | join key, finds an order's payments without scanning PAYMENTS |

Not created: `ORDER_ITEMS(order_id)`, because the PK already leads with it, and `ORDER_ITEMS(product_id)`, which is an FK but no query here uses it. V2 is still N+1, and the driver still full-scans ORDERS because of `TO_CHAR(order_date)`. That gets fixed in step 3. The cost of these indexes is bigger storage and slower inserts, which is fine for reporting but needs measuring on write-heavy tables.
