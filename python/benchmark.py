#!/usr/bin/env python3
"""Times REPORT_TOP_CUSTOMERS_<VERSION> (warm-up + N runs, V$MYSTAT deltas) into results/*.csv and a chart.

Connection from ORACLE_USER / ORACLE_PASSWORD / ORACLE_DSN (or .env), thin mode.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
import time
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display needed (SSH, CI)
import matplotlib.pyplot as plt  # noqa: E402  (must come after matplotlib.use)
import oracledb  # noqa: E402
import pandas as pd  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RESULTS_DIR = PROJECT_ROOT / "results"
RUNS_CSV = RESULTS_DIR / "results_runs.csv"
SUMMARY_CSV = RESULTS_DIR / "results.csv"
CHART_PNG = RESULTS_DIR / "benchmark_elapsed.png"

# Fixed whitelist, so the command line can't be used to call arbitrary procedures.
VERSIONS = {
    "slow": "REPORT_TOP_CUSTOMERS_SLOW",
    "v1": "REPORT_TOP_CUSTOMERS_V1",
    "v2": "REPORT_TOP_CUSTOMERS_V2",
    "v3": "REPORT_TOP_CUSTOMERS_V3",
    "v4": "REPORT_TOP_CUSTOMERS_V4",
    "v5": "REPORT_TOP_CUSTOMERS_V5",
    "v6": "REPORT_TOP_CUSTOMERS_V6",
    "v7": "REPORT_TOP_CUSTOMERS_V7",
    "v7p": "REPORT_TOP_CUSTOMERS_V7P",
}
VERSION_ORDER = {code: position for position, code in enumerate(VERSIONS)}

STAT_COLUMNS = {
    "consistent gets": "consistent_gets",
    "db block gets": "db_block_gets",
    "physical reads": "physical_reads",
    "redo size": "redo_bytes",
    "CPU used by this session": "cpu_cs",  # hundredths of a second
}
STAT_SQL = """
    SELECT sn.name, ms.value
      FROM v$mystat ms
      JOIN v$statname sn
        ON sn.statistic# = ms.statistic#
     WHERE sn.name IN ('consistent gets', 'db block gets', 'physical reads',
                       'redo size', 'CPU used by this session')
"""

RUN_COLUMNS = [
    "batch_id", "label", "version", "run_no", "run_at", "report_month", "top_n",
    "elapsed_s", "cpu_s", "consistent_gets", "db_block_gets", "physical_reads",
    "redo_bytes", "rows_written",
]


def load_env_file(path: Path) -> None:
    """Read KEY=VALUE lines from .env; real environment variables win. Avoids a python-dotenv dependency."""
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key:
            os.environ.setdefault(key, value)


def connect() -> "oracledb.Connection":
    """Open a thin-mode connection using environment variables only."""
    required = ("ORACLE_USER", "ORACLE_PASSWORD", "ORACLE_DSN")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        sys.exit("Missing environment variables: " + ", ".join(missing)
                 + " (copy .env.example to .env and fill it in).")

    params = {}
    wallet_dir = os.environ.get("ORACLE_WALLET_DIR")
    if wallet_dir:
        # Autonomous Database with mTLS: thin mode reads tnsnames.ora and ewallet.pem from here.
        params["config_dir"] = wallet_dir
        params["wallet_location"] = wallet_dir
        params["wallet_password"] = os.environ.get("ORACLE_WALLET_PASSWORD") or None

    return oracledb.connect(
        user=os.environ["ORACLE_USER"],
        password=os.environ["ORACLE_PASSWORD"],
        dsn=os.environ["ORACLE_DSN"],
        **params,
    )


def installed_procedures(cursor) -> set:
    cursor.execute(
        "SELECT object_name FROM user_objects "
        "WHERE object_type = 'PROCEDURE' AND object_name LIKE 'REPORT_TOP_CUSTOMERS%'"
    )
    return {row[0] for row in cursor.fetchall()}


def resolve_report_month(cursor, month_arg):
    """Return the report month: --month YYYY-MM, else DATASET_INFO.REPORT_MONTH."""
    if month_arg:
        try:
            return dt.datetime.strptime(month_arg, "%Y-%m")
        except ValueError:
            sys.exit("--month must be in YYYY-MM format, e.g. 2026-11")
    cursor.execute("SELECT report_month FROM dataset_info WHERE dataset_id = 1")
    row = cursor.fetchone()
    if row is None:
        sys.exit("DATASET_INFO is empty: run 02_data_generation/run_all.sql first.")
    return row[0]


def read_session_stats(cursor):
    """Snapshot of this session's statistics, or None if V$MYSTAT is not readable."""
    try:
        cursor.execute(STAT_SQL)
    except oracledb.DatabaseError:
        return None
    return {STAT_COLUMNS[name]: value for name, value in cursor.fetchall()}


