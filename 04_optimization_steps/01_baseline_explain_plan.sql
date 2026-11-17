-- Step 1: V1 = SLOW plus instrumentation (module/action, counters, phase timings), and
-- EXPLAIN PLAN of the loop statements into results/plans/step1_explain_plan.txt.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100

CREATE OR REPLACE PROCEDURE report_top_customers_v1 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    -- Same SQL as SLOW, only measuring code added.
    c_generated_by CONSTANT VARCHAR2(10) := 'V1';

    v_month        DATE;
    v_orders_count NUMBER;
    v_orders_total NUMBER;
    v_last_payment DATE;
    v_rank         PLS_INTEGER := 0;
    r_cust         customers%ROWTYPE;

    v_t_start      PLS_INTEGER;
    v_t_phase1     PLS_INTEGER;
    v_customers    PLS_INTEGER := 0;
    v_candidates   PLS_INTEGER := 0;
    v_sql_execs    PLS_INTEGER := 0;
    v_commits      PLS_INTEGER := 0;
BEGIN
    IF p_report_month IS NULL OR p_top_n IS NULL OR p_top_n < 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'p_report_month must not be NULL and p_top_n must be >= 1');
    END IF;
    v_month := TRUNC(p_report_month, 'MM');

    -- MODULE/ACTION show up in V$SESSION, V$SQL and ASH, so a DBA can see the phase.
    DBMS_APPLICATION_INFO.SET_MODULE(module_name => 'REPORT_TOP_CUSTOMERS',
                                     action_name => c_generated_by || ':phase1');
    v_t_start := DBMS_UTILITY.GET_TIME;

    DELETE FROM report_top_customers
     WHERE generated_by = c_generated_by
       AND report_month = v_month;
    DELETE FROM report_top_customers_stage
     WHERE generated_by = c_generated_by;
    COMMIT;

    -- Same mistakes #1-#6 as SLOW.
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
        v_customers := v_customers + 1;

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
        v_sql_execs := v_sql_execs + 1;

        IF v_orders_count > 0 THEN
            v_candidates := v_candidates + 1;

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
            v_sql_execs := v_sql_execs + 2;
            v_commits   := v_commits + 1;
        END IF;
    END LOOP;

    v_t_phase1 := DBMS_UTILITY.GET_TIME;
    DBMS_APPLICATION_INFO.SET_ACTION(c_generated_by || ':phase2');

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
        v_sql_execs := v_sql_execs + 2;
        v_commits   := v_commits + 1;
    END LOOP;

    -- GET_TIME is in hundredths of a second.
    DBMS_OUTPUT.PUT_LINE('V1 instrumentation for ' || TO_CHAR(v_month, 'YYYY-MM'));
    DBMS_OUTPUT.PUT_LINE('  customers visited by the loop : ' || v_customers);
    DBMS_OUTPUT.PUT_LINE('  candidates (valid orders)     : ' || v_candidates);
    DBMS_OUTPUT.PUT_LINE('  SQL executions inside loops   : ' || v_sql_execs);
    DBMS_OUTPUT.PUT_LINE('  COMMITs                       : ' || v_commits);
    DBMS_OUTPUT.PUT_LINE('  phase 1 (customer loop) cs    : ' || (v_t_phase1 - v_t_start));
    DBMS_OUTPUT.PUT_LINE('  phase 2 (ranking) cs          : ' || (DBMS_UTILITY.GET_TIME - v_t_phase1));

    DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
        RAISE;
END report_top_customers_v1;
/
SHOW ERRORS PROCEDURE report_top_customers_v1

-- EXPLAIN PLAN doesn't execute or peek binds, so these are estimates; the real plans come
-- from 05_benchmark/03_capture_plan.sql. SQL*Plus still wants the binds declared.
VARIABLE month_key   VARCHAR2(7)
VARIABLE month_start VARCHAR2(10)
VARIABLE customer_id NUMBER

DELETE FROM plan_table WHERE statement_id LIKE 'S1%';
COMMIT;

EXPLAIN PLAN SET STATEMENT_ID = 'S1_DRIVER' FOR
SELECT *
  FROM customers c
 WHERE EXISTS (SELECT 1
                 FROM orders o
                WHERE o.customer_id = c.customer_id
                  AND TO_CHAR(o.order_date, 'YYYY-MM') = :month_key)
 ORDER BY c.customer_id;

EXPLAIN PLAN SET STATEMENT_ID = 'S1_PER_CUSTOMER' FOR
SELECT COUNT(*), NVL(SUM(x.order_total), 0)
  FROM (SELECT o.order_id,
               (SELECT SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2))
                  FROM order_items oi
                 WHERE oi.order_id = o.order_id) AS order_total
          FROM orders o
         WHERE o.customer_id = :customer_id
           AND TRUNC(o.order_date, 'MM') = TO_DATE(:month_start, 'YYYY-MM-DD')
           AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')) x;

EXPLAIN PLAN SET STATEMENT_ID = 'S1_LAST_PAYMENT' FOR
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
SPOOL results/plans/step1_explain_plan.txt
PROMPT ===== S1_DRIVER: customers with any order in the month (TO_CHAR on ORDER_DATE) =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S1_DRIVER', 'TYPICAL'));
PROMPT ===== S1_PER_CUSTOMER: executed once per customer (N+1) =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S1_PER_CUSTOMER', 'TYPICAL'));
PROMPT ===== S1_LAST_PAYMENT: executed once per candidate customer (N+1) =====
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'S1_LAST_PAYMENT', 'TYPICAL'));
SPOOL OFF
SET PAGESIZE 100

PROMPT
PROMPT What to look for (write your findings in results/execution_plans.md):
PROMPT  - TABLE ACCESS FULL on ORDERS / PAYMENTS inside statements that run once per customer.
PROMPT  - The filter on TO_CHAR / TRUNC of ORDER_DATE: no access predicate on the date.
PROMPT  - "dynamic sampling used for this statement" in the notes: no statistics yet.
PROMPT Run V1 once (SET SERVEROUTPUT ON) to see how many times each statement executes.
