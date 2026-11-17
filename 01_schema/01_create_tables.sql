-- Creates the shop schema with PKs and FKs only; secondary indexes come in step 2.
-- Drops every project object first (99_drop_all.sql). Run from the project root.
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON

@@99_drop_all.sql

PROMPT Creating tables...

-- One row. Benchmarks read the report month from here, so they don't drift
-- when the calendar month changes.
CREATE TABLE dataset_info (
    dataset_id         NUMBER(1)    DEFAULT 1 NOT NULL,
    scale_factor       NUMBER       NOT NULL,
    random_seed        NUMBER       NOT NULL,
    n_customers        NUMBER(10)   NOT NULL,
    n_whale_customers  NUMBER(10)   NOT NULL,
    n_products         NUMBER(10)   NOT NULL,
    n_orders           NUMBER(12)   NOT NULL,
    date_from          DATE         NOT NULL,
    date_to            DATE         NOT NULL,
    report_month       DATE         NOT NULL,
    generated_at       DATE         DEFAULT SYSDATE NOT NULL,
    CONSTRAINT dataset_info_pk PRIMARY KEY (dataset_id),
    CONSTRAINT dataset_info_one_row_ck CHECK (dataset_id = 1),
    CONSTRAINT dataset_info_scale_ck CHECK (scale_factor > 0 AND scale_factor <= 1)
);

CREATE TABLE customers (
    customer_id   NUMBER(10)     NOT NULL,
    first_name    VARCHAR2(50)   NOT NULL,
    last_name     VARCHAR2(50)   NOT NULL,
    email         VARCHAR2(120)  NOT NULL,
    country_code  VARCHAR2(2)    NOT NULL,
    segment       VARCHAR2(12)   NOT NULL,
    status        VARCHAR2(10)   NOT NULL,
    created_at    DATE           NOT NULL,
    CONSTRAINT customers_pk PRIMARY KEY (customer_id),
    CONSTRAINT customers_status_ck CHECK (status IN ('ACTIVE', 'INACTIVE'))
);

CREATE TABLE products (
    product_id    NUMBER(10)     NOT NULL,
    product_name  VARCHAR2(100)  NOT NULL,
    category      VARCHAR2(30)   NOT NULL,
    unit_price    NUMBER(10,2)   NOT NULL,
    is_active     CHAR(1)        NOT NULL,
    created_at    DATE           NOT NULL,
    CONSTRAINT products_pk PRIMARY KEY (product_id),
    CONSTRAINT products_active_ck CHECK (is_active IN ('Y', 'N'))
);

-- NOTES is filler so SELECT * and full scans cost what they would on a real, wide table.
CREATE TABLE orders (
    order_id         NUMBER(12)     NOT NULL,
    customer_id      NUMBER(10)     NOT NULL,
    order_date       DATE           NOT NULL,
    status           VARCHAR2(12)   NOT NULL,
    channel          VARCHAR2(12)   NOT NULL,
    shipping_amount  NUMBER(8,2)    NOT NULL,
    notes            VARCHAR2(200),
    CONSTRAINT orders_pk PRIMARY KEY (order_id),
    CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    CONSTRAINT orders_status_ck CHECK (status IN ('PENDING', 'PAID', 'SHIPPED',
                                                  'DELIVERED', 'CANCELLED', 'RETURNED'))
);

-- Composite PK (order_id, line_no): the PK index doubles as the order_id lookup.
-- Without it the N+1 slow version would scan every order line per customer and never finish.
CREATE TABLE order_items (
    order_id      NUMBER(12)    NOT NULL,
    line_no       NUMBER(3)     NOT NULL,
    product_id    NUMBER(10)    NOT NULL,
    quantity      NUMBER(5)     NOT NULL,
    unit_price    NUMBER(10,2)  NOT NULL,
    discount_pct  NUMBER(5,2)   DEFAULT 0 NOT NULL,
    CONSTRAINT order_items_pk PRIMARY KEY (order_id, line_no),
    CONSTRAINT order_items_order_fk FOREIGN KEY (order_id) REFERENCES orders (order_id),
    CONSTRAINT order_items_product_fk FOREIGN KEY (product_id) REFERENCES products (product_id),
    CONSTRAINT order_items_qty_ck CHECK (quantity > 0),
    CONSTRAINT order_items_discount_ck CHECK (discount_pct BETWEEN 0 AND 100)
);