def run_once(cursor, procedure, version_code, month, top_n, with_stats) -> dict:
    before = read_session_stats(cursor) if with_stats else None
    start = time.perf_counter()
    cursor.callproc(procedure, [month, top_n])
    elapsed = time.perf_counter() - start
    after = read_session_stats(cursor) if with_stats else None

    cursor.execute(
        "SELECT COUNT(*) FROM report_top_customers "
        "WHERE generated_by = :code AND report_month = :month",
        {"code": version_code.upper(), "month": month},
    )
    rows_written = cursor.fetchone()[0]

    result = {"elapsed_s": elapsed, "rows_written": rows_written}
    for column in STAT_COLUMNS.values():
        if before and after and column in before and column in after:
            result[column] = after[column] - before[column]
        else:
            result[column] = None
    return result


def run_benchmark(args, versions) -> list:
    batch_id = dt.datetime.now().strftime("%Y%m%dT%H%M%S")
    records = []
    with connect() as connection:
        with connection.cursor() as cursor:
            installed = installed_procedures(cursor)
            month = resolve_report_month(cursor, args.month)
            with_stats = read_session_stats(cursor) is not None
            if not with_stats:
                print("WARNING: V$MYSTAT is not readable; only elapsed time will be recorded.")
            print(f"Report month {month:%Y-%m}, top {args.top_n}, label '{args.label}', "
                  f"{args.warmup} warm-up + {args.runs} measured runs per version.")

            for code in versions:
                procedure = VERSIONS[code]
                if procedure not in installed:
                    print(f"  {code:<5} skipped: {procedure} is not installed")
                    continue
                timings = []
                try:
                    for i in range(args.warmup + args.runs):
                        measured = run_once(cursor, procedure, code, month,
                                            args.top_n, with_stats)
                        if i < args.warmup:
                            continue  # warm-up, not recorded
                        timings.append(measured["elapsed_s"])
                        cpu_cs = measured["cpu_cs"]
                        records.append({
                            "batch_id": batch_id,
                            "label": args.label,
                            "version": code,
                            "run_no": i - args.warmup + 1,
                            "run_at": dt.datetime.now().isoformat(timespec="seconds"),
                            "report_month": month.strftime("%Y-%m"),
                            "top_n": args.top_n,
                            "elapsed_s": round(measured["elapsed_s"], 6),
                            "cpu_s": None if cpu_cs is None else cpu_cs / 100,
                            "consistent_gets": measured["consistent_gets"],
                            "db_block_gets": measured["db_block_gets"],
                            "physical_reads": measured["physical_reads"],
                            "redo_bytes": measured["redo_bytes"],
                            "rows_written": measured["rows_written"],
                        })
                except oracledb.DatabaseError as exc:
                    connection.rollback()
                    print(f"  {code:<5} FAILED: {exc}")
                    continue
                median = pd.Series(timings).median()
                print(f"  {code:<5} median {median:.4f} s over {len(timings)} runs")
    return records


def append_runs(records) -> None:
    if not records:
        print("No measured runs to save.")
        return
    frame = pd.DataFrame(records, columns=RUN_COLUMNS)
    frame.to_csv(RUNS_CSV, mode="a", header=not RUNS_CSV.exists(), index=False)
    print(f"Appended {len(frame)} runs to {RUNS_CSV.relative_to(PROJECT_ROOT)}")


