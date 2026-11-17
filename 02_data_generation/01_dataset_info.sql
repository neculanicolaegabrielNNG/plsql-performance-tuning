-- Turns SCALE and SEED (from run_all.sql) into row counts and dates in DATASET_INFO.
-- 24 full months ending with the current one, so the report month is complete.

-- The CHECK constraint rejects SCALE outside (0, 1]; WHENEVER SQLERROR in run_all stops the load.
INSERT INTO dataset_info
       (dataset_id, scale_factor, random_seed, n_customers, n_whale_customers,
        n_products, n_orders, date_from, date_to, report_month)
SELECT 1,
       s.scale_factor,
       &seed,
       GREATEST(ROUND(200000  * s.scale_factor), 100),
       -- 2% whale customers, they get 30% of the orders (04_orders.sql)
       GREATEST(ROUND(200000  * s.scale_factor * 0.02), 2),
       GREATEST(ROUND(5000    * s.scale_factor), 20),
       GREATEST(ROUND(5000000 * s.scale_factor), 2500),
       ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -23),
       ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1),
       TRUNC(SYSDATE, 'MM')
  FROM (SELECT &scale AS scale_factor FROM dual) s;

COMMIT;

COLUMN scale_factor FORMAT 0.9999
SELECT scale_factor, random_seed, n_customers, n_whale_customers, n_products, n_orders,
       TO_CHAR(date_from, 'YYYY-MM-DD')    AS date_from,
       TO_CHAR(date_to, 'YYYY-MM-DD')      AS date_to,
       TO_CHAR(report_month, 'YYYY-MM-DD') AS report_month
  FROM dataset_info;