CREATE TABLE payments (
    payment_id    NUMBER(12)    NOT NULL,
    order_id      NUMBER(12)    NOT NULL,
    payment_date  DATE          NOT NULL,
    amount        NUMBER(12,2)  NOT NULL,
    method        VARCHAR2(15)  NOT NULL,
    status        VARCHAR2(10)  NOT NULL,
    CONSTRAINT payments_pk PRIMARY KEY (payment_id),
    CONSTRAINT payments_order_fk FOREIGN KEY (order_id) REFERENCES orders (order_id),
    CONSTRAINT payments_status_ck CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED'))
);

-- Shared by all versions, tagged by GENERATED_BY, so outputs can be compared with MINUS.
CREATE TABLE report_top_customers (
    generated_by       VARCHAR2(10)   NOT NULL,
    report_month       DATE           NOT NULL,
    rank_no            NUMBER(6)      NOT NULL,
    customer_id        NUMBER(10)     NOT NULL,
    customer_name      VARCHAR2(101)  NOT NULL,
    email              VARCHAR2(120)  NOT NULL,
    country_code       VARCHAR2(2)    NOT NULL,
    orders_count       NUMBER(10)     NOT NULL,
    orders_total       NUMBER(14,2)   NOT NULL,
    last_payment_date  DATE,
    created_at         TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT report_top_customers_pk PRIMARY KEY (generated_by, report_month, rank_no)
);

-- Scratch table for the row-by-row versions (SLOW..V3) only.
CREATE TABLE report_top_customers_stage (
    generated_by       VARCHAR2(10)   NOT NULL,
    customer_id        NUMBER(10)     NOT NULL,
    orders_count       NUMBER(10)     NOT NULL,
    orders_total       NUMBER(14,2)   NOT NULL,
    last_payment_date  DATE,
    CONSTRAINT report_top_customers_stage_pk PRIMARY KEY (generated_by, customer_id)
);

CREATE TABLE benchmark_runs (
    run_id           NUMBER GENERATED ALWAYS AS IDENTITY,
    batch_id         VARCHAR2(30)  NOT NULL,
    label            VARCHAR2(60)  NOT NULL,
    version_code     VARCHAR2(10)  NOT NULL,
    run_no           NUMBER(3)     NOT NULL,
    is_warmup        CHAR(1)       NOT NULL,
    report_month     DATE          NOT NULL,
    top_n            NUMBER(6)     NOT NULL,
    elapsed_ms       NUMBER,
    cpu_ms           NUMBER,
    consistent_gets  NUMBER,
    db_block_gets    NUMBER,
    physical_reads   NUMBER,
    redo_bytes       NUMBER,
    rows_written     NUMBER,
    run_ts           TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT benchmark_runs_pk PRIMARY KEY (run_id),
    CONSTRAINT benchmark_runs_warmup_ck CHECK (is_warmup IN ('Y', 'N'))
);

PROMPT
PROMPT Indexes present now (expected: primary keys only):
COLUMN table_name FORMAT A28
COLUMN index_name FORMAT A32
SELECT table_name, index_name, uniqueness
  FROM user_indexes
 WHERE table_name IN ('CUSTOMERS', 'PRODUCTS', 'ORDERS', 'ORDER_ITEMS', 'PAYMENTS')
 ORDER BY table_name, index_name;

PROMPT Schema created. Next: @05_benchmark/00_install_bench_package.sql and @02_data_generation/run_all.sql
