#!/bin/bash
set -uo pipefail

# =============================================================================
# Priority runner: re-run Q5 and Q9 static experiments with FIXED SQL files.
#
# Only NATION (and REGION for Q5) are TABLE; all other relations are STREAM.
# This matches the cost model's TPCH_DIM_TABLES = {"region", "nation"}.
#
# Runs only fast VOs (those that complete in <15s in dynamic mode) for both
# static_pred_on and static_pred_off configurations.
# =============================================================================

cd "$(dirname "$0")/.."

BATCH_SIZE="${BATCH_SIZE:-10000}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"

CPP_DIR="generated/cpp/tods26"
BIN_DIR="bin/tods26"
OUT_DIR="tods26-experiments/output"

# Count query directories
CPP_DIR_CNT="generated/cpp/tods26count"
BIN_DIR_CNT="bin/tods26count"

mkdir -p "$CPP_DIR" "$BIN_DIR" "$CPP_DIR_CNT" "$BIN_DIR_CNT" "$OUT_DIR"

TOTAL=0
DONE=0
FAILED=0
TIMED_OUT=0

app_header() {
  case "$1" in
    5)  echo "include/application/tpch/application_tpch_query5.hpp" ;;
    9)  echo "include/application/tpch/application_tpch_query9.hpp" ;;
  esac
}

run_experiment() {
  local Q=$1 vo_name=$2 mode=$3 pred=$4 is_count=$5
  local query_dir sql_dir cpp_dir bin_dir log_prefix

  if [[ "$is_count" == "1" ]]; then
    query_dir="tods26-experiments/queries/tpch_query_${Q}_count"
    sql_dir="${query_dir}/sql_files"
    cpp_dir="$CPP_DIR_CNT"
    bin_dir="$BIN_DIR_CNT"
    log_prefix="q${Q}count"
  else
    query_dir="tods26-experiments/queries/tpch_query_${Q}"
    sql_dir="${query_dir}/sql_files"
    cpp_dir="$CPP_DIR"
    bin_dir="$BIN_DIR"
    log_prefix="tpch_q${Q}"
  fi

  local sql_file="${sql_dir}/${vo_name}_sf1_${mode}_pred_${pred}.sql"
  local cpp_out="${cpp_dir}/${vo_name}_sf1_${mode}_pred_${pred}.hpp"
  local bin_out="${bin_dir}/${vo_name}_sf1_${mode}_pred_${pred}"
  local log_out="${OUT_DIR}/${log_prefix}_${vo_name}_sf1_${mode}_pred_${pred}.csv"

  TOTAL=$((TOTAL + 1))

  if [[ -s "$log_out" ]]; then
    echo "  [SKIP] Q${Q} ${vo_name} ${mode} pred:${pred} (count=${is_count})"
    DONE=$((DONE + 1))
    return
  fi

  echo -n "  [RUN]  Q${Q} ${vo_name} ${mode} pred:${pred} (count=${is_count}) ... "
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

echo "============================================================"
echo "Priority Static-Fix Runner — Q5 + Q9 (main + count)"
echo "============================================================"
echo "  Fix: SUPPLIER/PART/PARTSUPP now STREAM in static mode"
echo "  Only NATION (and REGION) remain TABLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# --- Q9 main: priority VOs (fast in dynamic mode) ---
echo "=== Q9 main query (static_pred_on + static_pred_off) ==="
Q9_PRIORITY_VOS=(
  tpch_q9_vo01_nation_supp_order_part
  tpch_q9_vo03_nation_order_supp_part
  tpch_q9_vo15_supp_root_order_nation_bushy
  tpch_q9_vo08_order_nation_supp_part
  tpch_q9_vo17_order_root_bushy
  tpch_q9_vo02_nation_supp_part_order
  tpch_q9_vo16_supp_root_part_nation_bushy
  tpch_q9_vo05_nation_order_part_supp
  tpch_q9_vo09_order_nation_part_supp
  tpch_q9_vo04_nation_part_order_supp
  tpch_q9_vo06_nation_part_supp_order
)
for vo in "${Q9_PRIORITY_VOS[@]}"; do
  for pred in on off; do
    run_experiment 9 "$vo" static "$pred" 0
  done
done

echo ""

# --- Q9 count: same priority VOs ---
echo "=== Q9 count query (static_pred_on + static_pred_off) ==="
Q9CNT_PRIORITY_VOS=(
  tpch_q9cnt_vo01_nation_supp_order_part
  tpch_q9cnt_vo03_nation_order_supp_part
  tpch_q9cnt_vo15_supp_root_order_nation_bushy
  tpch_q9cnt_vo08_order_nation_supp_part
  tpch_q9cnt_vo17_order_root_bushy
  tpch_q9cnt_vo02_nation_supp_part_order
  tpch_q9cnt_vo16_supp_root_part_nation_bushy
)
for vo in "${Q9CNT_PRIORITY_VOS[@]}"; do
  for pred in on off; do
    run_experiment 9 "$vo" static "$pred" 1
  done
done

echo ""

# --- Q5 main: priority VOs ---
echo "=== Q5 main query (static_pred_on + static_pred_off) ==="
Q5_PRIORITY_VOS=(
  tpch_q5_vo01_nation_supp_cust_order
  tpch_q5_vo03_nation_cust_supp_order
  tpch_q5_vo07_supp_nation_cust_order
  tpch_q5_vo06_nation_order_supp_cust
  tpch_q5_vo02_nation_supp_order_cust
  tpch_q5_vo13_cust_nation_supp_order
  tpch_q5_vo21_order_nation_supp_cust
  tpch_q5_vo08_supp_nation_order_cust
  tpch_q5_vo23_nation_root_order_child_bushy
  tpch_q5_vo05_nation_cust_order_supp
  tpch_q5_vo14_cust_nation_order_supp
)
for vo in "${Q5_PRIORITY_VOS[@]}"; do
  for pred in on off; do
    run_experiment 5 "$vo" static "$pred" 0
  done
done

echo ""
echo "============================================================"
echo "SUMMARY — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo "  Total:     $TOTAL"
echo "  Done:      $DONE"
echo "  Failed:    $FAILED"
echo "  Timed out: $TIMED_OUT"
echo "============================================================"
