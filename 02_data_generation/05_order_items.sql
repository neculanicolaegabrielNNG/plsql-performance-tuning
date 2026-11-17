-- ORDER_ITEMS, 1-5 lines per order (~15M at SCALE = 1). ORA_HASH instead of DBMS_RANDOM:
-- row order here depends on the plan, a hash of the key does not.
COLUMN n_products_txt NEW_VALUE v_n_products NOPRINT
SELECT TO_CHAR(n_products) AS n_products_txt
  FROM dataset_info
 WHERE dataset_id = 1;

INSERT /*+ APPEND */ INTO order_items
       (order_id, line_no, product_id, quantity, unit_price, discount_pct)
SELECT x.order_id,
       x.line_no,
       x.product_id,
       x.quantity,
       5 + ORA_HASH(x.product_id, 49500, 7) / 100 AS unit_price,
       x.discount_pct
  FROM (SELECT o.order_id,
               l.line_no,
               TRUNC(POWER(ORA_HASH(o.order_id * 10 + l.line_no, 999999, 11) / 1000000, 2)
                     * &v_n_products) + 1 AS product_id,
               1 + ORA_HASH(o.order_id * 10 + l.line_no, 3, 13) AS quantity,
               DECODE(ORA_HASH(o.order_id * 10 + l.line_no, 9, 17),
                      0, 5, 1, 10, 2, 15, 3, 20, 0) AS discount_pct
          FROM orders o
          JOIN (SELECT LEVEL AS line_no FROM dual CONNECT BY LEVEL <= 5) l
            ON l.line_no <= 1 + ORA_HASH(o.order_id, 4, 3)) x;

COMMIT;
