-- Step 7a (optional): MV_CUSTOMER_MONTH_SALES pre-aggregates per customer and month. V7 reads
-- it by name, so no query rewrite (EE) is needed. COMPLETE refresh: COUNT(DISTINCT) rules out FAST.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET TIMING ON

-- TRUNC(order_date) is fine here: it runs at refresh time, the report filters on month_start.
CREATE MATERIALIZED VIEW mv_customer_month_sales
    BUILD IMMEDIATE
    REFRESH COMPLETE ON DEMAND
    DISABLE QUERY REWRITE
AS
SELECT o.customer_id,
       TRUNC(o.order_date, 'MM') AS month_start,
       COUNT(DISTINCT o.order_id) AS orders_count,
       SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS orders_total
  FROM orders o
  JOIN order_items oi
    ON oi.order_id = o.order_id
 WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
 GROUP BY o.customer_id, TRUNC(o.order_date, 'MM');

-- The report always filters one month: lead with MONTH_START.
CREATE INDEX mv_cms_month_ix ON mv_customer_month_sales (month_start, orders_total, customer_id);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(ownname => USER, tabname => 'MV_CUSTOMER_MONTH_SALES',
                                  cascade => TRUE, no_invalidate => FALSE);
END;
/

SET TIMING OFF

CREATE OR REPLACE PROCEDURE report_top_customers_v7 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'V7';
    v_month_start  DATE;
    v_staleness    user_mviews.staleness%TYPE;
BEGIN
    IF p_report_month IS NULL OR p_top_n IS NULL OR p_top_n < 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'p_report_month must not be NULL and p_top_n must be >= 1');
    END IF;
    v_month_start := TRUNC(p_report_month, 'MM');

    -- A fast wrong report is worse than a slow one: refuse a stale MV.
    SELECT staleness
      INTO v_staleness
      FROM user_mviews
     WHERE mview_name = 'MV_CUSTOMER_MONTH_SALES';
    IF v_staleness IN ('STALE', 'NEEDS_COMPILE', 'UNUSABLE') THEN
        RAISE_APPLICATION_ERROR(-20070, 'MV_CUSTOMER_MONTH_SALES is ' || v_staleness
                                        || ' - refresh it with DBMS_MVIEW.REFRESH first.');
    END IF;

    DELETE FROM report_top_customers
     WHERE generated_by = c_generated_by
       AND report_month = v_month_start;

    INSERT INTO report_top_customers
           (generated_by, report_month, rank_no, customer_id, customer_name,
            email, country_code, orders_count, orders_total, last_payment_date)
    WITH ranked AS (
        -- No join to ORDER_ITEMS any more.
        SELECT m.customer_id,
               m.orders_count,
               m.orders_total,
               ROW_NUMBER() OVER (ORDER BY m.orders_total DESC, m.customer_id) AS rank_no
          FROM mv_customer_month_sales m
         WHERE m.month_start = v_month_start
    ),
    top_customers AS (
        SELECT r.customer_id, r.orders_count, r.orders_total, r.rank_no
          FROM ranked r
         WHERE r.rank_no <= p_top_n
    ),
    last_payment AS (
        -- Last payment is all-time, so it still comes from the base tables (top N only).
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
END report_top_customers_v7;
/
SHOW ERRORS PROCEDURE report_top_customers_v7

PROMPT
PROMPT To refresh after the base data changes (complete, non-atomic = faster;
PROMPT the MV is empty while it is being rebuilt):
PROMPT   EXEC DBMS_MVIEW.REFRESH('MV_CUSTOMER_MONTH_SALES', method => 'C', atomic_refresh => FALSE)
SELECT mview_name, refresh_method, staleness,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS last_refresh
  FROM user_mviews
 WHERE mview_name = 'MV_CUSTOMER_MONTH_SALES';
