-- Deliberately slow but correct top-customers report; its output is the reference for
-- the correctness check. Mistakes are marked "slow #n" (list in docs/00_slow_version.md).
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON

CREATE OR REPLACE PROCEDURE report_top_customers_slow (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'SLOW';

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

    -- slow #3: SELECT *, only customer_id is used
    -- slow #2: TO_CHAR on order_date, no range scan possible
    -- slow #1: no status filter, also loops over customers with only cancelled orders
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
        -- slow #1: N+1, this query runs once per customer
        -- slow #4: no index on ORDERS.CUSTOMER_ID, so every run is a full scan
        -- slow #2: TRUNC on order_date
        -- slow #5: correlated scalar subquery per order
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
            -- slow #5: correlated EXISTS, once per customer
            -- slow #4: PAYMENTS.ORDER_ID not indexed, full scan per customer
            SELECT MAX(p.payment_date)
              INTO v_last_payment
              FROM payments p
             WHERE p.status = 'COMPLETED'
               AND EXISTS (SELECT 1
                             FROM orders o
                            WHERE o.order_id = p.order_id
                              AND o.customer_id = r_c.customer_id);

            -- slow #6: single-row insert + COMMIT per row
            INSERT INTO report_top_customers_stage
                   (generated_by, customer_id, orders_count, orders_total, last_payment_date)
            VALUES (c_generated_by, r_c.customer_id, v_orders_count, v_orders_total, v_last_payment);
            COMMIT;
        END IF;
    END LOOP;

    -- slow #3 #1: SELECT * from the stage table, then a SELECT * lookup per row
    -- slow #6: COMMIT per report row
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
END report_top_customers_slow;
/
SHOW ERRORS PROCEDURE report_top_customers_slow
