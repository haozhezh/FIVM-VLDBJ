#!/bin/bash
set -uo pipefail
# NOTE: no -e; we handle errors per-experiment

# =============================================================================
# Resumable runner for all 51 CP-free variable orders across Q3, Q5, Q9, Q10.
#
# Key features:
#   - IDEMPOTENT: skips experiments whose output CSV already exists and is non-empty
#   - RESUMABLE:  just re-run the script to continue from where you left off
#   - PROGRESS:   writes progress to a log file and prints a summary on Ctrl-C
#   - TIMEOUT:    per-experiment timeout (default 10 min) prevents runaway VOs
#
# Usage:
#   cd FIVM/examples
#   nohup ./tods26-experiments/run_all_51vo.sh > tods26-experiments/output/run_all_51vo.log 2>&1 &
#
#   # Check progress from another terminal:
#   ./tods26-experiments/check_progress.sh
#
#   # Or just:
#   tail -f tods26-experiments/output/run_all_51vo.log
#
# Environment variables:
#   BATCH_SIZE    - rows per batch (default: 10000)
#   RUN_TIMEOUT   - per-experiment timeout in seconds (default: 600 = 10 min; 0 = no timeout)
#   QUERIES       - space-separated list of queries to run (default: "3 5 9 10")
#   SKIP_COMPILE  - if set to 1, skip compilation (use existing binaries)
#   DRY_RUN       - if set to 1, list experiments without running
# =============================================================================

cd "$(dirname "$0")/.."

BATCH_SIZE="${BATCH_SIZE:-10000}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"
QUERIES="${QUERIES:-3 5 9 10}"
SCALES="${SCALES:-sf1}"
SKIP_COMPILE="${SKIP_COMPILE:-0}"
DRY_RUN="${DRY_RUN:-0}"

CPP_DIR="generated/cpp/tods26"
BIN_DIR="bin/tods26"
OUT_DIR="tods26-experiments/output"
PROGRESS_FILE="${OUT_DIR}/progress_51vo.txt"

mkdir -p "$CPP_DIR" "$BIN_DIR" "$OUT_DIR"

# --- Counters ---
TOTAL=0
DONE_PREV=0
DONE_NOW=0
FAILED=0
TIMED_OUT=0
SKIPPED=0

# --- Signal handler: print summary on Ctrl-C ---
print_summary() {
  echo ""
  echo "============================================================"
  echo "PROGRESS SUMMARY ($(date '+%Y-%m-%d %H:%M:%S'))"
  echo "============================================================"
  echo "  Total experiments:    $TOTAL"
  echo "  Already done (skip):  $DONE_PREV"
  echo "  Completed this run:   $DONE_NOW"
  echo "  Failed:               $FAILED"
  echo "  Timed out:            $TIMED_OUT"
  echo "  Remaining:            $((TOTAL - DONE_PREV - DONE_NOW - FAILED - TIMED_OUT))"
  echo "============================================================"
}
trap print_summary EXIT

# --- Write progress file (machine-readable) ---
write_progress() {
  cat > "$PROGRESS_FILE" <<PEOF
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
total=$TOTAL
done_previous=$DONE_PREV
done_this_run=$DONE_NOW
failed=$FAILED
timed_out=$TIMED_OUT
remaining=$((TOTAL - DONE_PREV - DONE_NOW - FAILED - TIMED_OUT))
PEOF
}

# --- Map query number to application header ---
app_header() {
  case "$1" in
    3)  echo "include/application/tpch/application_tpch_query3.hpp" ;;
    5)  echo "include/application/tpch/application_tpch_query5.hpp" ;;
    9)  echo "include/application/tpch/application_tpch_query9.hpp" ;;
    10) echo "include/application/tpch/application_tpch_query10.hpp" ;;
  esac
}

# --- Build the experiment manifest ---
# Each line: query_num vo_name scale mode pred
MANIFEST=()

for Q in $QUERIES; do
  SQL_DIR="tods26-experiments/queries/tpch_query_${Q}/sql_files"
  VO_DIR="tods26-experiments/queries/tpch_query_${Q}/variable_orders"

  while IFS= read -r f; do
    vo_name=$(basename "$f" .txt)
    for scale in $SCALES; do
      for mode in static dynamic; do
        for pred in on off; do
          MANIFEST+=("${Q} ${vo_name} ${scale} ${mode} ${pred}")
        done
      done
    done
  done < <(find "$VO_DIR" -maxdepth 1 -type f -name "tpch_q${Q}_*.txt" 2>/dev/null | sort)
done

