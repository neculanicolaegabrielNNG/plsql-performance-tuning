# Step 7 (optional): Materialized view or partitioning

Both options change the architecture, not just the code.

**7a, materialized view** (`07a_optional_materialized_view.sql`, `REPORT_TOP_CUSTOMERS_V7`)
- `MV_CUSTOMER_MONTH_SALES` holds orders_count and orders_total per customer and month, computed at refresh time.
- V7 reads the MV by name, so query rewrite (EE) isn't needed. MVs themselves exist in every edition.
- `REFRESH COMPLETE ON DEMAND`, because `COUNT(DISTINCT)` rules out fast refresh.
- V7 refuses to run on a stale MV, and the correctness check fails it if base data changed after the refresh. That is intended.
- Worth it when the report runs often, the data changes rarely and some staleness is acceptable.

**7b, partitioning** (`07b_optional_partitioning.sql`, `REPORT_TOP_CUSTOMERS_V7P`). Partitioning is a separately licensed option on on-prem EE, so check your edition first.
- `ORDERS_PART` is a monthly interval-partitioned copy of ORDERS. The original table stays untouched, and rollback is a drop.
- The sargable month filter on the partition key reads one partition (`PARTITION RANGE SINGLE`), which replaces the covering date index.
- `ORDERS_PART_CUST_DATE_IX` is global: the last-payment lookup spans all months, and a local index would be probed per partition.
