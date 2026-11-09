-- Northwind Outfitters: synthetic omnichannel retailer, 2022-01-01 .. 2026-11-08.
-- All values are generated deterministically from cityHash64, so a rerun gives the same data.

CREATE DATABASE IF NOT EXISTS demo;

-- uniform [0,1) from a key and a salt
CREATE FUNCTION IF NOT EXISTS cd_u AS (k, salt) -> (cityHash64(k, salt) % 1000000) / 1000000.;
-- weighted choice: element of arr, chosen by weights w and uniform r
CREATE FUNCTION IF NOT EXISTS cd_pick AS (arr, w, r) ->
    arr[arrayFirstIndex(x -> x >= r * arraySum(w), arrayCumSum(w))];

DROP TABLE IF EXISTS demo.customers;
CREATE TABLE demo.customers
(
    customer_id          UInt32,
    full_name            String,
    email                String,
    signup_date          Date,
    country              LowCardinality(String),
    city                 LowCardinality(String),
    region               LowCardinality(String),
    segment              LowCardinality(String),
    acquisition_channel  LowCardinality(String),
    age_band             LowCardinality(String),
    gender               LowCardinality(String),
    loyalty_tier         LowCardinality(String),
    is_marketing_opt_in  UInt8
)
ENGINE = MergeTree
ORDER BY customer_id;

DROP TABLE IF EXISTS demo.products;
CREATE TABLE demo.products
(
    product_id    UInt32,
    sku           String,
    product_name  String,
    category      LowCardinality(String),
    subcategory   LowCardinality(String),
    brand         LowCardinality(String),
    list_price    Decimal(12, 2),
    unit_cost     Decimal(12, 2),
    launched_on   Date,
    is_private_label UInt8
)
ENGINE = MergeTree
ORDER BY product_id;

DROP TABLE IF EXISTS demo.orders;
CREATE TABLE demo.orders
(
    order_id            UInt64,
    customer_id         UInt32,
    created_at          DateTime('UTC'),
    order_date          Date,
    status              LowCardinality(String),
    sales_channel       LowCardinality(String),
    device              LowCardinality(String),
    payment_method      LowCardinality(String),
    marketing_channel   LowCardinality(String),
    promo_code          LowCardinality(String),
    discount_pct        UInt8,
    shipping_method     LowCardinality(String),
    items_count         UInt8,
    units               UInt16,
    subtotal            Decimal(14, 2),
    discount_amount     Decimal(14, 2),
    shipping_amount     Decimal(14, 2),
    total_amount        Decimal(14, 2),
    cost_amount         Decimal(14, 2)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, sales_channel, order_id);

DROP TABLE IF EXISTS demo.order_items;
CREATE TABLE demo.order_items
(
    order_id         UInt64,
    line_number      UInt8,
    order_date       Date,
    created_at       DateTime('UTC'),
    product_id       UInt32,
    quantity         UInt16,
    unit_price       Decimal(12, 2),
    gross_amount     Decimal(14, 2),
    discount_amount  Decimal(14, 2),
    net_amount       Decimal(14, 2),
    cost_amount      Decimal(14, 2),
    is_returned      UInt8
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, product_id, order_id, line_number);

DROP TABLE IF EXISTS demo.web_events;
CREATE TABLE demo.web_events
(
    event_id      UInt64,
    event_time    DateTime('UTC'),
    event_date    Date,
    session_id    UInt64,
    customer_id   UInt32,          -- 0 = anonymous visitor
    event_type    LowCardinality(String),
    page_type     LowCardinality(String),
    product_id    UInt32,          -- 0 = no product on the page
    utm_source    LowCardinality(String),
    utm_medium    LowCardinality(String),
    device_type   LowCardinality(String),
    browser       LowCardinality(String),
    country       LowCardinality(String),
    revenue       Decimal(14, 2)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, event_type, session_id, event_id);

DROP TABLE IF EXISTS demo.marketing_spend;
CREATE TABLE demo.marketing_spend
(
    date         Date,
    channel      LowCardinality(String),
    platform     LowCardinality(String),
    campaign     LowCardinality(String),
    impressions  UInt64,
    clicks       UInt64,
    spend        Decimal(14, 2)
)
ENGINE = MergeTree
ORDER BY (date, channel, platform, campaign);
