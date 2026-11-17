-- Rollback step 1: drops V1 and its output rows. Nothing else in the schema changed.
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE report_top_customers_v1';
    DBMS_OUTPUT.PUT_LINE('Dropped REPORT_TOP_CUSTOMERS_V1');
EXCEPTION
    WHEN OTHERS THEN
        -- ORA-04043: object does not exist
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

DELETE FROM report_top_customers       WHERE generated_by = 'V1';
DELETE FROM report_top_customers_stage WHERE generated_by = 'V1';
COMMIT;
