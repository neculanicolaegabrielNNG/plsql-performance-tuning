-- Rollback step 7a: drops V7 and MV_CUSTOMER_MONTH_SALES (its index goes with it).
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE report_top_customers_v7';
    DBMS_OUTPUT.PUT_LINE('Dropped REPORT_TOP_CUSTOMERS_V7');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_customer_month_sales';
    DBMS_OUTPUT.PUT_LINE('Dropped MV_CUSTOMER_MONTH_SALES');
EXCEPTION
    WHEN OTHERS THEN
        -- ORA-12003: materialized view does not exist
        IF SQLCODE != -12003 THEN
            RAISE;
        END IF;
END;
/

DELETE FROM report_top_customers WHERE generated_by = 'V7';
COMMIT;
