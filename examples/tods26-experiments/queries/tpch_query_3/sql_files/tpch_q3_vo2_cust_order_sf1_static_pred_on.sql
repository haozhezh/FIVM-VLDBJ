IMPORT DTREE FROM FILE '../variable_orders/tpch_q3_vo2_cust_order.txt';

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
  FROM FILE './datasets/updates_sf1_b10000_static/lineitem.csv'
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
  FROM FILE './datasets/updates_sf1_b10000_static/orders.csv'
  LINE DELIMITED CSV (delimiter := '|', predefined_batches := 'true');


CREATE TABLE CUSTOMER (
        custkey        INT,
        c_name         VARCHAR(25),
        c_address      VARCHAR(40),
        nationkey      INT,
        c_phone        CHAR(15),
        c_acctbal      DECIMAL,
        c_mktsegment   CHAR(10),
        c_comment      VARCHAR(117)
    )
  FROM FILE './datasets/updates_sf1_b10000_static/customer_q3static.csv'
  LINE DELIMITED CSV (delimiter := '|');


SELECT  orderkey,
        o_orderdate,
        o_shippriority,
        SUM(l_extendedprice * (1 - l_discount))
FROM    customer NATURAL JOIN orders NATURAL JOIN lineitem
WHERE   c_mktsegment = 'BUILDING'
  AND   o_orderdate < DATE('1995-03-15')
  AND   l_shipdate > DATE('1995-03-15')
GROUP BY orderkey, o_orderdate, o_shippriority;
