-- Drops every project object that exists; safe to rerun. Called by 01_create_tables.sql.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON

PROMPT Dropping project objects (only those that exist)...

DECLARE
    PROCEDURE exec_ddl (p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
        DBMS_OUTPUT.PUT_LINE('  done: ' || p_sql);
    END exec_ddl;
BEGIN
    -- MV first: it depends on ORDERS and ORDER_ITEMS.
    FOR o IN (SELECT mview_name
                FROM user_mviews
               WHERE mview_name = 'MV_CUSTOMER_MONTH_SALES')
    LOOP
        exec_ddl('DROP MATERIALIZED VIEW ' || o.mview_name);
    END LOOP;

    FOR o IN (SELECT object_type, object_name
                FROM user_objects
               WHERE (object_type = 'PROCEDURE' AND object_name LIKE 'REPORT_TOP_CUSTOMERS%')
                  OR (object_type = 'PACKAGE'   AND object_name = 'PERF_BENCH'))
    LOOP
        exec_ddl('DROP ' || o.object_type || ' ' || o.object_name);
    END LOOP;

    -- CASCADE CONSTRAINTS drops the FKs, so table order doesn't matter.
    FOR t IN (SELECT table_name
                FROM user_tables
               WHERE table_name IN ('BENCHMARK_RUNS', 'REPORT_TOP_CUSTOMERS_STAGE',
                                    'REPORT_TOP_CUSTOMERS', 'PAYMENTS', 'ORDER_ITEMS',
                                    'ORDERS_PART', 'ORDERS', 'PRODUCTS', 'CUSTOMERS',
                                    'DATASET_INFO', 'STATS_BACKUP'))
    LOOP
        exec_ddl('DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE');
    END LOOP;
END;
/
