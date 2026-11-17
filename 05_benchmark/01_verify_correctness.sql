-- Runs every installed version and compares it with SLOW (MINUS both ways + row count),
-- PASS/FAIL per version, spooled to results/correctness_output.txt. Prompts whether to reuse SLOW.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET FEEDBACK OFF
SET LINESIZE 200

ACCEPT reuse_slow CHAR DEFAULT 'N' PROMPT 'Reuse existing SLOW output instead of re-running it? (Y/N) [N]: '

SPOOL results/correctness_output.txt

DECLARE
    TYPE t_codes IS TABLE OF VARCHAR2(10);
    c_codes    CONSTANT t_codes     := t_codes('V1', 'V2', 'V3', 'V4', 'V5', 'V6', 'V7', 'V7P');
    c_top_n    CONSTANT PLS_INTEGER := 100;

    v_month    DATE := perf_bench.dataset_month;
    v_code     VARCHAR2(10);
    v_ref_rows NUMBER;
    v_rows     NUMBER;
    v_only_ref NUMBER;
    v_only_new NUMBER;
    v_ran_ok   BOOLEAN;
    v_pass     PLS_INTEGER := 0;
    v_fail     PLS_INTEGER := 0;
    v_skip     PLS_INTEGER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Correctness check for report month ' || TO_CHAR(v_month, 'YYYY-MM')
                         || ', top ' || c_top_n);

    SELECT COUNT(*)
      INTO v_ref_rows
      FROM report_top_customers
     WHERE generated_by = 'SLOW'
       AND report_month = v_month;

    IF UPPER('&reuse_slow') <> 'Y' OR v_ref_rows = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Running the reference version SLOW (this can take a long time)...');
        perf_bench.run_report('SLOW', v_month, c_top_n);
        SELECT COUNT(*)
          INTO v_ref_rows
          FROM report_top_customers
         WHERE generated_by = 'SLOW'
           AND report_month = v_month;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Reusing existing SLOW output (' || v_ref_rows || ' rows).');
    END IF;

    -- An empty reference would make every MINUS trivially empty.
    IF v_ref_rows = 0 THEN
        RAISE_APPLICATION_ERROR(-20200, 'Reference (SLOW) output is empty - check the dataset and the report month.');
    END IF;

    FOR i IN 1 .. c_codes.COUNT LOOP
        v_code := c_codes(i);

        IF NOT perf_bench.is_installed(v_code) THEN
            DBMS_OUTPUT.PUT_LINE(RPAD(v_code, 5) || ' SKIPPED (procedure not installed)');
            v_skip := v_skip + 1;
        ELSE
            v_ran_ok := TRUE;
            BEGIN
                perf_bench.run_report(v_code, v_month, c_top_n);
            EXCEPTION
                WHEN OTHERS THEN
                    v_ran_ok := FALSE;
                    DBMS_OUTPUT.PUT_LINE(RPAD(v_code, 5) || ' FAIL (error while running: ' || SQLERRM || ')');
                    v_fail := v_fail + 1;
            END;

            IF v_ran_ok THEN
                -- GENERATED_BY and CREATED_AT differ by design and are left out.
                -- MINUS treats NULLs as equal, so a missing last payment compares fine.
                SELECT COUNT(*)
                  INTO v_only_ref
                  FROM (SELECT report_month, rank_no, customer_id, customer_name, email,
                               country_code, orders_count, orders_total, last_payment_date
                          FROM report_top_customers
                         WHERE generated_by = 'SLOW'
                           AND report_month = v_month
                        MINUS
                        SELECT report_month, rank_no, customer_id, customer_name, email,
                               country_code, orders_count, orders_total, last_payment_date
                          FROM report_top_customers
                         WHERE generated_by = v_code
                           AND report_month = v_month);

                SELECT COUNT(*)
                  INTO v_only_new
                  FROM (SELECT report_month, rank_no, customer_id, customer_name, email,
                               country_code, orders_count, orders_total, last_payment_date
                          FROM report_top_customers
                         WHERE generated_by = v_code
                           AND report_month = v_month
                        MINUS
                        SELECT report_month, rank_no, customer_id, customer_name, email,
                               country_code, orders_count, orders_total, last_payment_date
                          FROM report_top_customers
                         WHERE generated_by = 'SLOW'
                           AND report_month = v_month);

                SELECT COUNT(*)
                  INTO v_rows
                  FROM report_top_customers
                 WHERE generated_by = v_code
                   AND report_month = v_month;

                IF v_only_ref = 0 AND v_only_new = 0 AND v_rows = v_ref_rows THEN
                    DBMS_OUTPUT.PUT_LINE(RPAD(v_code, 5) || ' PASS (' || v_rows || ' rows identical to SLOW)');
                    v_pass := v_pass + 1;
                ELSE
                    DBMS_OUTPUT.PUT_LINE(RPAD(v_code, 5) || ' FAIL (only in SLOW: ' || v_only_ref
                                         || ', only in ' || v_code || ': ' || v_only_new
                                         || ', rows ' || v_rows || ' vs ' || v_ref_rows || ')');
                    v_fail := v_fail + 1;
                END IF;
            END IF;
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('----------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('PASS: ' || v_pass || '   FAIL: ' || v_fail || '   SKIPPED: ' || v_skip);
    IF v_fail > 0 THEN
        DBMS_OUTPUT.PUT_LINE('RESULT: FAIL - do not publish timings for the failing versions.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('RESULT: PASS');
    END IF;
END;
/

SPOOL OFF
SET FEEDBACK ON
