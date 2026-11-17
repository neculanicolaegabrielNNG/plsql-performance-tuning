-- Step 6: back up the current stats, gather stats with DBMS_STATS, create V6
-- (V4's query, no hints). V4 vs V6 isolates the effect of statistics.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100
SET TIMING ON

-- Backup so the rollback restores exactly the pre-step-6 state.
DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'STATS_BACKUP';
    IF v_exists = 0 THEN
        DBMS_STATS.CREATE_STAT_TABLE(ownname => USER, stattab => 'STATS_BACKUP');
    END IF;

    -- Dynamic SQL: STATS_BACKUP may not exist yet when this block compiles.
    EXECUTE IMMEDIATE 'DELETE FROM stats_backup WHERE statid = :1' USING 'BEFORE_STEP6';
    FOR t IN (SELECT table_name
                FROM user_tables
               WHERE table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS'))
    LOOP
        DBMS_STATS.EXPORT_TABLE_STATS(ownname => USER,
                                      tabname => t.table_name,
                                      stattab => 'STATS_BACKUP',
                                      statid  => 'BEFORE_STEP6',
                                      cascade => TRUE);
    END LOOP;
    COMMIT;
END;
/

-- SIZE AUTO: histograms only on skewed columns used in predicates (earlier runs recorded that).
-- no_invalidate => FALSE: the default spreads re-parsing over hours, benchmarks could keep old plans.
BEGIN
    FOR t IN (SELECT table_name
                FROM user_tables
               WHERE table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS'))
    LOOP
        DBMS_STATS.GATHER_TABLE_STATS(ownname          => USER,
                                      tabname          => t.table_name,
                                      estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                      method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
                                      cascade          => TRUE,
                                      no_invalidate    => FALSE);
    END LOOP;
END;
/

SET TIMING OFF

COLUMN table_name    FORMAT A14
COLUMN column_name   FORMAT A16
COLUMN histogram     FORMAT A16
COLUMN last_analyzed FORMAT A19
PROMPT Table statistics:
SELECT table_name, num_rows, blocks, TO_CHAR(last_analyzed, 'YYYY-MM-DD HH24:MI:SS') AS last_analyzed
  FROM user_tab_statistics
 WHERE table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS')
   AND object_type = 'TABLE'
 ORDER BY table_name;

PROMPT Column statistics used by the report (histograms appear where data is skewed):
SELECT table_name, column_name, num_distinct, num_nulls, histogram
  FROM user_tab_col_statistics
 WHERE (table_name = 'ORDERS'   AND column_name IN ('CUSTOMER_ID', 'ORDER_DATE', 'STATUS'))
    OR (table_name = 'PAYMENTS' AND column_name IN ('ORDER_ID', 'STATUS'))
 ORDER BY table_name, column_name;

CREATE OR REPLACE PROCEDURE report_top_customers_v6 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'V6';
    v_month_start  DATE;
    v_month_end    DATE;
BEGIN
    IF p_report_month IS NULL OR p_top_n IS NULL OR p_top_n < 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'p_report_month must not be NULL and p_top_n must be >= 1');
    END IF;
    v_month_start := TRUNC(p_report_month, 'MM');
    v_month_end   := ADD_MONTHS(v_month_start, 1);

    DELETE FROM report_top_customers
     WHERE generated_by = c_generated_by
       AND report_month = v_month_start;

    -- No hint unless DISPLAY_CURSOR still shows E-Rows far from A-Rows after stats, e.g.
    --   SELECT /*+ LEADING(o oi) USE_HASH(oi) INDEX(o orders_date_status_ix) */ ...
    -- and only with the evidence written down in results/execution_plans.md.
    INSERT INTO report_top_customers
           (generated_by, report_month, rank_no, customer_id, customer_name,
            email, country_code, orders_count, orders_total, last_payment_date)
    WITH month_sales AS (
        SELECT o.customer_id,
               COUNT(DISTINCT o.order_id) AS orders_count,
               SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS orders_total
          FROM orders o
          JOIN order_items oi
            ON oi.order_id = o.order_id
         WHERE o.order_date >= v_month_start
           AND o.order_date <  v_month_end
           AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
         GROUP BY o.customer_id
    ),
    ranked AS (
        SELECT ms.customer_id,
               ms.orders_count,
               ms.orders_total,
               ROW_NUMBER() OVER (ORDER BY ms.orders_total DESC, ms.customer_id) AS rank_no
          FROM month_sales ms
    ),
    top_customers AS (
        SELECT r.customer_id, r.orders_count, r.orders_total, r.rank_no
          FROM ranked r
         WHERE r.rank_no <= p_top_n
    ),
    last_payment AS (
        SELECT o.customer_id,
               MAX(p.payment_date) AS last_payment_date
          FROM top_customers t
          JOIN orders o
            ON o.customer_id = t.customer_id
          JOIN payments p
            ON p.order_id = o.order_id
         WHERE p.status = 'COMPLETED'
         GROUP BY o.customer_id
    )
    SELECT c_generated_by,
           v_month_start,
           t.rank_no,
           c.customer_id,
           c.first_name || ' ' || c.last_name,
           c.email,
           c.country_code,
           t.orders_count,
           t.orders_total,
           lp.last_payment_date
      FROM top_customers t
      JOIN customers c
        ON c.customer_id = t.customer_id
      LEFT JOIN last_payment lp
        ON lp.customer_id = t.customer_id;

    COMMIT;
END report_top_customers_v6;
/
SHOW ERRORS PROCEDURE report_top_customers_v6

PROMPT Next: benchmark V6 (and optionally V4 again) and capture its plan with
PROMPT @05_benchmark/03_capture_plan.sql V6 - compare E-Rows with A-Rows.
