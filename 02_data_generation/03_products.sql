-- PRODUCTS (5k at SCALE = 1). Price is a pure function of product_id (5.00-500.00),
-- so 05_order_items.sql can compute it without joining PRODUCTS.
COLUMN n_products_txt NEW_VALUE v_n_products NOPRINT
COLUMN date_from_txt  NEW_VALUE v_date_from  NOPRINT
COLUMN seed_txt       NEW_VALUE v_seed       NOPRINT
SELECT TO_CHAR(n_products)              AS n_products_txt,
       TO_CHAR(date_from, 'YYYY-MM-DD') AS date_from_txt,
       TO_CHAR(random_seed + 1)         AS seed_txt
  FROM dataset_info
 WHERE dataset_id = 1;

BEGIN
    DBMS_RANDOM.SEED(&v_seed);
END;
/

INSERT /*+ APPEND */ INTO products
       (product_id, product_name, category, unit_price, is_active, created_at)
SELECT g.n,
       'Product ' || LPAD(TO_CHAR(g.n), 5, '0'),
       DECODE(MOD(g.n, 8),
              0, 'ELECTRONICS', 1, 'BOOKS', 2, 'HOME', 3, 'GARDEN',
              4, 'TOYS', 5, 'SPORTS', 6, 'BEAUTY', 'GROCERY'),
       5 + ORA_HASH(g.n, 49500, 7) / 100,
       CASE WHEN DBMS_RANDOM.VALUE < 0.97 THEN 'Y' ELSE 'N' END,
       TO_DATE('&v_date_from', 'YYYY-MM-DD') - TRUNC(DBMS_RANDOM.VALUE(1, 730))
  FROM (SELECT ROWNUM AS n
          FROM (SELECT 1 FROM dual CONNECT BY LEVEL <= 5000) a,
               (SELECT 1 FROM dual CONNECT BY LEVEL <= 5000) b
         WHERE ROWNUM <= &v_n_products) g;

COMMIT;
