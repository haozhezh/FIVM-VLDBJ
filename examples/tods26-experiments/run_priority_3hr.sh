#!/bin/bash
set -uo pipefail

# =============================================================================
# Priority runner: Get presentable results for Q5 + Q9 within ~3 hours.
#
# Strategy:
#   Phase 1: Q9 all 18 VOs (all expected to finish, ~90 min)
#   Phase 2: Q5 predicted-fast VOs (bushy + cust/order→nation chains, ~20 min)
#   Phase 3: Q5 remaining with short timeout (skip known-slow, ~60 min)
#
# Usage:
#   cd FIVM/examples
#   nohup ./tods26-experiments/run_priority_3hr.sh > tods26-experiments/output/run_priority.log 2>&1 &
# =============================================================================

cd "$(dirname "$0")/.."

BATCH_SIZE="${BATCH_SIZE:-10000}"
SKIP_COMPILE="${SKIP_COMPILE:-0}"

CPP_DIR="generated/cpp/tods26"
BIN_DIR="bin/tods26"
OUT_DIR="tods26-experiments/output"

mkdir -p "$CPP_DIR" "$BIN_DIR" "$OUT_DIR"

TOTAL=0
DONE_PREV=0
DONE_NOW=0
FAILED=0
TIMED_OUT=0

print_summary() {
  echo ""
  echo "============================================================"
  echo "PRIORITY RUN SUMMARY ($(date '+%Y-%m-%d %H:%M:%S'))"
  echo "============================================================"
  echo "  Completed this run:   $DONE_NOW"
  echo "  Timed out:            $TIMED_OUT"
  echo "  Failed:               $FAILED"
  echo "  Skipped (existing):   $DONE_PREV"
  echo "============================================================"
}
trap print_summary EXIT

app_header() {
  case "$1" in
    3)  echo "include/application/tpch/application_tpch_query3.hpp" ;;
    5)  echo "include/application/tpch/application_tpch_query5.hpp" ;;
    9)  echo "include/application/tpch/application_tpch_query9.hpp" ;;
    10) echo "include/application/tpch/application_tpch_query10.hpp" ;;
  esac
}

run_one() {
  local Q="$1" vo_name="$2" scale="$3" mode="$4" pred="$5" timeout="$6"

  local sql_file="tods26-experiments/queries/tpch_query_${Q}/sql_files/${vo_name}_${scale}_${mode}_pred_${pred}.sql"
  local cpp_out="${CPP_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.hpp"
  local bin_out="${BIN_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}"
  local log_out="${OUT_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.csv"

  # Skip if already done
  if [ -s "$log_out" ]; then
    DONE_PREV=$((DONE_PREV + 1))
    return 0
  fi

  TOTAL=$((TOTAL + 1))
  echo -n "  [${TOTAL}] Q${Q} ${vo_name} ${scale} ${mode} pred:${pred} (${timeout}s) ... "
  local START_TIME=$(date +%s)

  if [ ! -f "$sql_file" ]; then
    echo "MISSING SQL"
    FAILED=$((FAILED + 1))
    return 1
  fi

  # Compile
  if [ "$SKIP_COMPILE" != "1" ]; then
    if ! ../scripts/generate-code.sh -l cpp -o "$cpp_out" "$sql_file" > /dev/null 2>&1; then
      echo "COMPILE_FAIL (codegen)"
      FAILED=$((FAILED + 1))
      return 1
    fi
    if ! APP_INCLUDE="$(app_header "$Q")" EXTRA_ARGS="-I include" \
         ../scripts/build-generated-cpp.sh "$cpp_out" "$bin_out" > /dev/null 2>&1; then
      echo "COMPILE_FAIL (g++)"
      FAILED=$((FAILED + 1))
      return 1
    fi
  fi

  if [ ! -x "$bin_out" ]; then
    echo "NO_BINARY"
    FAILED=$((FAILED + 1))
    return 1
  fi

  rm -f "$log_out"

  local timeout_cmd=()
  if [ "$timeout" -gt 0 ]; then
    timeout_cmd=(timeout --signal=KILL "$timeout")
  fi

  if "${timeout_cmd[@]}" env FIVM_BATCH_LOG="$log_out" \
      "$bin_out" --num_runs 1 --batch-size "$BATCH_SIZE" --no-output > /dev/null 2>&1; then
    local END_TIME=$(date +%s)
    echo "DONE ($((END_TIME - START_TIME))s)"
    DONE_NOW=$((DONE_NOW + 1))
    return 0
  else
    local rc=$?
    local END_TIME=$(date +%s)
    if [ $rc -eq 137 ]; then
      echo "TIMEOUT ($((END_TIME - START_TIME))s)"
      TIMED_OUT=$((TIMED_OUT + 1))
      rm -f "$log_out"
    else
      echo "FAIL:${rc} ($((END_TIME - START_TIME))s)"
      FAILED=$((FAILED + 1))
      rm -f "$log_out"
    fi
    return 1
  fi
}

