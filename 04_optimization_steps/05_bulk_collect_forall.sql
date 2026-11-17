-- Step 5: V5 = V4's query as a cursor, BULK COLLECT ... LIMIT + FORALL, one COMMIT.
-- The row-level part is only a data-quality guard; expect V5 close to V4, not faster.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON

CREATE OR REPLACE PROCEDURE report_top_customers_v5 (
    p_report_month IN DATE        DEFAULT TRUNC(SYSDATE, 'MM'),
    p_top_n        IN PLS_INTEGER DEFAULT 100
)
AS
    c_generated_by CONSTANT VARCHAR2(10) := 'V5';
    -- Big enough to make context switches negligible, small enough for PGA.
    c_batch_size   CONSTANT PLS_INTEGER  := 500;

    v_month_start  DATE;
    v_month_end    DATE;

    CURSOR c_top (cp_month_start DATE, cp_month_end DATE, cp_top_n NUMBER) IS
        WITH month_sales AS (
            SELECT o.customer_id,
                   COUNT(DISTINCT o.order_id) AS orders_count,
                   SUM(ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2)) AS orders_total
              FROM orders o
              JOIN order_items oi
                ON oi.order_id = o.order_id
             WHERE o.order_date >= cp_month_start
               AND o.order_date <  cp_month_end
               AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
             GROUP BY o.customer_id
        ),
        ranked AS (
            SELECT ms.customer_id, ms.orders_count, ms.orders_total,
                   ROW_NUMBER() OVER (ORDER BY ms.orders_total DESC, ms.customer_id) AS rank_no
              FROM month_sales ms
        ),
        top_customers AS (
            SELECT r.customer_id, r.orders_count, r.orders_total, r.rank_no
              FROM ranked r
             WHERE r.rank_no <= cp_top_n
        ),
        last_payment AS (
            SELECT o.customer_id, MAX(p.payment_date) AS last_payment_date
              FROM top_customers t
              JOIN orders o
                ON o.customer_id = t.customer_id
              JOIN payments p
                ON p.order_id = o.order_id
             WHERE p.status = 'COMPLETED'
             GROUP BY o.customer_id
        )
        SELECT t.rank_no,
               c.customer_id,
               c.first_name,
               c.last_name,
               c.email,
               c.country_code,
               t.orders_count,
               t.orders_total,
               lp.last_payment_date
          FROM top_customers t
          JOIN customers c
            ON c.customer_id = t.customer_id
          LEFT JOIN last_payment lp
            ON lp.customer_id = t.customer_id
         ORDER BY t.rank_no;

    TYPE t_top_tab IS TABLE OF c_top%ROWTYPE INDEX BY PLS_INTEGER;
    TYPE t_out_tab IS TABLE OF report_top_customers%ROWTYPE INDEX BY PLS_INTEGER;

    l_rows t_top_tab;
    l_out  t_out_tab;
BEGIN
    IF p_report_month IS NULL OR p_top_n IS NULL OR p_top_n < 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'p_report_month must not be NULL and p_top_n must be >= 1');
    END IF;
    v_month_start := TRUNC(p_report_month, 'MM');
    v_month_end   := ADD_MONTHS(v_month_start, 1);

    DELETE FROM report_top_customers
     WHERE generated_by = c_generated_by
       AND report_month = v_month_start;

    OPEN c_top(v_month_start, v_month_end, p_top_n);
    LOOP
        FETCH c_top BULK COLLECT INTO l_rows LIMIT c_batch_size;
        EXIT WHEN l_rows.COUNT = 0;

        l_out.DELETE;
        FOR i IN 1 .. l_rows.COUNT LOOP
            -- Stand-in for row logic that really needs PL/SQL; no SQL in this loop.
            IF l_rows(i).orders_count < 1 OR l_rows(i).orders_total < 0 THEN
                RAISE_APPLICATION_ERROR(-20010, 'Data-quality rule violated for customer '
                                                || l_rows(i).customer_id);
            END IF;

            l_out(i).generated_by      := c_generated_by;
            l_out(i).report_month      := v_month_start;
            l_out(i).rank_no           := l_rows(i).rank_no;
            l_out(i).customer_id       := l_rows(i).customer_id;
            l_out(i).customer_name     := l_rows(i).first_name || ' ' || l_rows(i).last_name;
            l_out(i).email             := l_rows(i).email;
            l_out(i).country_code      := l_rows(i).country_code;
            l_out(i).orders_count      := l_rows(i).orders_count;
            l_out(i).orders_total      := l_rows(i).orders_total;
            l_out(i).last_payment_date := l_rows(i).last_payment_date;
            -- Record inserts bypass column defaults.
            l_out(i).created_at        := SYSTIMESTAMP;
        END LOOP;

        FORALL i IN 1 .. l_out.COUNT
            INSERT INTO report_top_customers VALUES l_out(i);
    END LOOP;
    CLOSE c_top;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        IF c_top%ISOPEN THEN
            CLOSE c_top;
        END IF;
        ROLLBACK;
        RAISE;
END report_top_customers_v5;
/
SHOW ERRORS PROCEDURE report_top_customers_v5
