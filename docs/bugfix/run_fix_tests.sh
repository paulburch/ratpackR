#!/usr/bin/env bash
# Run the regression tests for one fix: all bug checks + smoke tests E1 and E2 (+E99 if asked),
# store results under Temp/fixruns/<tag>/ and compare them with Temp/fixruns/$PREV/ (default baseline).
# Usage: PREV=<previous tag> bash docs/bugfix/run_fix_tests.sh <tag> [E-values, default "1 2"]
set -u
prev=${PREV:-baseline}
tag=$1; shift; evals=${*:-"1 2"}
cd "$(dirname "$0")/../.."
source "$HOME/ratpack-env/activate.sh"
out=Temp/fixruns/$tag; mkdir -p "$out"
Rscript docs/bug_checks.R > "$out/checks.log" 2>&1
grep -E "^\[(CONFIRMED|NOT REPRODUCED|INFO)\]" "$out/checks.log" | cut -c1-24 > "$out/checks.txt"
for e in $evals; do
  s=$(date +%s)
  Rscript RunStreams/RunSmokeTest.R "$e" 1 > "$out/smoke_E$e.log" 2>&1; rc=$?
  echo "E$e exit=$rc time=$(( $(date +%s)-s ))s $(grep -o 'elapsed = [0-9.]* s' "$out/smoke_E$e.log")" >> "$out/summary.txt"
  rm -rf "$out/Results_E$e"; cp -r "Results/Smoke_Silver.warehou_E$e" "$out/Results_E$e" 2>/dev/null
  grep -E "^Error|Execution halted" "$out/smoke_E$e.log" | head -3 >> "$out/summary.txt"
done
if [ "$tag" != "$prev" ] && [ -d "Temp/fixruns/$prev" ]; then
  echo "--- checks that changed vs $prev:" >> "$out/summary.txt"
  diff "Temp/fixruns/$prev/checks.txt" "$out/checks.txt" | grep "^[<>]" >> "$out/summary.txt"
  for e in $evals; do
    [ -d "Temp/fixruns/$prev/Results_E$e" ] || continue
    echo "--- outputs E$e vs $prev:" >> "$out/summary.txt"
    Rscript docs/bugfix/compare_runs.R "Temp/fixruns/$prev/Results_E$e" "$out/Results_E$e" >> "$out/summary.txt" 2>&1
  done
fi
cat "$out/summary.txt"
