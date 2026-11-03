# ratpackR regression tests

`tests/run_all.sh` checks that a change to the code, such as a merge of André's updates with
`git pull upstream main`, doesn't change model results unexpectedly. It runs small, fixed
cases and compares every output file with the reference copies in `tests/reference/`.

```bash
bash tests/run_all.sh
```

```bash
bash tests/run_all.sh --full
```

```bash
bash tests/run_all.sh --update
```

- With no option, the standard set runs in about 4–5 minutes.
- `--full` also runs the stochastic real run and the parallel driver, about 9 minutes.
- `--update` re-generates the references from the current code. Use it **after** an intended
  change has been checked, and commit the new references with the change.

The script exits with status 0 if everything matches and 1 if anything differs or a run fails.
Work files and logs go to `Temp/tests/`, which is git-ignored. It needs the Linux set-up
(`setup_linux.sh`); on Windows, run it from Git Bash with R on the PATH.

## What is run

| Case | What it covers | Time |
|---|---|---|
| `checks` | the 20 reproducible checks in `docs/bug_checks.R`; their CONFIRMED / NOT REPRODUCED status must not change | 30 s |
| `E1` | Silver.warehou (`Inputs Buffer/`), 1 simulation, 1 projection year, Tier 1 with SS, `Estimation.test 1` (no estimation) | 95 s |
| `E2` | as E1 with SS estimation (`Estimation.test 2`, deterministic data) | 100 s |
| `Tier4a_Pcod` | P.cod (`Inputs Other/`) with the assessment switched to `Tier_4a` (a copy is made at run time) | 35 s |
| `E99` (`--full`) | as E2 with stochastic data and the SS clean-up (`Estimation.test 99`) | 100 s |
| `E99_parallel_2sim` (`--full`) | 2 simulations through `DoRunParallel` on 2 workers ("R Inserts/Parallel/RatpackR.R") | 160 s |

The runs use `RunStreams/RunSmokeTest.R`. That script copies the inputs to `Temp/`, so the
committed inputs are never changed.

## Comparing results

Every `.Out` file in a reference folder is compared token by token with the new run
(`docs/bugfix/compare_runs.R`). Text must match exactly, and numbers within a relative
tolerance, 1e-8 by default:

```bash
RATPACK_TOL=1e-6 bash tests/run_all.sh
```

- **Excluded files:** `Debug_*.Out` and `LogFile_*.Out` are not compared. `HistBiol.Out` is
  only stored for E1, since the biology is the same in every case.
- **Other machines:** the references were made on Linux (Ubuntu 24.04, R 4.5.3, SS
  3.30.26.00). On another machine, Windows or a different SS build, expect differences in
  the SS-estimated cases (E2, E99) at about 1e-6. Use a looser tolerance there, or
  re-generate the references on that machine first with `--update`.
- **Code version:** the references reflect the code on the `bugfix-experiments` branch. On a
  branch without those fixes the tests will fail where the fixes change results (buffer,
  costs, discards by area, random streams). That is expected; generate references on that
  branch with `--update` if you want to use the tests there.

## When a test fails

1. Look at the reported file and line. `Temp/tests/<case>.compare` lists every file and
   `Temp/tests/<case>.log` has the run log.
2. Decide whether the change is intended, for example from a fix or an upstream change you
   want.
   - **If it is intended:** run with `--update` and commit the new references with an
     explanation.
   - **If not:** investigate before merging.
