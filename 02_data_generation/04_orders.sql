-- ORDERS (5M at SCALE = 1) over the 24 months in DATASET_INFO. 30% of the orders go to
-- the whale customers (ids 1..n_whale_customers), so histograms in step 6 have skew to find.
COLUMN n_orders_txt    NEW_VALUE v_n_orders    NOPRINT
COLUMN n_customers_txt NEW_VALUE v_n_customers NOPRINT
COLUMN n_whales_txt    NEW_VALUE v_n_whales    NOPRINT
COLUMN date_from_txt   NEW_VALUE v_date_from   NOPRINT
COLUMN seconds_txt     NEW_VALUE v_seconds     NOPRINT
COLUMN seed_txt        NEW_VALUE v_seed        NOPRINT
SELECT TO_CHAR(n_orders)                     AS n_orders_txt,
       TO_CHAR(n_customers)                  AS n_customers_txt,
       TO_CHAR(n_whale_customers)            AS n_whales_txt,
       TO_CHAR(date_from, 'YYYY-MM-DD')      AS date_from_txt,
       TO_CHAR((date_to - date_from) * 86400) AS seconds_txt,
       TO_CHAR(random_seed + 2)              AS seed_txt
  FROM dataset_info
 WHERE dataset_id = 1;

BEGIN
    DBMS_RANDOM.SEED(&v_seed);
END;
/

-- NO_MERGE on d: the random numbers are drawn once per row; a merged view could call
-- DBMS_RANDOM again for every column reference.
-- order_id follows order_date, so rows are stored roughly in date order like a real table.
-- Second precision on purpose: the time part is what makes naive code reach for TRUNC.
INSERT /*+ APPEND */ INTO orders
       (order_id, customer_id, order_date, status, channel, shipping_amount, notes)
SELECT ROW_NUMBER() OVER (ORDER BY r.order_date, r.rn) AS order_id,
       r.customer_id,
       r.order_date,
       r.status,
       r.channel,
       r.shipping_amount,
       CASE WHEN MOD(r.rn, 5) = 0
            THEN 'Gift wrap requested. Leave the parcel at the reception desk if nobody answers.'
       END AS notes
  FROM (SELECT /*+ NO_MERGE */
               d.rn,
               CASE WHEN d.u_whale < 0.30
                    THEN TRUNC(d.u_cust * &v_n_whales) + 1
                    ELSE TRUNC(d.u_cust * &v_n_customers) + 1
               END AS customer_id,
               TO_DATE('&v_date_from', 'YYYY-MM-DD') + TRUNC(d.u_date * &v_seconds) / 86400 AS order_date,
               CASE WHEN d.u_status < 0.55 THEN 'DELIVERED'
                    WHEN d.u_status < 0.70 THEN 'SHIPPED'
                    WHEN d.u_status < 0.80 THEN 'PAID'
                    WHEN d.u_status < 0.88 THEN 'PENDING'
                    WHEN d.u_status < 0.96 THEN 'CANCELLED'
                    ELSE 'RETURNED'
               END AS status,
               CASE WHEN d.u_channel < 0.60 THEN 'WEB'
                    WHEN d.u_channel < 0.90 THEN 'MOBILE'
                    ELSE 'MARKETPLACE'
               END AS channel,
               CASE WHEN d.u_ship < 0.40 THEN 0
                    ELSE ROUND(2.99 + d.u_ship * 10, 2)
               END AS shipping_amount
          FROM (SELECT /*+ NO_MERGE */
                       g.rn,
                       DBMS_RANDOM.VALUE AS u_whale,
                       DBMS_RANDOM.VALUE AS u_cust,
                       DBMS_RANDOM.VALUE AS u_date,
                       DBMS_RANDOM.VALUE AS u_status,
                       DBMS_RANDOM.VALUE AS u_channel,
                       DBMS_RANDOM.VALUE AS u_ship
                  FROM (SELECT ROWNUM AS rn
                          FROM (SELECT 1 FROM dual CONNECT BY LEVEL <= 5000) a,
                               (SELECT 1 FROM dual CONNECT BY LEVEL <= 5000) b
                         WHERE ROWNUM <= &v_n_orders) g
               ) d
       ) r;

COMMIT;
