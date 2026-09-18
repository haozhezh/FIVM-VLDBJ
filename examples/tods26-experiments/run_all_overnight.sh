#!/bin/bash
set -uo pipefail

# =============================================================================
# Run ALL remaining experiments: original + count queries, SF1 only.
# Both sub-scripts are idempotent/resumable — safe to re-run.
#
# Usage:
#   cd FIVM/examples
#   nohup ./tods26-experiments/run_all_overnight.sh > tods26-experiments/output/run_all_overnight.log 2>&1 &
#
#   # Check progress:
#   tail -f tods26-experiments/output/run_all_overnight.log
# =============================================================================

cd "$(dirname "$0")/.."

export RUN_TIMEOUT="${RUN_TIMEOUT:-600}"

echo "============================================================"
echo "ALL REMAINING EXPERIMENTS — original + count (SF1)"
echo "Date: $(date)"
echo "Timeout per experiment: ${RUN_TIMEOUT}s"
echo "============================================================"

echo ""
echo ">>> Phase 1/2: Original aggregation queries (38 remaining)"
echo "============================================================"
bash tods26-experiments/run_all_51vo.sh

echo ""
echo ">>> Phase 2/2: Count (SUM1) queries (116 remaining)"
echo "============================================================"
bash tods26-experiments/run_all_51vo_count.sh

echo ""
echo "============================================================"
echo "ALL DONE — $(date)"
echo "============================================================"
