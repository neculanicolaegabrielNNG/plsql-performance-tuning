-- Rollback step 2: drops the three indexes and V2. V3+ plans rely on them, so roll those back first.
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    PROCEDURE drop_if_exists (p_sql IN VARCHAR2, p_missing_code IN PLS_INTEGER) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
        DBMS_OUTPUT.PUT_LINE('done: ' || p_sql);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != p_missing_code THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('skipped (does not exist): ' || p_sql);
    END drop_if_exists;
BEGIN
    -- ORA-01418: specified index does not exist; ORA-04043: object does not exist
    drop_if_exists('DROP INDEX orders_cust_date_ix', -1418);
    drop_if_exists('DROP INDEX orders_date_status_ix', -1418);
    drop_if_exists('DROP INDEX payments_order_ix', -1418);
    drop_if_exists('DROP PROCEDURE report_top_customers_v2', -4043);
END;
/

DELETE FROM report_top_customers       WHERE generated_by = 'V2';
DELETE FROM report_top_customers_stage WHERE generated_by = 'V2';
COMMIT;
