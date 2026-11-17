-- Rollback step 7b: drops V7P and ORDERS_PART. ORDERS itself was never modified.
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE report_top_customers_v7p';
    DBMS_OUTPUT.PUT_LINE('Dropped REPORT_TOP_CUSTOMERS_V7P');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE orders_part CASCADE CONSTRAINTS PURGE';
    DBMS_OUTPUT.PUT_LINE('Dropped ORDERS_PART');
EXCEPTION
    WHEN OTHERS THEN
        -- ORA-00942: table or view does not exist
        IF SQLCODE != -942 THEN
            RAISE;
        END IF;
END;
/

DELETE FROM report_top_customers WHERE generated_by = 'V7P';
COMMIT;
