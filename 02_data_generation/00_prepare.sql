-- Serial session, FKs disabled, tables emptied before a (re)load. Called by run_all.sql.

-- DBMS_RANDOM is only reproducible if rows come out in the same order every time;
-- parallel execution (default on some ADB services) breaks that.
ALTER SESSION DISABLE PARALLEL QUERY;
ALTER SESSION DISABLE PARALLEL DML;

-- Only a warning: loading with secondary indexes is slow and the baseline should be PKs only.
BEGIN
    FOR i IN (SELECT ui.index_name
                FROM user_indexes ui
               WHERE ui.table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS')
                 AND NOT EXISTS (SELECT 1
                                   FROM user_constraints uc
                                  WHERE uc.constraint_type = 'P'
                                    AND uc.index_name = ui.index_name))
    LOOP
        DBMS_OUTPUT.PUT_LINE('WARNING: secondary index ' || i.index_name
                             || ' exists. Rerun 01_schema/01_create_tables.sql for a clean baseline.');
    END LOOP;
END;
/

-- With FKs enabled Oracle silently ignores APPEND. Re-enabled with VALIDATE in 07_finalize.sql.
BEGIN
    FOR c IN (SELECT table_name, constraint_name
                FROM user_constraints
               WHERE constraint_type = 'R'
                 AND status = 'ENABLED'
                 AND table_name IN ('ORDERS', 'ORDER_ITEMS', 'PAYMENTS'))
    LOOP
        EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name
                          || ' DISABLE CONSTRAINT ' || c.constraint_name;
    END LOOP;
END;
/

-- TRUNCATE: no undo, and the HWM reset keeps later full scans off empty blocks.
TRUNCATE TABLE payments;
TRUNCATE TABLE order_items;
TRUNCATE TABLE orders;
TRUNCATE TABLE products;
TRUNCATE TABLE customers;

DELETE FROM report_top_customers;
DELETE FROM report_top_customers_stage;
DELETE FROM dataset_info;
COMMIT;
