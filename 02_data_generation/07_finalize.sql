-- Re-enables the FKs, deletes optimizer stats, prints row counts and skew checks.

-- ENABLE VALIDATE checks all rows once, set-based, instead of row by row during the load.
BEGIN
    FOR c IN (SELECT table_name, constraint_name
                FROM user_constraints
               WHERE constraint_type = 'R'
                 AND status = 'DISABLED'
                 AND table_name IN ('ORDERS', 'ORDER_ITEMS', 'PAYMENTS'))
    LOOP
        EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name
                          || ' ENABLE VALIDATE CONSTRAINT ' || c.constraint_name;
    END LOOP;
END;
/

-- Online stats gathering (12c+) left basic stats from the direct-path load. Deleted on
-- purpose: the baseline runs without stats, step 6 gathers them and its rollback returns here.
BEGIN
    FOR t IN (SELECT table_name
                FROM user_tables
               WHERE table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS'))
    LOOP
        DBMS_STATS.DELETE_TABLE_STATS(ownname => USER, tabname => t.table_name);
    END LOOP;
END;
/

PROMPT
PROMPT Row count per table:
COLUMN table_name FORMAT A14
COLUMN row_count  FORMAT 999,999,999,990
SELECT 'CUSTOMERS' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'PRODUCTS', COUNT(*) FROM products
UNION ALL
SELECT 'ORDERS', COUNT(*) FROM orders
UNION ALL
SELECT 'ORDER_ITEMS', COUNT(*) FROM order_items
UNION ALL
SELECT 'PAYMENTS', COUNT(*) FROM payments;

PROMPT
PROMPT Skew check - customers with the most orders (whales):
SELECT customer_id, COUNT(*) AS orders_count
  FROM orders
 GROUP BY customer_id
 ORDER BY orders_count DESC, customer_id
 FETCH FIRST 5 ROWS ONLY;

PROMPT
PROMPT Order status distribution:
COLUMN status FORMAT A12
SELECT status, COUNT(*) AS orders_count,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
  FROM orders
 GROUP BY status
 ORDER BY orders_count DESC;

PROMPT
PROMPT Orders in the report month (stored in DATASET_INFO.REPORT_MONTH):
SELECT TO_CHAR(d.report_month, 'YYYY-MM') AS report_month,
       COUNT(o.order_id)                   AS orders_in_month,
       COUNT(DISTINCT o.customer_id)       AS customers_in_month
  FROM dataset_info d
  LEFT JOIN orders o
    ON o.order_date >= d.report_month
   AND o.order_date <  ADD_MONTHS(d.report_month, 1)
 GROUP BY d.report_month;

PROMPT Data generation finished.
