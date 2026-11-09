-- Daily plan: number of orders per day with growth, weekly and yearly seasonality,
-- Black Friday / Cyber Monday peaks, a July sale and one outage day (2025-03-18).
DROP TABLE IF EXISTS demo._days;
CREATE TABLE demo._days ENGINE = Memory AS
SELECT d, idx, t, ev, toUInt32(round(4700 * g * wk * mo * ev * nz)) AS n_orders
FROM
(
    WITH toDate('2023-01-01') AS d0, toDate('2026-11-08') AS d1
    SELECT
        d0 + number AS d,
        number AS idx,
        number / dateDiff('day', d0, d1) AS t,
        exp(log(3.0) * t) AS g,
        [1.04, 0.98, 0.97, 1.0, 1.06, 1.12, 1.15][toDayOfWeek(d)] AS wk,
        [0.86, 0.8, 0.92, 0.95, 0.98, 0.95, 0.93, 0.97, 1.0, 1.03, 1.22, 1.42][toMonth(d)] AS mo,
        toDate(concat(toString(toYear(d)), '-11-01')) AS nov1,
        nov1 + ((12 - toDayOfWeek(nov1)) % 7) + 21 AS bf,
        multiIf(d = bf, 3.1, d BETWEEN bf + 1 AND bf + 2, 2.2, d = bf + 3, 2.6,
                toMonth(d) = 7 AND toDayOfMonth(d) IN (15, 16), 1.9,
                d = toDate('2025-03-18'), 0.31, 1.0) AS ev,
        1 + 0.1 * (cd_u(number, 'daynoise') - 0.5) AS nz
    FROM numbers(dateDiff('day', d0, d1) + 1)
);

-- Order headers without money columns.
DROP TABLE IF EXISTS demo._orders_base;
CREATE TABLE demo._orders_base ENGINE = MergeTree ORDER BY order_id AS
SELECT
    order_id,
    toUInt32(1 + floor(2000000 * pow(dateDiff('day', toDate('2022-01-01'), d) / 1773, 2)
                       * pow(cd_u(order_id, 'cust'), 1.25))) AS customer_id,
    toDateTime(d, 'UTC') + toIntervalSecond(hour * 3600 + toUInt32(cd_u(order_id, 'sec') * 3600)) AS created_at,
    d AS order_date,
    multiIf(age <= 1, cd_pick(['processing', 'shipped', 'cancelled'], [70, 25, 5], cd_u(order_id, 'st')),
            age <= 5, cd_pick(['shipped', 'completed', 'cancelled'], [45, 50, 5], cd_u(order_id, 'st')),
            cd_pick(['completed', 'returned', 'cancelled'],
                    [86.5, 7 + 3 * (ch = 'Marketplace'), 6.5], cd_u(order_id, 'st'))) AS status,
    ch AS sales_channel,
    multiIf(ch = 'Web', cd_pick(['Desktop', 'Mobile Web', 'Tablet'], [55 - 12 * t, 38 + 12 * t, 7], cd_u(order_id, 'dev')),
            ch = 'Mobile App', cd_pick(['iOS', 'Android'], [58, 42], cd_u(order_id, 'dev')),
            ch = 'Marketplace', 'Marketplace', 'In-Store') AS device,
    if(ch = 'Retail Store',
       cd_pick(['Credit Card', 'Debit Card', 'Apple Pay', 'Cash'], [45, 25, 15, 15], cd_u(order_id, 'pay')),
       cd_pick(['Credit Card', 'Debit Card', 'PayPal', 'Apple Pay', 'Google Pay', 'Buy Now Pay Later', 'Gift Card'],
               [38, 18, 14, 9 + 6 * t, 5 + 3 * t, 3 + 7 * t, 3], cd_u(order_id, 'pay'))) AS payment_method,
    if(ch = 'Retail Store', 'Store Walk-in',
       cd_pick(['Organic Search', 'Paid Search', 'Direct', 'Email', 'Paid Social', 'Affiliate', 'Referral'],
               [26, 22, 18, 12, 12 + 6 * t, 6, 4], cd_u(order_id, 'mkt'))) AS marketing_channel,
    multiIf(ev >= 2.2 AND cd_u(order_id, 'promo') < 0.55, 'BFCM30',
            cd_u(order_id, 'promo2') < 0.72, '',
            cd_pick(['WELCOME10', 'SAVE15', if(toMonth(d) IN (6, 7, 8), 'SUMMER20', 'SEASON20'), 'VIP25', 'FREESHIP'],
                    [8, 7, 6, 3, 6], cd_u(order_id, 'promo3'))) AS promo_code,
    toUInt8(multiIf(promo_code = 'BFCM30', 30, promo_code = 'WELCOME10', 10, promo_code = 'SAVE15', 15,
                    promo_code IN ('SUMMER20', 'SEASON20'), 20, promo_code = 'VIP25', 25, 0)) AS discount_pct,
    if(ch = 'Retail Store', 'In-Store',
       cd_pick(['Standard', 'Express', 'Next Day', 'Click & Collect'], [62, 22, 8, 8], cd_u(order_id, 'ship'))) AS shipping_method,
    toUInt8(cd_pick([1, 2, 3, 4, 5, 6], [52, 24, 12, 6, 4, 2], cd_u(order_id, 'items'))) AS items_count
