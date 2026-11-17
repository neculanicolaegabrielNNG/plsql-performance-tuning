-- Step 4: V4 replaces the loops with one INSERT ... SELECT (joins, GROUP BY, ROW_NUMBER).
-- No stage table, one COMMIT (kept for parity; in real code the caller owns the transaction).
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100

CREATE OR REPLACE PROCEDURE report_top_customers_v4 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'V4';
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

    INSERT INTO report_top_customers
           (generated_by, report_month, rank_no, customer_id, customer_name,
            email, country_code, orders_count, orders_total, last_payment_date)
    WITH month_sales AS (
        -- COUNT(DISTINCT): the join to ORDER_ITEMS returns one row per order line.
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
        -- Only the top N customers get here: a few index lookups instead of
        -- one subquery per customer of the month.
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
END report_top_customers_v4;
/
SHOW ERRORS PROCEDURE report_top_customers_v4

-- Plan of the SELECT part only.
VARIABLE month_start VARCHAR2(10)
VARIABLE top_n       NUMBER

DELETE FROM plan_table WHERE statement_id LIKE 'S4%';
COMMIT;

EXPLAIN PLAN SET STATEMENT_ID = 'S4_SET_BASED' FOR
WITH month_sales AS (
    SELECT o.customer_id,
           COUNT(DISTINCT o.order_id) AS orders_count,
           SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS orders_total
      FROM orders o
      JOIN order_items oi
        ON oi.order_id = o.order_id
     WHERE o.order_date >= TO_DATE(:month_start, 'YYYY-MM-DD')
       AND o.order_date <  ADD_MONTHS(TO_DATE(:month_start, 'YYYY-MM-DD'), 1)
       AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
     GROUP BY o.customer_id
),
ranked AS (
    SELECT ms.customer_id, ms.orders_count, ms.orders_total,
           ROW_NUMBER() OVER (ORDER BY ms.orders_total DESC, ms.customer_id) AS rank_no
      FROM month_sales ms
),
top_customers AS (
    SELECT r.customer_id, r.orders_count, r.orders_total, r.rank_no
      FROM ranked r
     WHERE r.rank_no <= :top_n
),
last_payment AS (
    SELECT o.customer_id, MAX(p.payment_date) AS last_payment_date
      FROM top_customers t
      JOIN orders o
        ON o.customer_id = t.customer_id
      JOIN payments p
        ON p.order_id = o.order_id
     WHERE p.status = 'COMPLETED'
     GROUP BY o.customer_id
)
SELECT t.rank_no, c.customer_id, c.first_name || ' ' || c.last_name AS customer_name,
       c.email, c.country_code, t.orders_count, t.orders_total, lp.last_payment_date
  FROM top_customers t
  JOIN customers c
    ON c.customer_id = t.customer_id
  LEFT JOIN last_payment lp
    ON lp.customer_id = t.customer_id;

SET PAGESIZE 0
SET TRIMSPOOL ON
SET TRIMOUT ON
SPOOL results/plans/step4_explain_plan.txt
PROMPT ===== S4_SET_BASED =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S4_SET_BASED', 'TYPICAL'));
SPOOL OFF
SET PAGESIZE 100

-- Running revenue share of the top 20, to check the skew. SUM() OVER fits here; for the
-- per-customer totals GROUP BY is right, an analytic SUM would keep one row per line.
PROMPT Revenue concentration in the report month (top 20 customers):
COLUMN cumulative_pct FORMAT 990.00
SELECT rank_no, customer_id, orders_total, running_total, cumulative_pct
  FROM (SELECT ms.customer_id,
               ms.orders_total,
               ROW_NUMBER() OVER (ORDER BY ms.orders_total DESC, ms.customer_id) AS rank_no,
               SUM(ms.orders_total) OVER (ORDER BY ms.orders_total DESC, ms.customer_id
                                          ROWS UNBOUNDED PRECEDING) AS running_total,
               ROUND(100 * SUM(ms.orders_total) OVER (ORDER BY ms.orders_total DESC, ms.customer_id
                                                      ROWS UNBOUNDED PRECEDING)
                         / SUM(ms.orders_total) OVER (), 2) AS cumulative_pct
          FROM (SELECT o.customer_id,
                       SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS orders_total
                  FROM dataset_info d
                  JOIN orders o
                    ON o.order_date >= d.report_month
                   AND o.order_date <  ADD_MONTHS(d.report_month, 1)
                  JOIN order_items oi
                    ON oi.order_id = o.order_id
                 WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
                 GROUP BY o.customer_id) ms)
 WHERE rank_no <= 20
 ORDER BY rank_no;
