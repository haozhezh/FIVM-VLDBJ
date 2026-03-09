#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[4] / "aux"))

from variable_order import Relation, VariableOrderNode, generate_txt  # type: ignore
import tpch_schema as tpch  # type: ignore


KEY_MAP = {
    "order": "orderkey",
    "part": "partkey",
    "supp": "suppkey",
    "nation": "nationkey",
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


def build_relations() -> list[Relation]:
    return [tpch.Part, tpch.PartSupp, tpch.Lineitem, tpch.Orders, SUPPLIER_SHARED, tpch.Nation]


def build_chain(ordering):
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in ordering}
    for parent, child in zip(ordering, ordering[1:]):
        nodes[parent].add_child(nodes[child])
    root = nodes[ordering[0]]
    return root, build_relations(), {}


# --- Bushy VO builders ---
# Each matches the corresponding VOSpec in tree_generator.py Q9_ALL_VOS

def build_bushy_vo25():
    """suppkey → {nationkey, orderkey → partkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["supp"]
    root.add_child(nodes["order"])
    nodes["order"].add_child(nodes["part"])
    root.add_child(nodes["nation"])
    return root, build_relations(), {}


def build_bushy_vo26():
    """suppkey → {nationkey, partkey → orderkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["supp"]
    root.add_child(nodes["nation"])
    root.add_child(nodes["part"])
    nodes["part"].add_child(nodes["order"])
    return root, build_relations(), {}


def build_bushy_vo29():
    """orderkey → suppkey → {nationkey, partkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["order"]
    root.add_child(nodes["supp"])
    nodes["supp"].add_child(nodes["part"])
    nodes["supp"].add_child(nodes["nation"])
    return root, build_relations(), {}


def build_bushy_vo30():
    """partkey → suppkey → {nationkey, orderkey}"""
    nodes = {name: VariableOrderNode(KEY_MAP[name]) for name in KEY_MAP}
    root = nodes["part"]
    root.add_child(nodes["supp"])
    nodes["supp"].add_child(nodes["order"])
    nodes["supp"].add_child(nodes["nation"])
    return root, build_relations(), {}


# 18 CP-free VOs (14 chains + 4 bushy), matching Q9_ALL_VOS in tree_generator.py
# Cartesian-product VOs (12 total: 10 chains + 2 bushy) excluded.
VO_CONFIGS = [
    # --- 14 CP-free chains ---
    ("tpch_q9cnt_vo01_nation_supp_order_part", lambda: build_chain(["nation", "supp", "order", "part"])),
    ("tpch_q9cnt_vo02_nation_supp_part_order", lambda: build_chain(["nation", "supp", "part", "order"])),
    ("tpch_q9cnt_vo03_nation_order_supp_part", lambda: build_chain(["nation", "order", "supp", "part"])),
    ("tpch_q9cnt_vo04_nation_part_order_supp", lambda: build_chain(["nation", "part", "order", "supp"])),
    ("tpch_q9cnt_vo05_nation_order_part_supp", lambda: build_chain(["nation", "order", "part", "supp"])),
    ("tpch_q9cnt_vo06_nation_part_supp_order", lambda: build_chain(["nation", "part", "supp", "order"])),
    ("tpch_q9cnt_vo07_order_part_supp_nation", lambda: build_chain(["order", "part", "supp", "nation"])),
    ("tpch_q9cnt_vo08_order_nation_supp_part", lambda: build_chain(["order", "nation", "supp", "part"])),
    ("tpch_q9cnt_vo09_order_nation_part_supp", lambda: build_chain(["order", "nation", "part", "supp"])),
    ("tpch_q9cnt_vo10_order_part_nation_supp", lambda: build_chain(["order", "part", "nation", "supp"])),
    ("tpch_q9cnt_vo11_part_order_supp_nation", lambda: build_chain(["part", "order", "supp", "nation"])),
    ("tpch_q9cnt_vo12_part_order_nation_supp", lambda: build_chain(["part", "order", "nation", "supp"])),
    ("tpch_q9cnt_vo13_part_nation_supp_order", lambda: build_chain(["part", "nation", "supp", "order"])),
    ("tpch_q9cnt_vo14_part_nation_order_supp", lambda: build_chain(["part", "nation", "order", "supp"])),
    # --- 4 bushy VOs (all CP-free) ---
    ("tpch_q9cnt_vo15_supp_root_order_nation_bushy", build_bushy_vo25),   # supp→{nation, order→part}
    ("tpch_q9cnt_vo16_supp_root_part_nation_bushy", build_bushy_vo26),    # supp→{nation, part→order}
    ("tpch_q9cnt_vo17_order_root_bushy", build_bushy_vo29),                # order→supp→{nation,part}
    ("tpch_q9cnt_vo18_part_root_bushy", build_bushy_vo30),                 # part→supp→{nation,order}
]

SCALES = ["sf0p1", "sf1"]
MODES = ["static", "dynamic"]
PRED_FLAGS = ["on", "off"]

BASE_DIR = Path(__file__).resolve().parent
VO_DIR = BASE_DIR / "variable_orders"
SQL_DIR = BASE_DIR / "sql_files"


def write_vo_files():
    VO_DIR.mkdir(parents=True, exist_ok=True)
    for existing in VO_DIR.glob("tpch_q9cnt_*.txt"):
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
    part_table = f"""
CREATE TABLE PART (
        partkey        INT,
        p_name         VARCHAR(55),
        p_mfgr         CHAR(25),
        p_brand        CHAR(10),
        p_type         VARCHAR(25),
        p_size         INT,
        p_container    CHAR(10),
        p_retailprice  DECIMAL,
        p_comment      VARCHAR(23)
    )
  FROM FILE '{base_path}/part.csv'
  LINE DELIMITED CSV (delimiter := '|');
"""
    part_stream = f"""
CREATE STREAM PART (
        partkey        INT,
        p_name         VARCHAR(55),
        p_mfgr         CHAR(25),
        p_brand        CHAR(10),
        p_type         VARCHAR(25),
        p_size         INT,
        p_container    CHAR(10),
        p_retailprice  DECIMAL,
        p_comment      VARCHAR(23)
    )
  FROM FILE '{base_path}/part.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');
