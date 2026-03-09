#!/bin/bash
# =============================================================================
# Check progress of the 67-VO experiment run.
# Run from any terminal while run_all_51vo.sh is running.
#
# Usage:
#   ./tods26-experiments/check_progress.sh          # summary
#   ./tods26-experiments/check_progress.sh --detail  # per-query breakdown
# =============================================================================

cd "$(dirname "$0")/.."

OUT_DIR="tods26-experiments/output"
PROGRESS_FILE="${OUT_DIR}/progress_51vo.txt"

echo "============================================================"
echo "Experiment Progress — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# --- Show progress file if it exists ---
if [[ -f "$PROGRESS_FILE" ]]; then
  echo ""
  echo "Runner status (from progress file):"
  while IFS='=' read -r key val; do
    printf "  %-20s %s\n" "$key" "$val"
  done < "$PROGRESS_FILE"
fi

# --- Count actual output files ---
echo ""
echo "Output files on disk:"

GRAND_TOTAL=0
GRAND_DONE=0
GRAND_TIMEOUT=0

for Q in 3 5 9 10; do
  VO_DIR="tods26-experiments/queries/tpch_query_${Q}/variable_orders"
  n_vos=$(find "$VO_DIR" -maxdepth 1 -type f -name "tpch_q${Q}_*.txt" 2>/dev/null | wc -l)
  expected=$((n_vos * 8))  # 2 scales × 2 modes × 2 preds

  done_count=0
  empty_count=0
  while IFS= read -r f; do
    vo_name=$(basename "$f" .txt)
    for scale in sf0p1 sf1; do
      for mode in static dynamic; do
        for pred in on off; do
          csv="${OUT_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.csv"
          if [[ -s "$csv" ]]; then
            done_count=$((done_count + 1))
          elif [[ -f "$csv" ]]; then
            empty_count=$((empty_count + 1))
          fi
        done
      done
    done
  done < <(find "$VO_DIR" -maxdepth 1 -type f -name "tpch_q${Q}_*.txt" 2>/dev/null | sort)

  pct=0
  if [[ "$expected" -gt 0 ]]; then
    pct=$((done_count * 100 / expected))
  fi
  printf "  Q%-2s: %3d / %3d done (%3d%%)  [%d VOs]" "$Q" "$done_count" "$expected" "$pct" "$n_vos"
  if [[ "$empty_count" -gt 0 ]]; then
    printf "  (%d empty/partial)" "$empty_count"
  fi
  echo ""

  GRAND_TOTAL=$((GRAND_TOTAL + expected))
  GRAND_DONE=$((GRAND_DONE + done_count))
done

echo "  ──────────────────────────────────────"
pct=0
if [[ "$GRAND_TOTAL" -gt 0 ]]; then
  pct=$((GRAND_DONE * 100 / GRAND_TOTAL))
fi
printf "  ALL: %3d / %3d done (%3d%%)\n" "$GRAND_DONE" "$GRAND_TOTAL" "$pct"

# --- Detail mode: show per-VO status ---
if [[ "${1:-}" == "--detail" ]]; then
  echo ""
  echo "Per-VO detail:"
  for Q in 3 5 9 10; do
    echo ""
    echo "  Q${Q}:"
    VO_DIR="tods26-experiments/queries/tpch_query_${Q}/variable_orders"
    while IFS= read -r f; do
      vo_name=$(basename "$f" .txt)
      done=0
      missing=0
      for scale in sf0p1 sf1; do
        for mode in static dynamic; do
          for pred in on off; do
            csv="${OUT_DIR}/${vo_name}_${scale}_${mode}_pred_${pred}.csv"
            if [[ -s "$csv" ]]; then
              done=$((done + 1))
            else
              missing=$((missing + 1))
            fi
          done
        done
      done
      if [[ "$done" -eq 8 ]]; then
        status="COMPLETE"
      elif [[ "$done" -eq 0 ]]; then
        status="PENDING"
      else
        status="${done}/8"
      fi
      printf "    %-55s %s\n" "$vo_name" "$status"
    done < <(find "$VO_DIR" -maxdepth 1 -type f -name "tpch_q${Q}_*.txt" 2>/dev/null | sort)
  done
fi

# --- Show last log line ---
LOG_FILE="${OUT_DIR}/run_all_51vo.log"
if [[ -f "$LOG_FILE" ]]; then
  echo ""
  echo "Last log entry:"
  tail -1 "$LOG_FILE"
fi

echo ""
