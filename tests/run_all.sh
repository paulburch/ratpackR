#!/usr/bin/env bash
# ratpackR regression tests (Paul's addition; see tests/README.md).
#
#   bash tests/run_all.sh            # standard set, about 5 minutes
#   bash tests/run_all.sh --full     # + stochastic E99 run and a 2-sim parallel run (about 9 minutes)
#   bash tests/run_all.sh --update   # re-generate tests/reference/ from the current code (after an intended change)
#   RATPACK_TOL=1e-6 bash tests/run_all.sh   # relative tolerance for numeric comparisons (default 1e-8)
#
# Exit status 0 = everything matches the references; 1 = something differs or a run failed.
# Work files go to Temp/tests/ (git-ignored). Needs the Linux set-up (setup_linux.sh).
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd); REF=tests/reference; OUT=Temp/tests; TOL=${RATPACK_TOL:-1e-8}
FULL=0; UPDATE=0
for a in "$@"; do case $a in --full) FULL=1;; --update) UPDATE=1;; *) echo "unknown option $a"; exit 2;; esac; done
[ -f "$HOME/ratpack-env/activate.sh" ] && source "$HOME/ratpack-env/activate.sh"
rm -rf "$OUT"; mkdir -p "$OUT"
FAIL=0; SUMMARY=()
note() { SUMMARY+=("$1"); echo "$1"; }

# --- 1. reproducible bug checks -------------------------------------------------------
echo ">> bug checks"
Rscript docs/bug_checks.R > "$OUT/checks.log" 2>&1
grep -E "^\[(CONFIRMED|NOT REPRODUCED|INFO)\]" "$OUT/checks.log" | cut -c1-24 > "$OUT/checks.txt"
if [ $UPDATE = 1 ]; then mkdir -p $REF; cp "$OUT/checks.txt" $REF/checks.txt
elif diff -q $REF/checks.txt "$OUT/checks.txt" > /dev/null; then note "PASS checks ($(wc -l < "$OUT/checks.txt") lines identical)"
else note "FAIL checks:"; diff $REF/checks.txt "$OUT/checks.txt"; FAIL=1; fi

# Tier 4a test input: P.cod from "Inputs Other/" with the assessment switched to Tier_4a
mkdir -p "$OUT/inputs/Tier4a_Pcod"; cp "Inputs Other/"P.cod.* "Inputs Other/General_P.cod.OM" "$OUT/inputs/Tier4a_Pcod/"
sed -i 's/^#Ass_Basic:Type Tier_1a/#Ass_Basic:Type Tier_4a/' "$OUT/inputs/Tier4a_Pcod/P.cod.EM"

# --- 2. model runs ---------------------------------------------------------------------
# name | RunSmokeTest.R arguments | results folder
CASES=("E1|1 1 Inputs\ Buffer/ Silver.warehou 1 0|Smoke_Silver.warehou_E1"
       "E2|2 1 Inputs\ Buffer/ Silver.warehou 1 0|Smoke_Silver.warehou_E2"
       "Tier4a_Pcod|1 1 Temp/tests/inputs/Tier4a_Pcod/ P.cod 1 0|Smoke_P.cod_E1")
if [ $FULL = 1 ]; then
  CASES+=("E99|99 1 Inputs\ Buffer/ Silver.warehou 1 0|Smoke_Silver.warehou_E99"
          "E99_parallel_2sim|99 1 Inputs\ Buffer/ Silver.warehou 2 2|Smoke_Silver.warehou_E99_par")
fi
for c in "${CASES[@]}"; do
  IFS='|' read -r name argstr res <<< "$c"
  eval "set -- $argstr"
  echo ">> run $name"
  s=$(date +%s)
  Rscript RunStreams/RunSmokeTest.R "$@" > "$OUT/$name.log" 2>&1; rc=$?
  t=$(( $(date +%s) - s ))
  if [ $rc != 0 ]; then note "FAIL $name: run stopped (exit $rc, ${t}s): $(grep -m1 '^Error' "$OUT/$name.log")"; FAIL=1; continue; fi
  mkdir -p "$OUT/$name"; cp Results/$res/*.Out "$OUT/$name/"
  # names in the reference do not depend on the run folder
  for f in "$OUT/$name"/*.Out; do mv "$f" "$OUT/$name/$(basename "$f" | sed -E 's/_Smoke_.*_00\.Out$/.Out/')"; done
  rm -f "$OUT/$name"/Debug.Out "$OUT/$name"/LogFile.Out
  [ "$name" != E1 ] && rm -f "$OUT/$name"/HistBiol.Out
  if [ $UPDATE = 1 ]; then rm -rf "$REF/$name"; cp -r "$OUT/$name" "$REF/$name"; note "updated reference $name (${t}s)"; continue; fi
  if [ ! -d "$REF/$name" ]; then note "FAIL $name: no reference (run with --update)"; FAIL=1; continue; fi
  if Rscript docs/bugfix/compare_runs.R "$REF/$name" "$OUT/$name" "$TOL" > "$OUT/$name.compare" 2>&1; then
    note "PASS $name (${t}s; $(grep -c identical "$OUT/$name.compare") files identical)"
  else
    note "FAIL $name (${t}s):"; grep -v identical "$OUT/$name.compare"; FAIL=1
  fi
done

echo; echo "===== summary ====="; printf '%s\n' "${SUMMARY[@]}"
[ $UPDATE = 1 ] && { echo "references written to $REF/"; exit 0; }
[ $FAIL = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED (details above; logs in $OUT/)"
exit $FAIL