"""
    partsupp_table = f"""
CREATE TABLE PARTSUPP (
        partkey         INT,
        suppkey         INT,
        ps_availqty     INT,
        ps_supplycost   DECIMAL,
        ps_comment      VARCHAR(199)
    )
  FROM FILE '{base_path}/partsupp.csv'
  LINE DELIMITED CSV (delimiter := '|');
"""
    partsupp_stream = f"""
CREATE STREAM PARTSUPP (
        partkey         INT,
        suppkey         INT,
        ps_availqty     INT,
        ps_supplycost   DECIMAL,
        ps_comment      VARCHAR(199)
    )
  FROM FILE '{base_path}/partsupp.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');
"""
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
    where_clause = "WHERE p_name LIKE '%green%'\n" if pred_on else ""

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

{part_table if mode == 'static' else part_stream}
{partsupp_table if mode == 'static' else partsupp_stream}
{supplier_table if mode == 'static' else supplier_stream}
{nation_table if mode == 'static' else nation_stream}

SELECT SUM(1)
FROM PART NATURAL JOIN PARTSUPP NATURAL JOIN LINEITEM NATURAL JOIN ORDERS NATURAL JOIN SUPPLIER NATURAL JOIN NATION
{where_clause};
"""
    return sql


def write_sql_files():
    SQL_DIR.mkdir(parents=True, exist_ok=True)
    for existing in SQL_DIR.glob("tpch_q9cnt_*.sql"):
        existing.unlink()
    vo_files = sorted(p.name for p in VO_DIR.glob("tpch_q9cnt_*.txt"))
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
