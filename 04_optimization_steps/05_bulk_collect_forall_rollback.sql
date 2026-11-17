-- Rollback step 5: drops V5 and its output rows (code-only step).
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE report_top_customers_v5';
    DBMS_OUTPUT.PUT_LINE('Dropped REPORT_TOP_CUSTOMERS_V5');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

DELETE FROM report_top_customers WHERE generated_by = 'V5';
COMMIT;
