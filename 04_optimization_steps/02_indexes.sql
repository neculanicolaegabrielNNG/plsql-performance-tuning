-- Step 2: indexes on the join keys plus a covering index for the month filter.
-- V2 = SLOW logic unchanged, so V1 -> V2 measures the indexes alone.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100
SET TIMING ON

-- customer_id first for the per-customer and last-payment lookups (also the FK index);
-- order_date second so that after step 3 one range scan gets a customer's month.
CREATE INDEX orders_cust_date_ix ON orders (customer_id, order_date);

-- Covering index for the set-based versions: range column first, status filtered inside
-- the index, plus the only other ORDERS columns the report needs, so no table access.
-- Bigger and slows inserts a bit; fine for reporting, reconsider for OLTP.
CREATE INDEX orders_date_status_ix ON orders (order_date, status, customer_id, order_id);

CREATE INDEX payments_order_ix ON payments (order_id);

-- Not created: ORDER_ITEMS(order_id) is already the PK prefix; ORDER_ITEMS(product_id)
-- is an FK, but nothing here filters on it and every index slows DML.

SET TIMING OFF

CREATE OR REPLACE PROCEDURE report_top_customers_v2 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    -- Same SQL as SLOW; only the schema changed.
    c_generated_by CONSTANT VARCHAR2(10) := 'V2';

    v_month        DATE;
    v_orders_count NUMBER;
    v_orders_total NUMBER;
    v_last_payment DATE;
    v_rank         PLS_INTEGER := 0;
    r_cust         customers%ROWTYPE;
BEGIN
    IF p_report_month IS NULL OR p_top_n IS NULL OR p_top_n < 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'p_report_month must not be NULL and p_top_n must be >= 1');
    END IF;
    v_month := TRUNC(p_report_month, 'MM');

    DELETE FROM report_top_customers
     WHERE generated_by = c_generated_by
       AND report_month = v_month;
    DELETE FROM report_top_customers_stage
     WHERE generated_by = c_generated_by;
    COMMIT;

    -- Still #1, #2, #3, #5, #6; #4 is fixed by the indexes.
    FOR r_c IN (
        SELECT *
          FROM customers c
         WHERE EXISTS (SELECT 1
                         FROM orders o
                        WHERE o.customer_id = c.customer_id
                          AND TO_CHAR(o.order_date, 'YYYY-MM') = TO_CHAR(v_month, 'YYYY-MM'))
         ORDER BY c.customer_id
    )
    LOOP
        -- Range scan on ORDERS_CUST_DATE_IX now, but TRUNC still filters every entry of the customer.
        SELECT COUNT(*),
               NVL(SUM(x.order_total), 0)
          INTO v_orders_count, v_orders_total
          FROM (SELECT o.order_id,
                       (SELECT SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2))
                          FROM order_items oi
                         WHERE oi.order_id = o.order_id) AS order_total
                  FROM orders o
                 WHERE o.customer_id = r_c.customer_id
                   AND TRUNC(o.order_date, 'MM') = v_month
                   AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')) x;

        IF v_orders_count > 0 THEN
            SELECT MAX(p.payment_date)
              INTO v_last_payment
              FROM payments p
             WHERE p.status = 'COMPLETED'
               AND EXISTS (SELECT 1
                             FROM orders o
                            WHERE o.order_id = p.order_id
                              AND o.customer_id = r_c.customer_id);

            INSERT INTO report_top_customers_stage
                   (generated_by, customer_id, orders_count, orders_total, last_payment_date)
            VALUES (c_generated_by, r_c.customer_id, v_orders_count, v_orders_total, v_last_payment);
            COMMIT;
        END IF;
    END LOOP;

    FOR r_s IN (
        SELECT *
          FROM report_top_customers_stage
         WHERE generated_by = c_generated_by
         ORDER BY orders_total DESC, customer_id
    )
    LOOP
        v_rank := v_rank + 1;
        EXIT WHEN v_rank > p_top_n;

        SELECT *
          INTO r_cust
          FROM customers
         WHERE customer_id = r_s.customer_id;

        INSERT INTO report_top_customers
               (generated_by, report_month, rank_no, customer_id, customer_name,
                email, country_code, orders_count, orders_total, last_payment_date)
        VALUES (c_generated_by, v_month, v_rank, r_cust.customer_id,
                r_cust.first_name || ' ' || r_cust.last_name,
                r_cust.email, r_cust.country_code, r_s.orders_count,
                r_s.orders_total, r_s.last_payment_date);
        COMMIT;
    END LOOP;
END report_top_customers_v2;
/
SHOW ERRORS PROCEDURE report_top_customers_v2

-- Inner statements should now use the indexes; the driver still full-scans ORDERS (TO_CHAR).
VARIABLE month_key   VARCHAR2(7)
VARIABLE month_start VARCHAR2(10)
VARIABLE customer_id NUMBER

DELETE FROM plan_table WHERE statement_id LIKE 'S2%';
COMMIT;

EXPLAIN PLAN SET STATEMENT_ID = 'S2_DRIVER' FOR
SELECT *
  FROM customers c
 WHERE EXISTS (SELECT 1
                 FROM orders o
                WHERE o.customer_id = c.customer_id
                  AND TO_CHAR(o.order_date, 'YYYY-MM') = :month_key)
 ORDER BY c.customer_id;

EXPLAIN PLAN SET STATEMENT_ID = 'S2_PER_CUSTOMER' FOR
SELECT COUNT(*), NVL(SUM(x.order_total), 0)
  FROM (SELECT o.order_id,
               (SELECT SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2))
                  FROM order_items oi
                 WHERE oi.order_id = o.order_id) AS order_total
          FROM orders o
         WHERE o.customer_id = :customer_id
           AND TRUNC(o.order_date, 'MM') = TO_DATE(:month_start, 'YYYY-MM-DD')
           AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')) x;

EXPLAIN PLAN SET STATEMENT_ID = 'S2_LAST_PAYMENT' FOR
SELECT MAX(p.payment_date)
  FROM payments p
 WHERE p.status = 'COMPLETED'
   AND EXISTS (SELECT 1
                 FROM orders o
                WHERE o.order_id = p.order_id
                  AND o.customer_id = :customer_id);

SET PAGESIZE 0
SET TRIMSPOOL ON
SET TRIMOUT ON
SPOOL results/plans/step2_explain_plan.txt
PROMPT ===== S2_DRIVER (still TO_CHAR on ORDER_DATE) =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S2_DRIVER', 'TYPICAL'));
PROMPT ===== S2_PER_CUSTOMER =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S2_PER_CUSTOMER', 'TYPICAL'));
PROMPT ===== S2_LAST_PAYMENT =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S2_LAST_PAYMENT', 'TYPICAL'));
SPOOL OFF
SET PAGESIZE 100

COLUMN index_name  FORMAT A24
COLUMN column_name FORMAT A16
SELECT index_name, column_position, column_name
  FROM user_ind_columns
 WHERE index_name IN ('ORDERS_CUST_DATE_IX', 'ORDERS_DATE_STATUS_IX', 'PAYMENTS_ORDER_IX')
 ORDER BY index_name, column_position;
