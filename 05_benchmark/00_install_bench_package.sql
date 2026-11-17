-- PERF_BENCH: runs report versions by code and benchmarks them into BENCHMARK_RUNS.
-- Invoker rights + dynamic SQL on V$MYSTAT, so a role is enough; without access the I/O columns stay NULL.
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON

CREATE OR REPLACE PACKAGE perf_bench AUTHID CURRENT_USER AS

    FUNCTION proc_name (p_version IN VARCHAR2) RETURN VARCHAR2;

    FUNCTION dataset_month RETURN DATE;

    FUNCTION is_installed (p_version IN VARCHAR2) RETURN BOOLEAN;

    PROCEDURE run_report (
        p_version IN VARCHAR2,
        p_month   IN DATE,
        p_top_n   IN PLS_INTEGER DEFAULT 100
    );

    PROCEDURE benchmark (
        p_version IN VARCHAR2,
        p_label   IN VARCHAR2    DEFAULT 'manual',
        p_runs    IN PLS_INTEGER DEFAULT 5,
        p_warmup  IN PLS_INTEGER DEFAULT 1,
        p_month   IN DATE        DEFAULT NULL,
        p_top_n   IN PLS_INTEGER DEFAULT 100
    );

END perf_bench;
/
SHOW ERRORS PACKAGE perf_bench

