-- 1 warm-up + 5 measured runs of one version into BENCHMARK_RUNS, prints the median.
-- Usage: @05_benchmark/02_benchmark_version.sql V4 after_step4   (label = schema state)
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET FEEDBACK OFF

DEFINE version_code = '&1'
DEFINE run_label    = '&2'

BEGIN
    perf_bench.benchmark(p_version => '&version_code',
                         p_label   => '&run_label',
                         p_runs    => 5,
                         p_warmup  => 1);
END;
/

SET FEEDBACK ON
