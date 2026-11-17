# results/

Templates and generated output of the benchmark. **Every number in this folder must come from a real run.** Until then, every value is `TBD`.

| File | Filled by | Committed to git? |
|---|---|---|
| `comparison_table.md` | you, from `results.csv` or `05_benchmark/04_show_results.sql` | yes |
| `execution_plans.md` | you, from the files in `plans/` | yes |
| `correctness.md` | you, from `correctness_output.txt` | yes |
| `plans/*.txt` | `04_optimization_steps/*.sql` (EXPLAIN PLAN) and `05_benchmark/03_capture_plan.sql` (DISPLAY_CURSOR) | yes, if you want |
| `correctness_output.txt` | `05_benchmark/01_verify_correctness.sql` | yes, if you want |
| `results_runs.csv` | `python/benchmark.py` (one row per measured run) | no (`.gitignore`) |
| `results.csv` | `python/benchmark.py` (median per version) | no (`.gitignore`) |
| `benchmark_elapsed.png` | `python/benchmark.py` | no (`.gitignore`) |

To show the chart in the main README, copy your final `benchmark_elapsed.png` to `docs/img/benchmark_elapsed.png` and remove the HTML comment around the image link in `README.md`. That way only a chart you have checked gets published.