CREATE OR REPLACE PACKAGE BODY perf_bench AS

    TYPE t_stats IS RECORD (
        consistent_gets NUMBER,
        db_block_gets   NUMBER,
        physical_reads  NUMBER,
        redo_bytes      NUMBER
    );

    g_stats_available BOOLEAN := TRUE;

    -- Whitelist: the dynamic call in run_report can only reach these procedures.
    FUNCTION proc_name (p_version IN VARCHAR2) RETURN VARCHAR2 IS
        v_code VARCHAR2(10) := UPPER(TRIM(p_version));
    BEGIN
        IF v_code IN ('SLOW', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6', 'V7', 'V7P') THEN
            RETURN 'REPORT_TOP_CUSTOMERS_' || v_code;
        END IF;
        RAISE_APPLICATION_ERROR(-20100, 'Unknown version code: ' || p_version
                                        || ' (expected SLOW, V1..V7, V7P)');
    END proc_name;

    FUNCTION dataset_month RETURN DATE IS
        v_month DATE;
    BEGIN
        SELECT report_month INTO v_month FROM dataset_info WHERE dataset_id = 1;
        RETURN v_month;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20101, 'DATASET_INFO is empty - run 02_data_generation/run_all.sql');
    END dataset_month;

    FUNCTION is_installed (p_version IN VARCHAR2) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        -- Status not checked: an INVALID procedure recompiles on its next call, or fails loudly.
        SELECT COUNT(*)
          INTO v_count
          FROM user_objects
         WHERE object_type = 'PROCEDURE'
           AND object_name = proc_name(p_version);
        RETURN v_count > 0;
    END is_installed;

    FUNCTION snapshot RETURN t_stats IS
        v t_stats;
    BEGIN
        IF g_stats_available THEN
            EXECUTE IMMEDIATE q'[
                SELECT MAX(CASE sn.name WHEN 'consistent gets' THEN ms.value END),
                       MAX(CASE sn.name WHEN 'db block gets'   THEN ms.value END),
                       MAX(CASE sn.name WHEN 'physical reads'  THEN ms.value END),
                       MAX(CASE sn.name WHEN 'redo size'       THEN ms.value END)
                  FROM v$mystat ms
                  JOIN v$statname sn
                    ON sn.statistic# = ms.statistic#
                 WHERE sn.name IN ('consistent gets', 'db block gets', 'physical reads', 'redo size')]'
               INTO v.consistent_gets, v.db_block_gets, v.physical_reads, v.redo_bytes;
        END IF;
        RETURN v;
    EXCEPTION
        WHEN OTHERS THEN
            g_stats_available := FALSE;
            DBMS_OUTPUT.PUT_LINE('WARNING: cannot read V$MYSTAT (' || SQLERRM
                                 || '). Logical I/O columns will be NULL.');
            RETURN v;
    END snapshot;

    FUNCTION ms_between (p_t0 IN TIMESTAMP WITH TIME ZONE,
                         p_t1 IN TIMESTAMP WITH TIME ZONE) RETURN NUMBER IS
        v_int INTERVAL DAY(9) TO SECOND(6) := p_t1 - p_t0;
    BEGIN
        RETURN ROUND(  EXTRACT(DAY    FROM v_int) * 86400000
                     + EXTRACT(HOUR   FROM v_int) * 3600000
                     + EXTRACT(MINUTE FROM v_int) * 60000
                     + EXTRACT(SECOND FROM v_int) * 1000, 3);
    END ms_between;

    PROCEDURE run_report (
        p_version IN VARCHAR2,
        p_month   IN DATE,
        p_top_n   IN PLS_INTEGER DEFAULT 100
    ) IS
        v_proc  VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(proc_name(p_version));
        v_top_n NUMBER        := p_top_n;
    BEGIN
        EXECUTE IMMEDIATE 'BEGIN ' || v_proc || '(p_report_month => :m, p_top_n => :n); END;'
            USING IN p_month, IN v_top_n;
    END run_report;

    PROCEDURE benchmark (
        p_version IN VARCHAR2,
        p_label   IN VARCHAR2    DEFAULT 'manual',
        p_runs    IN PLS_INTEGER DEFAULT 5,
        p_warmup  IN PLS_INTEGER DEFAULT 1,
        p_month   IN DATE        DEFAULT NULL,
        p_top_n   IN PLS_INTEGER DEFAULT 100
    ) IS
        v_code    VARCHAR2(10) := UPPER(TRIM(p_version));
        v_month   DATE;
        v_warmup  PLS_INTEGER  := NVL(p_warmup, 0);
        v_batch   VARCHAR2(30) := TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD"T"HH24MISS.FF3');
        s0        t_stats;
        s1        t_stats;
        v_t0      TIMESTAMP WITH TIME ZONE;
        v_t1      TIMESTAMP WITH TIME ZONE;
        v_cpu0    NUMBER;
        v_cpu1    NUMBER;
        v_rows    NUMBER;
        v_elapsed NUMBER;
        v_med_ms  NUMBER;
        v_med_cg  NUMBER;
    BEGIN
        IF p_runs IS NULL OR p_runs < 1 THEN
            RAISE_APPLICATION_ERROR(-20102, 'p_runs must be >= 1');
        END IF;
        IF NOT is_installed(v_code) THEN
            DBMS_OUTPUT.PUT_LINE('SKIPPED ' || v_code || ': procedure ' || proc_name(v_code)
                                 || ' is not installed.');
            RETURN;
        END IF;

        v_month := NVL(TRUNC(p_month, 'MM'), dataset_month);
        DBMS_OUTPUT.PUT_LINE('Benchmark ' || v_code || ' label=' || p_label
                             || ' month=' || TO_CHAR(v_month, 'YYYY-MM')
                             || ' warm-up=' || v_warmup || ' runs=' || p_runs);

        FOR i IN 1 .. v_warmup + p_runs LOOP
            s0     := snapshot;
            v_cpu0 := DBMS_UTILITY.GET_CPU_TIME;
            v_t0   := SYSTIMESTAMP;

            run_report(v_code, v_month, p_top_n);

            v_t1   := SYSTIMESTAMP;
            v_cpu1 := DBMS_UTILITY.GET_CPU_TIME;
            s1     := snapshot;

            SELECT COUNT(*)
              INTO v_rows
              FROM report_top_customers
             WHERE generated_by = v_code
               AND report_month = v_month;

            v_elapsed := ms_between(v_t0, v_t1);

            INSERT INTO benchmark_runs
                   (batch_id, label, version_code, run_no, is_warmup, report_month, top_n,
                    elapsed_ms, cpu_ms, consistent_gets, db_block_gets, physical_reads,
                    redo_bytes, rows_written)
            VALUES (v_batch, p_label, v_code, i,
                    CASE WHEN i <= v_warmup THEN 'Y' ELSE 'N' END,
                    v_month, p_top_n, v_elapsed,
                    (v_cpu1 - v_cpu0) * 10,
                    s1.consistent_gets - s0.consistent_gets,
                    s1.db_block_gets   - s0.db_block_gets,
                    s1.physical_reads  - s0.physical_reads,
                    s1.redo_bytes      - s0.redo_bytes,
                    v_rows);
            COMMIT;

            DBMS_OUTPUT.PUT_LINE('  run ' || i
                                 || CASE WHEN i <= v_warmup THEN ' (warm-up)' END
                                 || ': ' || v_elapsed || ' ms, consistent gets '
                                 || NVL(TO_CHAR(s1.consistent_gets - s0.consistent_gets), 'n/a')
                                 || ', rows ' || v_rows);
        END LOOP;

        SELECT MEDIAN(elapsed_ms), MEDIAN(consistent_gets)
          INTO v_med_ms, v_med_cg
          FROM benchmark_runs
         WHERE batch_id     = v_batch
           AND version_code = v_code
           AND is_warmup    = 'N';

        DBMS_OUTPUT.PUT_LINE('  MEDIAN ' || v_code || ': ' || v_med_ms || ' ms, consistent gets '
                             || NVL(TO_CHAR(v_med_cg), 'n/a') || '  (batch ' || v_batch || ')');
    END benchmark;

END perf_bench;
/
SHOW ERRORS PACKAGE BODY perf_bench
