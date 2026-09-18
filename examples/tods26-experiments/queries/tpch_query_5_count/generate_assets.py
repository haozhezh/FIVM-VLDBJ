#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[4] / "aux"))

from variable_order import Relation, VariableOrderNode, generate_txt  # type: ignore
import tpch_schema as tpch  # type: ignore


KEY_MAP = {
    "nation": "nationkey",
    "cust": "custkey",
    "order": "orderkey",
    "supp": "suppkey",
}

SUPPLIER_SHARED = Relation(
    "supplier",
    {
        "suppkey": "int",
        "s_name": "string",
        "s_address": "string",
        "nationkey": "int",
        "s_phone": "string",
        "s_acctbal": "double",
        "s_comment": "string",
    },
    {"suppkey", "nationkey"},
)


def query_relations():
    return [tpch.Customer, tpch.Orders, tpch.Lineitem, SUPPLIER_SHARED, tpch.Nation, tpch.Region]


def build_chain(ordering):
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in ordering}
    for parent, child in zip(ordering, ordering[1:]):
        nodes[parent].add_child(nodes[child])
    root = nodes[ordering[0]]
    return root, query_relations(), {}


# --- Bushy VO builders ---
# Each matches the corresponding VOSpec in tree_generator.py Q5_ALL_VOS

