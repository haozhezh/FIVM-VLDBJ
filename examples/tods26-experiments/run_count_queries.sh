#!/bin/bash
set -uo pipefail

# =============================================================================
# Count query runner: Q9 count (all 18 VOs) then Q5 count (all 26 VOs)
# Both static and dynamic modes, pred_on and pred_off.
#
# Resumable: skips experiments with existing non-empty output CSVs.
# Q9 count first (all should finish), Q5 count after (some may timeout).
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

app_header() {
  case "$1" in
    5)  echo "include/application/tpch/application_tpch_query5.hpp" ;;
    9)  echo "include/application/tpch/application_tpch_query9.hpp" ;;
  esac
}

run_count() {
  local Q=$1 vo_name=$2 mode=$3 pred=$4
  local query_dir="tods26-experiments/queries/tpch_query_${Q}_count"
  local sql_dir="${query_dir}/sql_files"
  local sql_file="${sql_dir}/${vo_name}_sf1_${mode}_pred_${pred}.sql"
  local cpp_out="${CPP_DIR}/${vo_name}_sf1_${mode}_pred_${pred}.hpp"
  local bin_out="${BIN_DIR}/${vo_name}_sf1_${mode}_pred_${pred}"
  local log_out="${OUT_DIR}/q${Q}count_${vo_name}_sf1_${mode}_pred_${pred}.csv"

  TOTAL=$((TOTAL + 1))

  if [[ -s "$log_out" ]]; then
    echo "  [SKIP] Q${Q}cnt ${vo_name} ${mode} pred:${pred}"
    SKIPPED=$((SKIPPED + 1))
    DONE=$((DONE + 1))
    return
  fi

  echo -n "  [RUN]  Q${Q}cnt ${vo_name} ${mode} pred:${pred} ... "
  START_TIME=$(date +%s)

  if [[ ! -f "$sql_file" ]]; then
    echo "MISSING SQL"
    FAILED=$((FAILED + 1))
    return
  fi

  # Compile
  if ! ../scripts/generate-code.sh -l cpp -o "$cpp_out" "$sql_file" > /dev/null 2>&1; then
    echo "COMPILE_FAIL (codegen)"
    FAILED=$((FAILED + 1))
    return
  fi

  if ! APP_INCLUDE="$(app_header "$Q")" EXTRA_ARGS="-I include" \
       ../scripts/build-generated-cpp.sh "$cpp_out" "$bin_out" > /dev/null 2>&1; then
    echo "COMPILE_FAIL (g++)"
    FAILED=$((FAILED + 1))
    return
  fi

  # Run
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

# Helper: run a VO for both modes and both pred settings
run_vo_full() {
  local Q=$1 vo=$2
  for mode in static dynamic; do
    for pred in on off; do
      run_count "$Q" "$vo" "$mode" "$pred"
    done
  done
}

echo "============================================================"
echo "Count Query Runner — Q9 count + Q5 count (static + dynamic)"
echo "============================================================"
echo "  Timeout: ${RUN_TIMEOUT}s per experiment"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Resumable: existing results will be skipped"
echo "============================================================"
echo ""

# =========================================================================
# Q9 COUNT — all 18 VOs, ordered fast to slow (from main query runtimes)
# =========================================================================
echo "=== Q9 count queries (18 VOs × 2 modes × 2 preds = 72 experiments) ==="
echo ""

echo "--- Q9 count: fast VOs ---"
run_vo_full 9 tpch_q9cnt_vo01_nation_supp_order_part
run_vo_full 9 tpch_q9cnt_vo03_nation_order_supp_part
run_vo_full 9 tpch_q9cnt_vo15_supp_root_order_nation_bushy
run_vo_full 9 tpch_q9cnt_vo08_order_nation_supp_part
run_vo_full 9 tpch_q9cnt_vo17_order_root_bushy
echo ""

echo "--- Q9 count: medium VOs ---"
run_vo_full 9 tpch_q9cnt_vo05_nation_order_part_supp
run_vo_full 9 tpch_q9cnt_vo02_nation_supp_part_order
run_vo_full 9 tpch_q9cnt_vo09_order_nation_part_supp
run_vo_full 9 tpch_q9cnt_vo16_supp_root_part_nation_bushy
run_vo_full 9 tpch_q9cnt_vo04_nation_part_order_supp
run_vo_full 9 tpch_q9cnt_vo06_nation_part_supp_order
echo ""

echo "--- Q9 count: slow VOs ---"
run_vo_full 9 tpch_q9cnt_vo14_part_nation_order_supp
run_vo_full 9 tpch_q9cnt_vo13_part_nation_supp_order
run_vo_full 9 tpch_q9cnt_vo18_part_root_bushy
run_vo_full 9 tpch_q9cnt_vo10_order_part_nation_supp
run_vo_full 9 tpch_q9cnt_vo07_order_part_supp_nation
run_vo_full 9 tpch_q9cnt_vo12_part_order_nation_supp
run_vo_full 9 tpch_q9cnt_vo11_part_order_supp_nation
echo ""

# =========================================================================
# Q5 COUNT — all 26 VOs, ordered fast to slow, timeouts last
# =========================================================================
echo "=== Q5 count queries (26 VOs × 2 modes × 2 preds = 208 experiments) ==="
echo ""

echo "--- Q5 count: fast VOs ---"
run_vo_full 5 tpch_q5cnt_vo01_nation_supp_cust_order
run_vo_full 5 tpch_q5cnt_vo03_nation_cust_supp_order
run_vo_full 5 tpch_q5cnt_vo07_supp_nation_cust_order
run_vo_full 5 tpch_q5cnt_vo06_nation_order_supp_cust
run_vo_full 5 tpch_q5cnt_vo02_nation_supp_order_cust
run_vo_full 5 tpch_q5cnt_vo13_cust_nation_supp_order
run_vo_full 5 tpch_q5cnt_vo21_order_nation_supp_cust
run_vo_full 5 tpch_q5cnt_vo08_supp_nation_order_cust
run_vo_full 5 tpch_q5cnt_vo23_nation_root_order_child_bushy
echo ""

echo "--- Q5 count: medium VOs ---"
run_vo_full 5 tpch_q5cnt_vo05_nation_cust_order_supp
run_vo_full 5 tpch_q5cnt_vo14_cust_nation_order_supp
run_vo_full 5 tpch_q5cnt_vo26_order_root_nation_child_bushy
echo ""

echo "--- Q5 count: slow VOs ---"
run_vo_full 5 tpch_q5cnt_vo25_cust_root_supp_child_bushy
run_vo_full 5 tpch_q5cnt_vo24_supp_root_cust_child_bushy
run_vo_full 5 tpch_q5cnt_vo10_supp_order_nation_cust
run_vo_full 5 tpch_q5cnt_vo18_order_supp_nation_cust
run_vo_full 5 tpch_q5cnt_vo16_cust_supp_order_nation
run_vo_full 5 tpch_q5cnt_vo11_supp_cust_order_nation
echo ""

echo "--- Q5 count: timeout candidates ---"
run_vo_full 5 tpch_q5cnt_vo09_supp_order_cust_nation
run_vo_full 5 tpch_q5cnt_vo20_order_supp_cust_nation
run_vo_full 5 tpch_q5cnt_vo04_nation_order_cust_supp
run_vo_full 5 tpch_q5cnt_vo12_cust_order_supp_nation
run_vo_full 5 tpch_q5cnt_vo15_cust_order_nation_supp
run_vo_full 5 tpch_q5cnt_vo17_order_cust_supp_nation
run_vo_full 5 tpch_q5cnt_vo19_order_cust_nation_supp
run_vo_full 5 tpch_q5cnt_vo22_order_nation_cust_supp
echo ""

# =========================================================================
echo "============================================================"
echo "SUMMARY — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo "  Total:     $TOTAL"
echo "  Done:      $DONE  (skipped: $SKIPPED)"
echo "  Failed:    $FAILED"
echo "  Timed out: $TIMED_OUT"
echo "============================================================"