def build_summary():
    """Median per (label, version), latest batch of each pair only."""
    if not RUNS_CSV.is_file():
        print(f"{RUNS_CSV.relative_to(PROJECT_ROOT)} does not exist yet - nothing to summarise.")
        return None
    runs = pd.read_csv(RUNS_CSV, dtype={"batch_id": str, "label": str, "version": str})
    if runs.empty:
        return None
    latest = runs.groupby(["label", "version"])["batch_id"].transform("max")
    runs = runs[runs["batch_id"] == latest]

    summary = runs.groupby(["label", "version"], as_index=False).agg(
        runs=("elapsed_s", "size"),
        median_elapsed_s=("elapsed_s", "median"),
        min_elapsed_s=("elapsed_s", "min"),
        max_elapsed_s=("elapsed_s", "max"),
        median_cpu_s=("cpu_s", "median"),
        median_consistent_gets=("consistent_gets", "median"),
        median_physical_reads=("physical_reads", "median"),
        first_run_at=("run_at", "min"),
    )
    summary["version_order"] = summary["version"].map(VERSION_ORDER)
    summary = (summary.sort_values(["version_order", "first_run_at"])
                      .drop(columns="version_order")
                      .reset_index(drop=True))
    summary.to_csv(SUMMARY_CSV, index=False)
    print(f"Wrote {SUMMARY_CSV.relative_to(PROJECT_ROOT)}")
    print(summary.to_string(index=False))
    return summary


def plot_summary(summary, linear: bool) -> None:
    if summary is None or summary.empty:
        return
    if summary["label"].nunique() == 1:
        labels = summary["version"].str.upper().tolist()
    else:
        labels = (summary["version"].str.upper() + "\n" + summary["label"]).tolist()
    values = summary["median_elapsed_s"].tolist()

    fig, ax = plt.subplots(figsize=(max(6.0, 1.0 * len(labels) + 2.0), 4.8))
    bars = ax.bar(labels, values, color="#3B6EA8")
    if not linear:
        # SLOW can be orders of magnitude slower; on a linear axis the fast bars disappear.
        ax.set_yscale("log")
    ax.set_ylabel("Median elapsed time (s)" + ("" if linear else ", log scale"))
    ax.set_title("REPORT_TOP_CUSTOMERS - median elapsed time per version (warm cache)")
    ax.grid(axis="y", linestyle=":", alpha=0.6)
    ax.set_axisbelow(True)
    for bar, value in zip(bars, values):
        ax.annotate(f"{value:.3g} s",
                    (bar.get_x() + bar.get_width() / 2, value),
                    xytext=(0, 3), textcoords="offset points",
                    ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(CHART_PNG, dpi=150)
    plt.close(fig)
    print(f"Wrote {CHART_PNG.relative_to(PROJECT_ROOT)}")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Benchmark the REPORT_TOP_CUSTOMERS_* procedures (python-oracledb, thin mode).")
    parser.add_argument("--versions", default=",".join(VERSIONS),
                        help="comma-separated codes: " + ",".join(VERSIONS)
                             + " (default: all; missing procedures are skipped)")
    parser.add_argument("--runs", type=int, default=5, help="measured runs per version (default 5)")
    parser.add_argument("--warmup", type=int, default=1, help="warm-up runs per version (default 1)")
    parser.add_argument("--top-n", type=int, default=100, help="p_top_n argument (default 100)")
    parser.add_argument("--month", help="report month YYYY-MM (default: DATASET_INFO.REPORT_MONTH)")
    parser.add_argument("--label", default="current_state",
                        help="schema state of this batch, e.g. after_step2 (default current_state)")
    parser.add_argument("--linear", action="store_true", help="linear y axis instead of log scale")
    parser.add_argument("--chart-only", action="store_true",
                        help="rebuild results.csv and the chart from results_runs.csv without connecting")
    args = parser.parse_args(argv)

    if args.runs < 1 or args.warmup < 0 or args.top_n < 1:
        parser.error("--runs must be >= 1, --warmup >= 0 and --top-n >= 1")
    if not args.label.strip():
        parser.error("--label must not be empty")
    return args


def main(argv=None) -> int:
    args = parse_args(argv)
    load_env_file(PROJECT_ROOT / ".env")
    RESULTS_DIR.mkdir(exist_ok=True)

    if not args.chart_only:
        versions = [v.strip().lower() for v in args.versions.split(",") if v.strip()]
        unknown = [v for v in versions if v not in VERSIONS]
        if unknown:
            sys.exit("Unknown version code(s): " + ", ".join(unknown))
        append_runs(run_benchmark(args, versions))
        print("Reminder: a timing only counts if 05_benchmark/01_verify_correctness.sql "
              "reports PASS for that version.")

    plot_summary(build_summary(), args.linear)
    return 0


if __name__ == "__main__":
    sys.exit(main())
