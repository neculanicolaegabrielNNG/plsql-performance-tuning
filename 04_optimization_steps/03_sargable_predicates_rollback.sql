-- Rollback step 3: drops V3 and its output rows (code-only step).
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE report_top_customers_v3';
    DBMS_OUTPUT.PUT_LINE('Dropped REPORT_TOP_CUSTOMERS_V3');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

DELETE FROM report_top_customers       WHERE generated_by = 'V3';
DELETE FROM report_top_customers_stage WHERE generated_by = 'V3';
COMMIT;
