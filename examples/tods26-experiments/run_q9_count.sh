#!/bin/bash
set -uo pipefail

# =============================================================================
# Q9 count query runner: all 18 VOs, static + dynamic, pred_on + pred_off.
# Resumable: skips experiments with existing non-empty output CSVs.
# Ordered fast to slow based on main query runtimes.
# =============================================================================

cd "$(dirname "$0")/.."

BATCH_SIZE="${BATCH_SIZE:-10000}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"

CPP_DIR="generated/cpp/tods26count"
BIN_DIR="bin/tods26count"
OUT_DIR="tods26-experiments/output"

mkdir -p "$CPP_DIR" "$BIN_DIR" "$OUT_DIR"

TOTAL=0
DONE=0
SKIPPED=0
FAILED=0
TIMED_OUT=0

run_count() {
  local vo_name=$1 mode=$2 pred=$3
  local query_dir="tods26-experiments/queries/tpch_query_9_count"
  local sql_dir="${query_dir}/sql_files"
  local sql_file="${sql_dir}/${vo_name}_sf1_${mode}_pred_${pred}.sql"
  local cpp_out="${CPP_DIR}/${vo_name}_sf1_${mode}_pred_${pred}.hpp"
  local bin_out="${BIN_DIR}/${vo_name}_sf1_${mode}_pred_${pred}"
  local log_out="${OUT_DIR}/q9count_${vo_name}_sf1_${mode}_pred_${pred}.csv"

  TOTAL=$((TOTAL + 1))

  if [[ -s "$log_out" ]]; then
    echo "  [SKIP] ${vo_name} ${mode} pred:${pred}"
    SKIPPED=$((SKIPPED + 1))
    DONE=$((DONE + 1))
    return
  fi

  echo -n "  [RUN]  ${vo_name} ${mode} pred:${pred} ... "
  START_TIME=$(date +%s)

  if [[ ! -f "$sql_file" ]]; then
    echo "MISSING SQL"
    FAILED=$((FAILED + 1))
    return
  fi

  if ! ../scripts/generate-code.sh -l cpp -o "$cpp_out" "$sql_file" > /dev/null 2>&1; then
    echo "COMPILE_FAIL (codegen)"
    FAILED=$((FAILED + 1))
    return
  fi

  if ! APP_INCLUDE="include/application/tpch/application_tpch_query9.hpp" EXTRA_ARGS="-I include" \
       ../scripts/build-generated-cpp.sh "$cpp_out" "$bin_out" > /dev/null 2>&1; then
    echo "COMPILE_FAIL (g++)"
    FAILED=$((FAILED + 1))
    return
  fi

  rm -f "$log_out"
  local local_timeout=()
  if [[ "$RUN_TIMEOUT" -gt 0 ]]; then
    local_timeout=(timeout --signal=KILL "$RUN_TIMEOUT")
  fi

  if "${local_timeout[@]}" env FIVM_BATCH_LOG="$log_out" \
      "$bin_out" --num_runs 1 --batch-size "$BATCH_SIZE" --no-output > /dev/null 2>&1; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    echo "DONE (${ELAPSED}s)"
    DONE=$((DONE + 1))
  else
    rc=$?
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    if [[ $rc -eq 137 ]]; then
      echo "TIMEOUT (${ELAPSED}s)"
      TIMED_OUT=$((TIMED_OUT + 1))
      rm -f "$log_out"
    else
      echo "FAIL:${rc} (${ELAPSED}s)"
      FAILED=$((FAILED + 1))
      rm -f "$log_out"
    fi
  fi
}

run_vo() {
  local vo=$1
  for mode in static dynamic; do
    for pred in on off; do
      run_count "$vo" "$mode" "$pred"
    done
  done
}

echo "============================================================"
echo "Q9 Count Query Runner — 18 VOs × 2 modes × 2 preds = 72"
echo "============================================================"
echo "  Timeout: ${RUN_TIMEOUT}s per experiment"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Resumable: existing results will be skipped"
echo "============================================================"
echo ""

echo "--- Fast VOs ---"
run_vo tpch_q9cnt_vo01_nation_supp_order_part
run_vo tpch_q9cnt_vo03_nation_order_supp_part
run_vo tpch_q9cnt_vo15_supp_root_order_nation_bushy
run_vo tpch_q9cnt_vo08_order_nation_supp_part
run_vo tpch_q9cnt_vo17_order_root_bushy
echo ""

echo "--- Medium VOs ---"
run_vo tpch_q9cnt_vo05_nation_order_part_supp
run_vo tpch_q9cnt_vo02_nation_supp_part_order
run_vo tpch_q9cnt_vo09_order_nation_part_supp
run_vo tpch_q9cnt_vo16_supp_root_part_nation_bushy
run_vo tpch_q9cnt_vo04_nation_part_order_supp
run_vo tpch_q9cnt_vo06_nation_part_supp_order
echo ""

echo "--- Slow VOs ---"
run_vo tpch_q9cnt_vo14_part_nation_order_supp
run_vo tpch_q9cnt_vo13_part_nation_supp_order
run_vo tpch_q9cnt_vo18_part_root_bushy
run_vo tpch_q9cnt_vo10_order_part_nation_supp
run_vo tpch_q9cnt_vo07_order_part_supp_nation
run_vo tpch_q9cnt_vo12_part_order_nation_supp
run_vo tpch_q9cnt_vo11_part_order_supp_nation
echo ""

echo "============================================================"
echo "SUMMARY — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo "  Total:     $TOTAL"
echo "  Done:      $DONE  (skipped: $SKIPPED)"
echo "  Failed:    $FAILED"
echo "  Timed out: $TIMED_OUT"
echo "============================================================"
