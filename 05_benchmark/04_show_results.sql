-- Median/min/max per (label, version) from BENCHMARK_RUNS, latest batch only, no warm-ups.
SET LINESIZE 220
SET PAGESIZE 100

COLUMN label           FORMAT A16
COLUMN version_code    FORMAT A7  HEADING 'VERSION'
COLUMN runs            FORMAT 990
COLUMN median_ms       FORMAT 999,999,990.9
COLUMN min_ms          FORMAT 999,999,990.9
COLUMN max_ms          FORMAT 999,999,990.9
COLUMN median_cpu_ms   FORMAT 999,999,990
COLUMN median_gets     FORMAT 999,999,999,990
COLUMN median_phys     FORMAT 999,999,990
COLUMN speedup_vs_slow FORMAT 999,990.0 HEADING 'SPEEDUP|VS SLOW'

WITH latest AS (
    SELECT label, version_code, MAX(batch_id) AS batch_id
      FROM benchmark_runs
     GROUP BY label, version_code
),
summary AS (
    SELECT b.label,
           b.version_code,
           COUNT(*)                 AS runs,
           MEDIAN(b.elapsed_ms)     AS median_ms,
           MIN(b.elapsed_ms)        AS min_ms,
           MAX(b.elapsed_ms)        AS max_ms,
           MEDIAN(b.cpu_ms)         AS median_cpu_ms,
           MEDIAN(b.consistent_gets) AS median_gets,
           MEDIAN(b.physical_reads) AS median_phys,
           MIN(b.run_ts)            AS first_run
      FROM benchmark_runs b
      JOIN latest l
        ON l.label        = b.label
       AND l.version_code = b.version_code
       AND l.batch_id     = b.batch_id
     WHERE b.is_warmup = 'N'
     GROUP BY b.label, b.version_code
)
SELECT s.label,
       s.version_code,
       s.runs,
       s.median_ms,
       s.min_ms,
       s.max_ms,
       s.median_cpu_ms,
       s.median_gets,
       s.median_phys,
       -- against the most recent SLOW batch, whatever its label
       (SELECT x.median_ms
          FROM summary x
         WHERE x.version_code = 'SLOW'
         ORDER BY x.first_run DESC
         FETCH FIRST 1 ROW ONLY) / NULLIF(s.median_ms, 0) AS speedup_vs_slow
  FROM summary s
 ORDER BY DECODE(s.version_code, 'SLOW', 0, 'V1', 1, 'V2', 2, 'V3', 3, 'V4', 4,
                 'V5', 5, 'V6', 6, 'V7', 7, 'V7P', 8, 9),
          s.first_run;
