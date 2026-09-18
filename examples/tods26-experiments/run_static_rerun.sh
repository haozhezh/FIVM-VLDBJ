#!/bin/bash
set -uo pipefail

# =============================================================================
# Static-mode re-run: ALL Q5 and Q9 VOs with FIXED SQL files.
#
# Fix: Only NATION (and REGION for Q5) are TABLE in static mode.
#      SUPPLIER, PART, PARTSUPP are now STREAM (matching cost model).
#
# Ordering strategy:
#   - Interleaved Q9/Q5 so both queries get early results
#   - Fast VOs first, then medium, slow, timeout candidates last
#   - Runtime estimates from dynamic-mode measurements (new static ≈ dynamic)
#
# Resumable: skips experiments with existing non-empty output CSVs.
#            Stop anytime (Ctrl-C or kill), restart to continue.
#
# Only re-runs STATIC mode. Dynamic results are unaffected by the fix.
# =============================================================================

cd "$(dirname "$0")/.."

BATCH_SIZE="${BATCH_SIZE:-10000}"
RUN_TIMEOUT="${RUN_TIMEOUT:-600}"

CPP_DIR="generated/cpp/tods26"
BIN_DIR="bin/tods26"
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

run_static() {
  local Q=$1 vo_name=$2 pred=$3
  local query_dir="tods26-experiments/queries/tpch_query_${Q}"
  local sql_dir="${query_dir}/sql_files"
  local sql_file="${sql_dir}/${vo_name}_sf1_static_pred_${pred}.sql"
  local cpp_out="${CPP_DIR}/${vo_name}_sf1_static_pred_${pred}.hpp"
  local bin_out="${BIN_DIR}/${vo_name}_sf1_static_pred_${pred}"
  local log_out="${OUT_DIR}/${vo_name}_sf1_static_pred_${pred}.csv"

  TOTAL=$((TOTAL + 1))

  if [[ -s "$log_out" ]]; then
    echo "  [SKIP] Q${Q} ${vo_name} static pred:${pred}"
    SKIPPED=$((SKIPPED + 1))
    DONE=$((DONE + 1))
    return
  fi

  echo -n "  [RUN]  Q${Q} ${vo_name} static pred:${pred} ... "
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

# Helper: run a VO for both pred_on and pred_off
run_vo() {
  local Q=$1 vo=$2
  run_static "$Q" "$vo" on
  run_static "$Q" "$vo" off
}

echo "============================================================"
echo "Static-Mode Re-run — Q5 + Q9 (all VOs, corrected SQL)"
echo "============================================================"
echo "  Fix: Only NATION/REGION are TABLE; all others STREAM"
echo "  Timeout: ${RUN_TIMEOUT}s per experiment"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Resumable: existing results will be skipped"
echo "============================================================"
echo ""

# =========================================================================
# GROUP 1: Quick wins — 2 fast VOs per query (~20 min)
# Expected: first results for both Q5 and Q9 within 20 minutes
# =========================================================================
echo "--- Group 1: Fast VOs (both queries) ---"
run_vo 9 tpch_q9_vo01_nation_supp_order_part          # Q9 fastest (5s)
run_vo 5 tpch_q5_vo01_nation_supp_cust_order           # Q5 fastest (3s)
run_vo 9 tpch_q9_vo15_supp_root_order_nation_bushy     # Q9 fast bushy (5s)
run_vo 5 tpch_q5_vo03_nation_cust_supp_order           # Q5 fast (3s)
echo ""

# =========================================================================
# GROUP 2: Medium VOs — adds diversity (~30 min)
# =========================================================================
echo "--- Group 2: Medium VOs ---"
run_vo 9 tpch_q9_vo03_nation_order_supp_part           # Q9 (5s)
run_vo 5 tpch_q5_vo07_supp_nation_cust_order           # Q5 (3s)
run_vo 9 tpch_q9_vo08_order_nation_supp_part           # Q9 (6s)
run_vo 5 tpch_q5_vo06_nation_order_supp_cust           # Q5 (3s)
run_vo 9 tpch_q9_vo17_order_root_bushy                 # Q9 bushy (6s)
run_vo 5 tpch_q5_vo02_nation_supp_order_cust           # Q5 (3s)
echo ""

# =========================================================================
# GROUP 3: More diversity — medium-slow VOs (~40 min)
# =========================================================================
echo "--- Group 3: Medium-slow VOs ---"
run_vo 9 tpch_q9_vo02_nation_supp_part_order           # Q9 (9s)
run_vo 5 tpch_q5_vo13_cust_nation_supp_order           # Q5 (3s)
run_vo 9 tpch_q9_vo05_nation_order_part_supp           # Q9 (8s)
run_vo 5 tpch_q5_vo21_order_nation_supp_cust           # Q5 (3s)
run_vo 9 tpch_q9_vo09_order_nation_part_supp           # Q9 (9s)
run_vo 5 tpch_q5_vo08_supp_nation_order_cust           # Q5 (3s)
run_vo 9 tpch_q9_vo16_supp_root_part_nation_bushy      # Q9 bushy (9s)
run_vo 5 tpch_q5_vo23_nation_root_order_child_bushy    # Q5 bushy (3.4s)
echo ""

# =========================================================================
# GROUP 4: Slow VOs (~60 min)
# At this point: 8 Q9 + 8 Q5 = 16 VOs complete
# =========================================================================
echo "--- Group 4: Slow VOs ---"
run_vo 9 tpch_q9_vo04_nation_part_order_supp           # Q9 (11s)
run_vo 5 tpch_q5_vo05_nation_cust_order_supp           # Q5 (5s)
run_vo 9 tpch_q9_vo06_nation_part_supp_order           # Q9 (11s)
run_vo 5 tpch_q5_vo14_cust_nation_order_supp           # Q5 (5s)
run_vo 9 tpch_q9_vo14_part_nation_order_supp           # Q9 (25s)
run_vo 5 tpch_q5_vo26_order_root_nation_child_bushy    # Q5 bushy (10s)
run_vo 9 tpch_q9_vo13_part_nation_supp_order           # Q9 (25s)
echo ""

# =========================================================================
# GROUP 5: Remaining Q9 VOs — all should finish (~40 min)
# =========================================================================
echo "--- Group 5: Remaining Q9 VOs ---"
run_vo 9 tpch_q9_vo18_part_root_bushy                  # Q9 bushy (33s)
run_vo 9 tpch_q9_vo10_order_part_nation_supp           # Q9 (33s)
run_vo 9 tpch_q9_vo07_order_part_supp_nation           # Q9 (38s)
run_vo 9 tpch_q9_vo12_part_order_nation_supp           # Q9 (61s)
run_vo 9 tpch_q9_vo11_part_order_supp_nation           # Q9 slowest (67s)
echo ""

# =========================================================================
# GROUP 6: Q5 slow VOs (~80 min, ~6-7 min each)
# These all completed in dynamic mode but take 5-7 min each
# =========================================================================
echo "--- Group 6: Q5 slow VOs ---"
run_vo 5 tpch_q5_vo25_cust_root_supp_child_bushy      # Q5 bushy (326s)
run_vo 5 tpch_q5_vo24_supp_root_cust_child_bushy      # Q5 bushy (327s)
run_vo 5 tpch_q5_vo10_supp_order_nation_cust           # Q5 (374s)
run_vo 5 tpch_q5_vo18_order_supp_nation_cust           # Q5 (374s)
run_vo 5 tpch_q5_vo16_cust_supp_order_nation           # Q5 (401s)
run_vo 5 tpch_q5_vo11_supp_cust_order_nation           # Q5 (404s)
echo ""

# =========================================================================
# GROUP 7: Q5 timeout candidates — LAST (could take 10 min each)
# These all timed out at 600s in dynamic mode.
# =========================================================================
echo "--- Group 7: Q5 timeout candidates (may timeout at ${RUN_TIMEOUT}s) ---"
run_vo 5 tpch_q5_vo04_nation_order_cust_supp
run_vo 5 tpch_q5_vo09_supp_order_cust_nation
run_vo 5 tpch_q5_vo12_cust_order_supp_nation
run_vo 5 tpch_q5_vo15_cust_order_nation_supp
run_vo 5 tpch_q5_vo17_order_cust_supp_nation
run_vo 5 tpch_q5_vo19_order_cust_nation_supp
run_vo 5 tpch_q5_vo20_order_supp_cust_nation
run_vo 5 tpch_q5_vo22_order_nation_cust_supp
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
