-- Runs SLOW once for the dataset month and shows the top 20. Work grows with
-- customers x (ORDERS + PAYMENTS rows): start around SCALE 0.01, SCALE 1 is impractical.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET TIMING ON

DECLARE
    v_month DATE;
    v_t0    TIMESTAMP WITH TIME ZONE;
    v_rows  NUMBER;
BEGIN
    SELECT report_month INTO v_month FROM dataset_info WHERE dataset_id = 1;
    DBMS_OUTPUT.PUT_LINE('Report month: ' || TO_CHAR(v_month, 'YYYY-MM'));

    v_t0 := SYSTIMESTAMP;
    report_top_customers_slow(p_report_month => v_month, p_top_n => 100);

    SELECT COUNT(*) INTO v_rows
      FROM report_top_customers
     WHERE generated_by = 'SLOW'
       AND report_month = v_month;

    DBMS_OUTPUT.PUT_LINE('Rows written: ' || v_rows);
    DBMS_OUTPUT.PUT_LINE('Elapsed     : ' || TO_CHAR(SYSTIMESTAMP - v_t0));
END;
/

SET TIMING OFF
COLUMN customer_name FORMAT A24
COLUMN last_payment  FORMAT A19
SELECT r.rank_no, r.customer_id, r.customer_name, r.orders_count, r.orders_total,
       TO_CHAR(r.last_payment_date, 'YYYY-MM-DD HH24:MI:SS') AS last_payment
  FROM report_top_customers r
  JOIN dataset_info d
    ON d.report_month = r.report_month
 WHERE r.generated_by = 'SLOW'
   AND r.rank_no <= 20
 ORDER BY r.rank_no;
