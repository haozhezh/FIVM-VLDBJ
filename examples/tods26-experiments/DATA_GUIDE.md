# Experiment Data Guide

## Results Location

All experiment results are in:
```
FIVM/examples/tods26-experiments/output/
```

Only **sf1** (scale factor 1) results exist. Old sf0.1 and old hand-picked VO
results have been moved to `output/old_results_backup/` and should NOT be used.

There are **two types of experiments**: main (sum/aggregation) queries and count queries.

## File Naming Convention

### Main (sum) queries
```
tpch_q{Q}_vo{NN}_{description}_sf1_{mode}_pred_{pred}.csv
```

### Count queries
```
q{Q}count_tpch_q{Q}cnt_vo{NN}_{description}_sf1_{mode}_pred_{pred}.csv
```

- `Q`: query number (3, 5, 9, 10)
- `NN`: variable order number (zero-padded for Q5/Q9: vo01..vo26; single-digit for Q3/Q10: vo1..vo5)
- `description`: human-readable VO structure (e.g., `nation_supp_cust_order`)
- `mode`: `static` (dimension tables are TABLE, no updates) or `dynamic` (all tables are STREAM)
- `pred`: `on` (query predicates applied) or `off` (no predicates)

Examples:
- Main: `tpch_q5_vo01_nation_supp_cust_order_sf1_static_pred_on.csv`
- Count: `q5count_tpch_q5cnt_vo01_nation_supp_cust_order_sf1_static_pred_on.csv`

### Main vs Count query difference

Count queries use `SELECT SUM(1)` — no GROUP BY, no aggregation expressions.
This isolates the join/maintenance overhead from the aggregation overhead.
Same variable orders, same predicates, same table declarations.

## CSV Format

```csv
source,batch_id,rows,inserts,deletes,duration_ms
LINEITEM,-1,6927,6927,0,1.55817
ORDERS,-1,1732,1732,0,0.856712
```

| Column | Description |
|--------|-------------|
| `source` | Base relation that was updated (e.g., LINEITEM, ORDERS, CUSTOMER) |
| `batch_id` | Batch sequence number (-1 for initial load batches) |
| `rows` | Total rows in this batch |
| `inserts` | Number of inserts |
| `deletes` | Number of deletes |
| `duration_ms` | Wall-clock time to process this batch, in milliseconds |

**Key metric**: Total runtime = `SUM(duration_ms)` across all rows in a file.
**Throughput**: `SUM(rows) / (SUM(duration_ms) / 1000)` = rows per second.

### Notes on `source`
- In `static` mode: only stream relations appear (LINEITEM, ORDERS for Q3/Q5/Q9/Q10; CUSTOMER for Q5/Q10).
  Dimension tables (NATION, REGION, SUPPLIER, PART, PARTSUPP) have zero batches.
- In `dynamic` mode: all relations appear, including dimension tables with small batches.

### Notes on `batch_id`
- `batch_id = -1`: initial load phase (before steady-state processing begins).
  These may appear multiple times as different relations are loaded.
- `batch_id >= 0`: steady-state update batches.

## Experiment Matrix

Each VO is tested in 4 configurations: {static, dynamic} × {pred_on, pred_off} = 4 CSV files per VO.

### Main Query Completion Status

| Query | VOs | Configs | Files | Status |
|-------|-----|---------|-------|--------|
| Q3  | 2  | 4 each | 8   | **100% complete** |
| Q5  | 26 | 4 each | 104 expected | **Partial** (see below) |
| Q9  | 18 | 4 each | 72  | **100% complete** |
| Q10 | 5  | 4 each | 20  | **100% complete** |

### Count Query Completion Status

| Query | VOs | Configs | Files expected | Status |
|-------|-----|---------|----------------|--------|
| Q3 count  | 2  | 4 each | 8   | **100% complete** (from prior run) |
| Q5 count  | 26 | 4 each | 104 | **Partial** (~19 of 104 from renamed old results) |
| Q9 count  | 18 | 4 each | 72  | **Partial** (~28 of 72 from renamed old results) |
| Q10 count | 5  | 4 each | 20  | **Needs re-run** (old results in subdirectory) |

Count query experiments will be completed via `run_all_51vo_count.sh` (see Overnight Run section).

### Q5 Detailed Status

| VO | Description | Status |
|----|-------------|--------|
| vo01 | nation→supp→cust→order | COMPLETE (4/4) |
| vo02 | nation→supp→order→cust | COMPLETE (4/4) |
| vo03 | nation→cust→supp→order | COMPLETE (4/4) |
| vo04 | nation→order→cust→supp | **TIMEOUT** (0/4) |
| vo05 | nation→cust→order→supp | COMPLETE (4/4) |
| vo06 | nation→order→supp→cust | COMPLETE (4/4) |
| vo07 | supp→nation→cust→order | COMPLETE (4/4) |
| vo08 | supp→nation→order→cust | COMPLETE (4/4) |
| vo09 | supp→order→cust→nation | PARTIAL (1/4: static_pred_on only) |
| vo10 | supp→order→nation→cust | PARTIAL (3/4: missing dynamic_pred_off) |
| vo11 | supp→cust→order→nation | PARTIAL (3/4: missing dynamic_pred_off) |
| vo12 | cust→order→supp→nation | **TIMEOUT** (0/4) |
| vo13 | cust→nation→supp→order | COMPLETE (4/4) |
| vo14 | cust→nation→order→supp | COMPLETE (4/4) |
| vo15 | cust→order→nation→supp | **TIMEOUT** (0/4) |
| vo16 | cust→supp→order→nation | PARTIAL (3/4: missing dynamic_pred_off) |
| vo17 | order→cust→supp→nation | **TIMEOUT** (0/4) |
| vo18 | order→supp→nation→cust | PARTIAL (3/4: missing dynamic_pred_off) |
| vo19 | order→cust→nation→supp | **TIMEOUT** (0/4) |
| vo20 | order→supp→cust→nation | PARTIAL (1/4: static_pred_on only) |
| vo21 | order→nation→supp→cust | COMPLETE (4/4) |
| vo22 | order→nation→cust→supp | **TIMEOUT** (0/4) |
| vo23 | nation→{order→{cust,supp}} bushy | COMPLETE (4/4) |
| vo24 | supp→{cust→{nation,order}} bushy | PARTIAL (3/4: missing dynamic_pred_off) |
| vo25 | cust→{supp→{nation,order}} bushy | PARTIAL (3/4: missing dynamic_pred_off) |
| vo26 | order→{nation→{cust,supp}} bushy | COMPLETE (4/4) |