def build_bushy_vo25():
    """nationkey → orderkey → {custkey, suppkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["nation"]
    root.add_child(nodes["order"])
    nodes["order"].add_child(nodes["cust"])
    nodes["order"].add_child(nodes["supp"])
    return root, query_relations(), {}


def build_bushy_vo26():
    """suppkey → custkey → {nationkey, orderkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["supp"]
    root.add_child(nodes["cust"])
    nodes["cust"].add_child(nodes["nation"])
    nodes["cust"].add_child(nodes["order"])
    return root, query_relations(), {}


def build_bushy_vo27():
    """custkey → suppkey → {nationkey, orderkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["cust"]
    root.add_child(nodes["supp"])
    nodes["supp"].add_child(nodes["nation"])
    nodes["supp"].add_child(nodes["order"])
    return root, query_relations(), {}


def build_bushy_vo28():
    """orderkey → nationkey → {custkey, suppkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["order"]
    root.add_child(nodes["nation"])
    nodes["nation"].add_child(nodes["cust"])
    nodes["nation"].add_child(nodes["supp"])
    return root, query_relations(), {}


# 26 CP-free VOs (22 chains + 4 bushy), matching Q5_ALL_VOS in tree_generator.py
# Cartesian-product VOs (supp→cust→nation→order, cust→supp→nation→order) excluded.
VO_CONFIGS = [
    # --- 22 CP-free chains ---
    ("tpch_q5cnt_vo01_nation_supp_cust_order", lambda: build_chain(["nation", "supp", "cust", "order"])),
    ("tpch_q5cnt_vo02_nation_supp_order_cust", lambda: build_chain(["nation", "supp", "order", "cust"])),
    ("tpch_q5cnt_vo03_nation_cust_supp_order", lambda: build_chain(["nation", "cust", "supp", "order"])),
    ("tpch_q5cnt_vo04_nation_order_cust_supp", lambda: build_chain(["nation", "order", "cust", "supp"])),
    ("tpch_q5cnt_vo05_nation_cust_order_supp", lambda: build_chain(["nation", "cust", "order", "supp"])),
    ("tpch_q5cnt_vo06_nation_order_supp_cust", lambda: build_chain(["nation", "order", "supp", "cust"])),
    ("tpch_q5cnt_vo07_supp_nation_cust_order", lambda: build_chain(["supp", "nation", "cust", "order"])),
    ("tpch_q5cnt_vo08_supp_nation_order_cust", lambda: build_chain(["supp", "nation", "order", "cust"])),
    ("tpch_q5cnt_vo09_supp_order_cust_nation", lambda: build_chain(["supp", "order", "cust", "nation"])),
    ("tpch_q5cnt_vo10_supp_order_nation_cust", lambda: build_chain(["supp", "order", "nation", "cust"])),
    ("tpch_q5cnt_vo11_supp_cust_order_nation", lambda: build_chain(["supp", "cust", "order", "nation"])),
    ("tpch_q5cnt_vo12_cust_order_supp_nation", lambda: build_chain(["cust", "order", "supp", "nation"])),
    ("tpch_q5cnt_vo13_cust_nation_supp_order", lambda: build_chain(["cust", "nation", "supp", "order"])),
    ("tpch_q5cnt_vo14_cust_nation_order_supp", lambda: build_chain(["cust", "nation", "order", "supp"])),
    ("tpch_q5cnt_vo15_cust_order_nation_supp", lambda: build_chain(["cust", "order", "nation", "supp"])),
    ("tpch_q5cnt_vo16_cust_supp_order_nation", lambda: build_chain(["cust", "supp", "order", "nation"])),
    ("tpch_q5cnt_vo17_order_cust_supp_nation", lambda: build_chain(["order", "cust", "supp", "nation"])),
    ("tpch_q5cnt_vo18_order_supp_nation_cust", lambda: build_chain(["order", "supp", "nation", "cust"])),
    ("tpch_q5cnt_vo19_order_cust_nation_supp", lambda: build_chain(["order", "cust", "nation", "supp"])),
    ("tpch_q5cnt_vo20_order_supp_cust_nation", lambda: build_chain(["order", "supp", "cust", "nation"])),
    ("tpch_q5cnt_vo21_order_nation_supp_cust", lambda: build_chain(["order", "nation", "supp", "cust"])),
    ("tpch_q5cnt_vo22_order_nation_cust_supp", lambda: build_chain(["order", "nation", "cust", "supp"])),
    # --- 4 bushy VOs (all CP-free) ---
    ("tpch_q5cnt_vo23_nation_root_order_child_bushy", build_bushy_vo25),   # nation→order→{cust,supp}
    ("tpch_q5cnt_vo24_supp_root_cust_child_bushy", build_bushy_vo26),      # supp→cust→{nation,order}
    ("tpch_q5cnt_vo25_cust_root_supp_child_bushy", build_bushy_vo27),      # cust→supp→{nation,order}
    ("tpch_q5cnt_vo26_order_root_nation_child_bushy", build_bushy_vo28),   # order→nation→{cust,supp}
]

SCALES = ["sf0p1", "sf1"]
MODES = ["static", "dynamic"]
PRED_FLAGS = ["on", "off"]

BASE_DIR = Path(__file__).resolve().parent
VO_DIR = BASE_DIR / "variable_orders"
SQL_DIR = BASE_DIR / "sql_files"


def write_vo_files():
    VO_DIR.mkdir(parents=True, exist_ok=True)
    for existing in VO_DIR.glob("tpch_q5cnt_*.txt"):
        existing.unlink()
    for name, builder in VO_CONFIGS:
        root, relations, free_vars = builder()
        out_path = VO_DIR / f"{name}.txt"
        content = generate_txt(relations, root, free_vars)
        out_path.write_text(content)
        print(f"Wrote VO: {out_path}")


def sql_template(mode, scale, pred_on, vo_file):
    base_path = f"./datasets/updates_{scale}_b10000_{mode}"

    # Dimension tables: TABLE in static mode, STREAM in dynamic mode
    supplier_table = f"""
CREATE TABLE SUPPLIER (
        suppkey        INT,
        s_name         CHAR(25),
        s_address      VARCHAR(40),
        nationkey      INT,
        s_phone        CHAR(15),
        s_acctbal      DECIMAL,
        s_comment      VARCHAR(101)
    )
  FROM FILE '{base_path}/supplier.csv'
  LINE DELIMITED CSV (delimiter := '|');
"""
    supplier_stream = f"""
CREATE STREAM SUPPLIER (
        suppkey        INT,
        s_name         CHAR(25),
        s_address      VARCHAR(40),
        nationkey      INT,
        s_phone        CHAR(15),
        s_acctbal      DECIMAL,
        s_comment      VARCHAR(101)
    )
  FROM FILE '{base_path}/supplier.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');
"""
    nation_table = f"""
CREATE TABLE NATION (
        nationkey      INT,
        n_name         CHAR(25),
        regionkey      INT,
        n_comment      VARCHAR(152)
    )
  FROM FILE '{base_path}/nation.csv'
  LINE DELIMITED CSV (delimiter := '|');
"""
    nation_stream = f"""
CREATE STREAM NATION (
        nationkey      INT,
        n_name         CHAR(25),
        regionkey      INT,
        n_comment      VARCHAR(152)
    )
  FROM FILE '{base_path}/nation.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');
"""
    region_table = f"""
CREATE TABLE REGION (
        regionkey      INT,
        r_name         CHAR(25),
        r_comment      VARCHAR(152)
    )
  FROM FILE '{base_path}/region.csv'
  LINE DELIMITED CSV (delimiter := '|');
"""
    region_stream = f"""
CREATE STREAM REGION (
        regionkey      INT,
        r_name         CHAR(25),
        r_comment      VARCHAR(152)
    )
  FROM FILE '{base_path}/region.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');
"""
    where_clause = (
        "WHERE   r_name = 'ASIA'\n"
        "  AND   o_orderdate >= DATE('1994-01-01')\n"
        "  AND   o_orderdate < DATE('1995-01-01')\n"
        if pred_on
        else ""
    )

    sql = f"""IMPORT DTREE FROM FILE '../variable_orders/{vo_file}';

CREATE STREAM LINEITEM (
        orderkey         INT,
        partkey          INT,
        suppkey          INT,
        l_linenumber     INT,
        l_quantity       DECIMAL,
        l_extendedprice  DECIMAL,
        l_discount       DECIMAL,
        l_tax            DECIMAL,
        l_returnflag     CHAR(1),
        l_linestatus     CHAR(1),
        l_shipdate       DATE,
        l_commitdate     DATE,
        l_receiptdate    DATE,
        l_shipinstruct   CHAR(25),
        l_shipmode       CHAR(10),
        l_comment        VARCHAR(44)
    )
  FROM FILE '{base_path}/lineitem.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');

CREATE STREAM ORDERS (
        orderkey         INT,
        custkey          INT,
        o_orderstatus    CHAR(1),
        o_totalprice     DECIMAL,
        o_orderdate      DATE,
        o_orderpriority  CHAR(15),
        o_clerk          CHAR(15),
        o_shippriority   INT,
        o_comment        VARCHAR(79)
    )
  FROM FILE '{base_path}/orders.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');

CREATE STREAM CUSTOMER (
        custkey        INT,
        c_name         VARCHAR(25),
        c_address      VARCHAR(40),
        nationkey      INT,
        c_phone        CHAR(15),
        c_acctbal      DECIMAL,
        c_mktsegment   CHAR(10),
        c_comment      VARCHAR(117)
    )
  FROM FILE '{base_path}/customer.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');

{supplier_stream}
{nation_table if mode == 'static' else nation_stream}
{region_table if mode == 'static' else region_stream}

SELECT SUM(1)
FROM customer NATURAL JOIN orders NATURAL JOIN lineitem NATURAL JOIN supplier NATURAL JOIN nation NATURAL JOIN region
{where_clause};
"""
    return sql


def write_sql_files():
    SQL_DIR.mkdir(parents=True, exist_ok=True)
    for existing in SQL_DIR.glob("tpch_q5cnt_*.sql"):
        existing.unlink()
    vo_files = sorted(p.name for p in VO_DIR.glob("tpch_q5cnt_*.txt"))
    for vo in vo_files:
        base = vo.removesuffix(".txt")
        for scale in SCALES:
            for mode in MODES:
                for pred in PRED_FLAGS:
                    pred_on = pred == "on"
                    out_name = f"{base}_{scale}_{mode}_pred_{pred}.sql"
                    out_path = SQL_DIR / out_name
                    out_path.write_text(sql_template(mode, scale, pred_on, vo))
                    print(f"Wrote SQL: {out_path}")


def main():
    write_vo_files()
    write_sql_files()


if __name__ == "__main__":
    main()
