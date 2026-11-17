-- Step 3: V3 = V2 with only the date predicates rewritten as a half-open range.
-- No function-based index on TRUNC(order_date): it would serve only that one expression.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100

CREATE OR REPLACE PROCEDURE report_top_customers_v3 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'V3';

    -- TRUNC goes on the parameter once, never on the column.
    v_month_start  DATE;
    v_month_end    DATE;

    v_orders_count NUMBER;
    v_orders_total NUMBER;
    v_last_payment DATE;
    v_rank         PLS_INTEGER := 0;
    r_cust         customers%ROWTYPE;
BEGIN
    IF p_report_month IS NULL OR p_top_n IS NULL OR p_top_n < 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'p_report_month must not be NULL and p_top_n must be >= 1');
    END IF;
    v_month_start := TRUNC(p_report_month, 'MM');
    v_month_end   := ADD_MONTHS(v_month_start, 1);

    DELETE FROM report_top_customers
     WHERE generated_by = c_generated_by
       AND report_month = v_month_start;
    DELETE FROM report_top_customers_stage
     WHERE generated_by = c_generated_by;
    COMMIT;

    -- #2 fixed: the driver can start from a range scan on ORDERS_DATE_STATUS_IX.
    -- Still #1, #3, #5, #6.
    FOR r_c IN (
        SELECT *
          FROM customers c
         WHERE EXISTS (SELECT 1
                         FROM orders o
                        WHERE o.customer_id = c.customer_id
                          AND o.order_date >= v_month_start
                          AND o.order_date <  v_month_end)
         ORDER BY c.customer_id
    )
    LOOP
        -- customer_id and the date range are both access predicates on ORDERS_CUST_DATE_IX now.
        SELECT COUNT(*),
               NVL(SUM(x.order_total), 0)
          INTO v_orders_count, v_orders_total
          FROM (SELECT o.order_id,
                       (SELECT SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2))
                          FROM order_items oi
                         WHERE oi.order_id = o.order_id) AS order_total
                  FROM orders o
                 WHERE o.customer_id = r_c.customer_id
                   AND o.order_date >= v_month_start
                   AND o.order_date <  v_month_end
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
        VALUES (c_generated_by, v_month_start, v_rank, r_cust.customer_id,
                r_cust.first_name || ' ' || r_cust.last_name,
                r_cust.email, r_cust.country_code, r_s.orders_count,
                r_s.orders_total, r_s.last_payment_date);
        COMMIT;
    END LOOP;
END report_top_customers_v3;
/
SHOW ERRORS PROCEDURE report_top_customers_v3

-- order_date should now show up under access predicates, not filter.
VARIABLE month_start VARCHAR2(10)
VARIABLE customer_id NUMBER

DELETE FROM plan_table WHERE statement_id LIKE 'S3%';
COMMIT;

EXPLAIN PLAN SET STATEMENT_ID = 'S3_DRIVER' FOR
SELECT *
  FROM customers c
 WHERE EXISTS (SELECT 1
                 FROM orders o
                WHERE o.customer_id = c.customer_id
                  AND o.order_date >= TO_DATE(:month_start, 'YYYY-MM-DD')
                  AND o.order_date <  ADD_MONTHS(TO_DATE(:month_start, 'YYYY-MM-DD'), 1))
 ORDER BY c.customer_id;

EXPLAIN PLAN SET STATEMENT_ID = 'S3_PER_CUSTOMER' FOR
SELECT COUNT(*), NVL(SUM(x.order_total), 0)
  FROM (SELECT o.order_id,
               (SELECT SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2))
                  FROM order_items oi
                 WHERE oi.order_id = o.order_id) AS order_total
          FROM orders o
         WHERE o.customer_id = :customer_id
           AND o.order_date >= TO_DATE(:month_start, 'YYYY-MM-DD')
           AND o.order_date <  ADD_MONTHS(TO_DATE(:month_start, 'YYYY-MM-DD'), 1)
           AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')) x;

SET PAGESIZE 0
SET TRIMSPOOL ON
SET TRIMOUT ON
SPOOL results/plans/step3_explain_plan.txt
PROMPT ===== S3_DRIVER (date range) =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S3_DRIVER', 'TYPICAL'));
PROMPT ===== S3_PER_CUSTOMER (date range) =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S3_PER_CUSTOMER', 'TYPICAL'));
SPOOL OFF
SET PAGESIZE 100