run_vo() {
  local Q="$1" vo_name="$2" timeout="$3"
  for mode in static dynamic; do
    for pred in on off; do
      run_one "$Q" "$vo_name" "sf1" "$mode" "$pred" "$timeout"
    done
  done
}

echo "============================================================"
echo "Priority Runner — 3-hour plan for presentation"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# =====================================================
# PHASE 1: Q9 — all 18 VOs (10-min timeout, ~90 min)
# =====================================================
echo ""
echo ">>> PHASE 1: Q9 all 18 VOs (timeout: 600s)"
echo "------------------------------------------------------------"

Q9_VO_DIR="tods26-experiments/queries/tpch_query_9/variable_orders"
for f in $(find "$Q9_VO_DIR" -maxdepth 1 -name "tpch_q9_*.txt" -type f | sort); do
  vo_name=$(basename "$f" .txt)
  run_vo 9 "$vo_name" 600
done

echo ""
echo ">>> Phase 1 done: $DONE_NOW completed, $TIMED_OUT timed out"

# =====================================================
# PHASE 2: Q5 predicted-fast VOs (5-min timeout, ~20 min)
# =====================================================
echo ""
echo ">>> PHASE 2: Q5 fast VOs (timeout: 300s)"
echo "------------------------------------------------------------"

# Bushy VOs (confirmed fast from old data: 5-26s)
Q5_FAST_VOS=(
  "tpch_q5_vo23_nation_root_order_child_bushy"    # old data: 6s
  "tpch_q5_vo26_order_root_nation_child_bushy"     # old data: 5s
  "tpch_q5_vo24_supp_root_cust_child_bushy"        # old data: ~moderate
  "tpch_q5_vo25_cust_root_supp_child_bushy"        # old data: 26s
  # cust→nation chains (nation constrains early = fast)
  "tpch_q5_vo13_cust_nation_supp_order"
  "tpch_q5_vo14_cust_nation_order_supp"
  # order→nation chains (nation constrains early = fast)
  "tpch_q5_vo21_order_nation_supp_cust"
  "tpch_q5_vo22_order_nation_cust_supp"
)

for vo_name in "${Q5_FAST_VOS[@]}"; do
  run_vo 5 "$vo_name" 300
done

echo ""
echo ">>> Phase 2 done: $DONE_NOW completed total, $TIMED_OUT timed out total"

# =====================================================
# PHASE 3: Q5 remaining with shorter timeout (3-min)
# =====================================================
echo ""
echo ">>> PHASE 3: Q5 remaining VOs (timeout: 180s, skip known-slow)"
echo "------------------------------------------------------------"

# These are custkey-root and orderkey-root chains that might be slow.
# Use 3-min timeout — if they can't finish in 3 min, they're not worth it.
Q5_MAYBE_VOS=(
  "tpch_q5_vo16_cust_supp_order_nation"
  "tpch_q5_vo15_cust_order_nation_supp"
  "tpch_q5_vo17_order_cust_supp_nation"
  "tpch_q5_vo18_order_supp_nation_cust"
  "tpch_q5_vo19_order_cust_nation_supp"
  "tpch_q5_vo20_order_supp_cust_nation"
)

for vo_name in "${Q5_MAYBE_VOS[@]}"; do
  run_vo 5 "$vo_name" 180
done

echo ""
echo ">>> Phase 3 done: $DONE_NOW completed total, $TIMED_OUT timed out total"

# =====================================================
# PHASE 4: Q5 fill gaps — retry partial VOs (vo09-vo12)
# =====================================================
echo ""
echo ">>> PHASE 4: Q5 retry partial VOs (timeout: 180s)"
echo "------------------------------------------------------------"

Q5_RETRY_VOS=(
  "tpch_q5_vo04_nation_order_cust_supp"
  "tpch_q5_vo09_supp_order_cust_nation"
  "tpch_q5_vo10_supp_order_nation_cust"
  "tpch_q5_vo11_supp_cust_order_nation"
  "tpch_q5_vo12_cust_order_supp_nation"
)

for vo_name in "${Q5_RETRY_VOS[@]}"; do
  run_vo 5 "$vo_name" 180
done

echo ""
echo "ALL PHASES COMPLETE."
echo ""