**For analysis**: Treat all Q5 VOs that are not COMPLETE as **timed out at 10 minutes**.
These VOs exceed the 10-minute per-experiment timeout, which is itself a meaningful result
(they are impractical variable orders). Overnight runs with a uniform 10-minute timeout will
fill in any remaining gaps.

## Variable Order Definitions

### VO Text Files

Main queries:
```
FIVM/examples/tods26-experiments/queries/tpch_query_{Q}/variable_orders/
```

Count queries (identical tree structures, just `q{Q}cnt` prefix):
```
FIVM/examples/tods26-experiments/queries/tpch_query_{Q}_count/variable_orders/
```

File format (F-IVM DTREE format):
```
<total_columns> <num_join_keys>
<col_id> <col_name> <type> <parent_id> {ancestor_set} <is_key>
...
```

The first `num_join_keys` lines define the join variable hierarchy (the variable order).
Remaining lines are non-key attributes placed under their deepest join key ancestor.

### VO Structure Summary

All 51 VOs are Cartesian-product-free. The structure is encoded in the filename:

- **Chain VOs** (linear): `vo01_nation_supp_cust_order` means nationkey → suppkey → custkey → orderkey
- **Bushy VOs** (branching): `vo23_nation_root_order_child_bushy` means nationkey → orderkey → {custkey, suppkey}

### Programmatic VO Definitions

All VOs are also defined programmatically in:
```
cost-model/tree_generator.py
```

- `Q3_ALL_VOS` (2 VOs), `Q5_ALL_VOS` (26 VOs), `Q9_ALL_VOS` (18 VOs), `Q10_ALL_VOS` (5 VOs)
- `ALL_QUERIES_FULL` = all 4 queries with their full VO lists (51 total)

Each `VOSpec` has: `name` (e.g., "vo01"), `root` variable, `children` dict defining the tree.

### Join Variables Per Query

| Query | Join Variables | Cardinalities (sf1) |
|-------|---------------|---------------------|
| Q3 | orderkey, custkey | 1.5M, 150K |
| Q5 | nationkey, suppkey, custkey, orderkey | 25, 10K, 150K, 1.5M |
| Q9 | nationkey, suppkey, partkey, orderkey | 25, 10K, 200K, 1.5M |
| Q10 | nationkey, custkey, orderkey | 25, 150K, 1.5M |

## Cost Model

The cost model predicting VO performance is in:
```
cost-model/pipeline.py          # Main entry point
cost-model/cost_model_lib.py    # Cost computation
cost-model/tree_generator.py    # VO definitions + tree builder
cost-model/generic_stats.py     # Statistics estimation (R1-R5 rules)
```

Run predictions:
```bash
cd cost-model
python pipeline.py --db tpch_sf1.duckdb --query all --breakdown
```

## Overnight Runs

### Main queries (to complete remaining Q5)

```bash
cd FIVM/examples
nohup ./tods26-experiments/run_all_51vo.sh > tods26-experiments/output/run_all_51vo.log 2>&1 &
```

This will skip all already-completed experiments and attempt the remaining Q5 VOs
with a 10-minute timeout. Check progress with `./tods26-experiments/check_progress.sh`.

### Count queries (all 51 VOs)

```bash
cd FIVM/examples
nohup ./tods26-experiments/run_all_51vo_count.sh > tods26-experiments/output/run_all_51vo_count.log 2>&1 &
```

204 total experiments (51 VOs × 4 configs). ~55 already done from prior runs.
Count queries are typically much faster than main queries. Both runners are
idempotent and resumable — they skip any experiment whose output CSV already
exists and is non-empty.

## What Happened With Count Query VO Numbering

**Background**: When we expanded from hand-picked VOs to the exhaustive 51 CP-free
set, the VO numbering changed (e.g., old Q5 vo1 = nation→cust→order→supp became
new vo05; old Q9 vo4 = supp→order→part→nation was a Cartesian-product VO and was
removed entirely).

The main query experiment files were regenerated with the new numbering, but the
count query `generate_assets.py` files were NOT updated — they still had the old
7 VOs for Q5 and 8 VOs for Q9 (including 1 CP VO).

**What was fixed**:
1. Updated `tpch_query_5_count/generate_assets.py`: 7 old VOs → 26 CP-free VOs
2. Updated `tpch_query_9_count/generate_assets.py`: 8 old VOs → 18 CP-free VOs
3. Regenerated all 51 VO text files + 408 SQL files for count queries
4. Created `run_all_51vo_count.sh` — unified resumable runner for all count queries
5. Renamed existing count result CSVs to match new VO numbering
6. Discarded Q9 old vo4 (supp→order→part→nation) count results — it was a CP VO

**Verified by Codex GPT-5.4**: VO_CONFIGS match between main and count for all 4
queries, join-key tree structures are identical, all SQL files use `SELECT SUM(1)`
with no GROUP BY, file counts are correct (51 VOs, 408 SQL files).
