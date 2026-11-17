-- Step 7b (optional; Partitioning is licensed separately on on-prem EE): V7P = V4 on ORDERS_PART,
-- a monthly interval-partitioned copy. ORDERS stays untouched so all versions remain comparable.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET TIMING ON

-- Only the first, empty partition is declared; interval partitioning adds one per month with data.
CREATE TABLE orders_part
    PARTITION BY RANGE (order_date)
    INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
    (PARTITION p_before_2000 VALUES LESS THAN (DATE '2000-01-01'))
AS
SELECT order_id, customer_id, order_date, status, channel, shipping_amount, notes
  FROM orders;

ALTER TABLE orders_part ADD CONSTRAINT orders_part_pk PRIMARY KEY (order_id);

-- Global on purpose: the last-payment lookup spans all months, a local index would be
-- probed once per partition. No date index: partition pruning does that job.
CREATE INDEX orders_part_cust_date_ix ON orders_part (customer_id, order_date);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(ownname => USER, tabname => 'ORDERS_PART',
                                  method_opt => 'FOR ALL COLUMNS SIZE AUTO',
                                  cascade => TRUE, no_invalidate => FALSE);
END;
/

SET TIMING OFF

CREATE OR REPLACE PROCEDURE report_top_customers_v7p (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'V7P';
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
        -- Range on the partition key, so only one partition is read.
        SELECT o.customer_id,
               COUNT(DISTINCT o.order_id) AS orders_count,
               SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS orders_total
          FROM orders_part o
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
          JOIN orders_part o
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
END report_top_customers_v7p;
/
SHOW ERRORS PROCEDURE report_top_customers_v7p

PROMPT Partitions created (expect one per month of data, plus P_BEFORE_2000):
SELECT COUNT(*) AS partitions
  FROM user_tab_partitions
 WHERE table_name = 'ORDERS_PART';
