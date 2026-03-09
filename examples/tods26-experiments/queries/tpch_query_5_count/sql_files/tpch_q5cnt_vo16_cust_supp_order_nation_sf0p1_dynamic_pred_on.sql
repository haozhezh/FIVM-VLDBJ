IMPORT DTREE FROM FILE '../variable_orders/tpch_q5cnt_vo16_cust_supp_order_nation.txt';

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
  FROM FILE './datasets/updates_sf0p1_b10000_dynamic/lineitem.csv'
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
  FROM FILE './datasets/updates_sf0p1_b10000_dynamic/orders.csv'
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
  FROM FILE './datasets/updates_sf0p1_b10000_dynamic/customer.csv'
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
  FROM FILE './datasets/updates_sf0p1_b10000_dynamic/supplier.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


CREATE STREAM NATION (
        nationkey      INT,
        n_name         CHAR(25),
        regionkey      INT,
        n_comment      VARCHAR(152)
    )
  FROM FILE './datasets/updates_sf0p1_b10000_dynamic/nation.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


CREATE STREAM REGION (
        regionkey      INT,
        r_name         CHAR(25),
        r_comment      VARCHAR(152)
    )
  FROM FILE './datasets/updates_sf0p1_b10000_dynamic/region.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


SELECT SUM(1)
FROM customer NATURAL JOIN orders NATURAL JOIN lineitem NATURAL JOIN supplier NATURAL JOIN nation NATURAL JOIN region
WHERE   r_name = 'ASIA'
  AND   o_orderdate >= DATE('1994-01-01')
  AND   o_orderdate < DATE('1995-01-01')
;
