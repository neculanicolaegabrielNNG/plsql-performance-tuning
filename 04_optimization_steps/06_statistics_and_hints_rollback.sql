-- Rollback step 6: restores the stats saved in STATS_BACKUP (BEFORE_STEP6) and drops V6.
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_backup NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_backup FROM user_tables WHERE table_name = 'STATS_BACKUP';
    IF v_backup = 0 THEN
        RAISE_APPLICATION_ERROR(-20060, 'STATS_BACKUP not found - step 6 was never run.');
    END IF;

    FOR t IN (SELECT table_name
                FROM user_tables
               WHERE table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS'))
    LOOP
        -- Delete first: tables without stats before step 6 must end up without stats again.
        DBMS_STATS.DELETE_TABLE_STATS(ownname => USER, tabname => t.table_name,
                                      no_invalidate => FALSE);
        DBMS_STATS.IMPORT_TABLE_STATS(ownname       => USER,
                                      tabname       => t.table_name,
                                      stattab       => 'STATS_BACKUP',
                                      statid        => 'BEFORE_STEP6',
                                      cascade       => TRUE,
                                      no_invalidate => FALSE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Statistics restored from STATS_BACKUP (BEFORE_STEP6).');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE report_top_customers_v6';
    DBMS_OUTPUT.PUT_LINE('Dropped REPORT_TOP_CUSTOMERS_V6');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            RAISE;
        END IF;
END;
/

DELETE FROM report_top_customers WHERE generated_by = 'V6';
COMMIT;
