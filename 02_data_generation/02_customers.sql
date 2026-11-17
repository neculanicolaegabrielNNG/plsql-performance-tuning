-- CUSTOMERS (200k at SCALE = 1). Random name combinations, e-mails on example.com.
COLUMN n_customers_txt NEW_VALUE v_n_customers NOPRINT
COLUMN date_from_txt   NEW_VALUE v_date_from   NOPRINT
COLUMN seed_txt        NEW_VALUE v_seed        NOPRINT
SELECT TO_CHAR(n_customers)             AS n_customers_txt,
       TO_CHAR(date_from, 'YYYY-MM-DD') AS date_from_txt,
       TO_CHAR(random_seed)             AS seed_txt
  FROM dataset_info
 WHERE dataset_id = 1;

-- Separate seed per table so each one is reproducible on its own.
BEGIN
    DBMS_RANDOM.SEED(&v_seed);
END;
/

-- Two 5000-row generators cross-joined: one CONNECT BY LEVEL <= 5000000 can hit ORA-30009.
-- ROWNUM in the inline view also blocks view merging, so DBMS_RANDOM runs once per row.
INSERT /*+ APPEND */ INTO customers
       (customer_id, first_name, last_name, email, country_code, segment, status, created_at)
SELECT g.n,
       DECODE(TRUNC(DBMS_RANDOM.VALUE(0, 12)),
              0, 'Ana', 1, 'Mihai', 2, 'Elena', 3, 'Andrei', 4, 'Ioana', 5, 'Radu',
              6, 'Sofia', 7, 'Lucas', 8, 'Maria', 9, 'David', 10, 'Irina', 'Paul'),
       DECODE(TRUNC(DBMS_RANDOM.VALUE(0, 10)),
              0, 'Popescu', 1, 'Smith', 2, 'Muller', 3, 'Rossi', 4, 'Garcia',
              5, 'Novak', 6, 'Dubois', 7, 'Jansen', 8, 'Kowalski', 'Silva'),
       'customer' || g.n || '@example.com',
       DECODE(TRUNC(DBMS_RANDOM.VALUE(0, 8)),
              0, 'RO', 1, 'DE', 2, 'FR', 3, 'IT', 4, 'ES', 5, 'NL', 6, 'PL', 'GB'),
       CASE WHEN DBMS_RANDOM.VALUE < 0.10 THEN 'BUSINESS' ELSE 'CONSUMER' END,
       CASE WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'ACTIVE' ELSE 'INACTIVE' END,
       -- up to 3 years before the first order date
       TO_DATE('&v_date_from', 'YYYY-MM-DD') - TRUNC(DBMS_RANDOM.VALUE(1, 1096))
  FROM (SELECT ROWNUM AS n
          FROM (SELECT 1 FROM dual CONNECT BY LEVEL <= 5000) a,
               (SELECT 1 FROM dual CONNECT BY LEVEL <= 5000) b
         WHERE ROWNUM <= &v_n_customers) g;

-- Direct-path insert must be committed before the table is read again (ORA-12838).
COMMIT;