TOTAL=${#MANIFEST[@]}

if [[ "$TOTAL" -eq 0 ]]; then
  echo "ERROR: No experiments found. Run generate_assets.py first."
  exit 1
fi

# --- Count already-done experiments ---
for entry in "${MANIFEST[@]}"; do
  read -r Q vo_name scale mode pred <<< "$entry"
  log_out="${OUT_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.csv"
  if [[ -s "$log_out" ]]; then
    DONE_PREV=$((DONE_PREV + 1))
  fi
done

echo "============================================================"
echo "F-IVM Experiment Runner — All 51 CP-free Variable Orders"
echo "============================================================"
echo "  Queries:        $QUERIES"
echo "  Total combos:   $TOTAL"
echo "  Already done:   $DONE_PREV"
echo "  To run:         $((TOTAL - DONE_PREV))"
echo "  Batch size:     $BATCH_SIZE"
echo "  Timeout:        ${RUN_TIMEOUT}s per experiment"
echo "  Started:        $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN — listing experiments:"
  for entry in "${MANIFEST[@]}"; do
    read -r Q vo_name scale mode pred <<< "$entry"
    log_out="${OUT_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.csv"
    if [[ -s "$log_out" ]]; then
      echo "  [SKIP] Q${Q} ${vo_name} ${scale} ${mode} pred:${pred}"
    else
      echo "  [TODO] Q${Q} ${vo_name} ${scale} ${mode} pred:${pred}"
    fi
  done
  exit 0
fi

# --- Main loop ---
IDX=0
for entry in "${MANIFEST[@]}"; do
  read -r Q vo_name scale mode pred <<< "$entry"
  IDX=$((IDX + 1))

  sql_file="tods26-experiments/queries/tpch_query_${Q}/sql_files/${vo_name}_${scale}_${mode}_pred_${pred}.sql"
  cpp_out="${CPP_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.hpp"
  bin_out="${BIN_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}"
  log_out="${OUT_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.csv"

  # --- Skip if already done ---
  if [[ -s "$log_out" ]]; then
    SKIPPED=$((SKIPPED + 1))
    # Only print skip messages periodically to avoid log spam
    if [[ $((SKIPPED % 50)) -eq 1 ]] || [[ "$SKIPPED" -eq "$DONE_PREV" ]]; then
      echo "[${IDX}/${TOTAL}] Q${Q} ${vo_name} ${scale} ${mode} pred:${pred} — SKIP (${SKIPPED}/${DONE_PREV} skipped)"
    fi
    continue
  fi

  echo -n "[${IDX}/${TOTAL}] Q${Q} ${vo_name} ${scale} ${mode} pred:${pred} ... "
  START_TIME=$(date +%s)

  # --- Check SQL file exists ---
  if [[ ! -f "$sql_file" ]]; then
    echo "MISSING SQL"
    FAILED=$((FAILED + 1))
    write_progress
    continue
  fi

  # --- Phase 1: Compile SQL → C++ ---
  if [[ "$SKIP_COMPILE" != "1" ]]; then
    if ! ../scripts/generate-code.sh -l cpp -o "$cpp_out" "$sql_file" > /dev/null 2>&1; then
      echo "COMPILE_FAIL (codegen)"
      FAILED=$((FAILED + 1))
      write_progress
      continue
    fi

    if ! APP_INCLUDE="$(app_header "$Q")" EXTRA_ARGS="-I include" \
         ../scripts/build-generated-cpp.sh "$cpp_out" "$bin_out" > /dev/null 2>&1; then
      echo "COMPILE_FAIL (g++)"
      FAILED=$((FAILED + 1))
      write_progress
      continue
    fi
  fi

  # --- Phase 2: Run experiment ---
  if [[ ! -x "$bin_out" ]]; then
    echo "NO_BINARY"
    FAILED=$((FAILED + 1))
    write_progress
    continue
  fi

  rm -f "$log_out"

  local_timeout=()
  if [[ "$RUN_TIMEOUT" -gt 0 ]]; then
    local_timeout=(timeout --signal=KILL "$RUN_TIMEOUT")
  fi

  if "${local_timeout[@]}" env FIVM_BATCH_LOG="$log_out" \
      "$bin_out" --num_runs 1 --batch-size "$BATCH_SIZE" --no-output > /dev/null 2>&1; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    echo "DONE (${ELAPSED}s)"
    DONE_NOW=$((DONE_NOW + 1))
  else
    rc=$?
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    if [[ $rc -eq 137 ]]; then
      echo "TIMEOUT (${ELAPSED}s)"
      TIMED_OUT=$((TIMED_OUT + 1))
      # Remove partial output
      rm -f "$log_out"
    else
      echo "FAIL:${rc} (${ELAPSED}s)"
      FAILED=$((FAILED + 1))
      rm -f "$log_out"
    fi
  fi

  write_progress
done

echo ""
echo "ALL EXPERIMENTS PROCESSED."
