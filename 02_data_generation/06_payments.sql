-- PAYMENTS, one per order, status derived from the order status.
-- ORA_HASH for the same reason as ORDER_ITEMS.

INSERT /*+ APPEND */ INTO payments
       (payment_id, order_id, payment_date, amount, method, status)
SELECT o.order_id AS payment_id,
       o.order_id,
       o.order_date + ORA_HASH(o.order_id, 259200, 19) / 86400 AS payment_date,
       t.items_total + o.shipping_amount AS amount,
       DECODE(ORA_HASH(o.order_id, 9, 23),
              0, 'BANK_TRANSFER', 1, 'PAYPAL', 2, 'PAYPAL', 3, 'WALLET', 'CARD') AS method,
       CASE o.status
            WHEN 'PENDING'   THEN 'PENDING'
            WHEN 'CANCELLED' THEN CASE WHEN ORA_HASH(o.order_id, 1, 29) = 0
                                       THEN 'FAILED' ELSE 'REFUNDED' END
            WHEN 'RETURNED'  THEN 'REFUNDED'
            ELSE CASE WHEN ORA_HASH(o.order_id, 49, 31) = 0
                      THEN 'FAILED' ELSE 'COMPLETED' END
       END AS status
  FROM orders o
  JOIN (SELECT oi.order_id,
               SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS items_total
          FROM order_items oi
         GROUP BY oi.order_id) t
    ON t.order_id = o.order_id;

COMMIT;