FROM
(
    SELECT
        d, t, ev,
        toUInt64(idx + 1) * 1000000 + k AS order_id,
        dateDiff('day', d, toDate('2026-11-08')) AS age,
        toUInt32(cd_pick(range(24), [2, 1, 0.6, 0.4, 0.4, 0.8, 2, 4, 5, 6, 6, 6.5, 6.5, 6, 5.5, 5.5, 6, 7, 8, 9, 9.5, 8.5, 6, 4],
                         cd_u(order_id, 'hour'))) AS hour,
        cd_pick(['Web', 'Mobile App', 'Marketplace', 'Retail Store'], [46 - 14 * t, 28 + 16 * t, 18 - 2 * t, 8],
                cd_u(order_id, 'ch')) AS ch
    FROM demo._days
    ARRAY JOIN range(n_orders) AS k
);

-- Order lines. Product popularity has a long tail.
INSERT INTO demo.order_items
SELECT
    b.order_id, b.line_number, b.order_date, b.created_at, b.product_id, b.quantity,
    p.list_price AS unit_price,
    toDecimal64(unit_price * b.quantity, 2) AS gross_amount,
    toDecimal64(gross_amount * b.discount_pct / 100, 2) AS discount_amount,
    gross_amount - discount_amount AS net_amount,
    toDecimal64(p.unit_cost * b.quantity, 2) AS cost_amount,
    toUInt8(b.status = 'returned' AND (b.line_number = 1 OR cd_u(b.order_id * 10 + b.line_number, 'ret') < 0.4))
FROM
(
    SELECT
        order_id, order_date, created_at, discount_pct, status,
        toUInt8(line) AS line_number,
        toUInt32(1 + floor(25000 * pow(cd_u(order_id * 10 + line, 'prod'), 2.2))) AS product_id,
        toUInt16(cd_pick([1, 2, 3, 4], [85, 11, 3, 1], cd_u(order_id * 10 + line, 'qty'))) AS quantity
    FROM demo._orders_base
    ARRAY JOIN range(1, items_count + 1) AS line
) AS b
INNER JOIN demo.products AS p ON p.product_id = b.product_id
SETTINGS max_insert_threads = 6;

-- Orders with totals.
INSERT INTO demo.orders
SELECT
    o.order_id, o.customer_id, o.created_at, o.order_date, o.status, o.sales_channel, o.device,
    o.payment_method, o.marketing_channel, o.promo_code, o.discount_pct, o.shipping_method, o.items_count,
    a.units, a.subtotal, a.discount_amount,
    toDecimal64(multiIf(o.shipping_method IN ('In-Store', 'Click & Collect') OR o.promo_code = 'FREESHIP'
                        OR a.subtotal - a.discount_amount >= 75, 0,
                        o.shipping_method = 'Standard', 4.99, o.shipping_method = 'Express', 12.99, 24.99), 2) AS shipping_amount,
    a.subtotal - a.discount_amount + shipping_amount AS total_amount,
    a.cost_amount
FROM demo._orders_base AS o
INNER JOIN
(
    SELECT order_id, toUInt16(sum(quantity)) AS units, sum(gross_amount) AS subtotal,
           sum(discount_amount) AS discount_amount, sum(cost_amount) AS cost_amount
    FROM demo.order_items
    GROUP BY order_id
) AS a ON a.order_id = o.order_id
SETTINGS join_algorithm = 'grace_hash', grace_hash_join_initial_buckets = 8;
