-- Generates the dataset. Prompts for SCALE (0 < SCALE <= 1, dot as decimal separator;
-- 1 = 5M orders, default 0.05 = ~1.26M rows). Run from the project root after 01_create_tables.sql.
SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100

WHENEVER SQLERROR EXIT FAILURE ROLLBACK

ACCEPT scale CHAR DEFAULT '0.05' PROMPT 'SCALE factor, 0 < SCALE <= 1 (1 = 5M orders) [0.05]: '
DEFINE seed = 42

PROMPT === 00 prepare (serial session, disable FKs, truncate) ===
@@00_prepare.sql
PROMPT === 01 dataset_info (SCALE = &scale, seed = &seed) ===
@@01_dataset_info.sql
PROMPT === 02 customers ===
@@02_customers.sql
PROMPT === 03 products ===
@@03_products.sql
PROMPT === 04 orders ===
@@04_orders.sql
PROMPT === 05 order_items ===
@@05_order_items.sql
PROMPT === 06 payments ===
@@06_payments.sql
PROMPT === 07 finalize (enable FKs, reset statistics, row counts) ===
@@07_finalize.sql

WHENEVER SQLERROR CONTINUE
SET TIMING OFF
