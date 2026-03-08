IMPORT DTREE FROM FILE '../variable_orders/tpch_q9_vo14_order_part_supp_nation.txt';

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
  FROM FILE './datasets/updates_sf1_b10000_dynamic/lineitem.csv'
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
  FROM FILE './datasets/updates_sf1_b10000_dynamic/orders.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


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
  FROM FILE './datasets/updates_sf1_b10000_dynamic/part.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


CREATE STREAM PARTSUPP (
        partkey         INT,
        suppkey         INT,
        ps_availqty     INT,
        ps_supplycost   DECIMAL,
        ps_comment      VARCHAR(199)
    )
  FROM FILE './datasets/updates_sf1_b10000_dynamic/partsupp.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


CREATE STREAM SUPPLIER (
        suppkey        INT,
        s_name         CHAR(25),
        s_address      VARCHAR(40),
        nationkey      INT,
        s_phone        CHAR(15),
        s_acctbal      DECIMAL,
        s_comment      VARCHAR(101)
    )
  FROM FILE './datasets/updates_sf1_b10000_dynamic/supplier.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


CREATE STREAM NATION (
        nationkey      INT,
        n_name         CHAR(25),
        regionkey      INT,
        n_comment      VARCHAR(152)
    )
  FROM FILE './datasets/updates_sf1_b10000_dynamic/nation.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


SELECT n_name,
       EXTRACT(year FROM o_orderdate),
       SUM((l_extendedprice * (1 - l_discount)) - (ps_supplycost * l_quantity))
FROM PART NATURAL JOIN PARTSUPP NATURAL JOIN LINEITEM NATURAL JOIN ORDERS NATURAL JOIN SUPPLIER NATURAL JOIN NATION
GROUP BY n_name, EXTRACT(year FROM o_orderdate);
