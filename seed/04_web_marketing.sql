-- Clickstream: a 10% sample of web and app sessions. Each session walks the funnel
-- page_view -> product_view -> add_to_cart -> checkout_start -> purchase.
-- Conversion depends on device and traffic source.
INSERT INTO demo.web_events
SELECT
    session_id * 16 + step AS event_id,
    session_start + toIntervalSecond(toUInt32((step - 1) * (15 + 75 * cd_u(session_id * 16 + step, 'gap')))) AS event_time,
    toDate(event_time) AS event_date,
    session_id,
    customer_id,
    event_type,
    multiIf(event_type = 'page_view', cd_pick(['home', 'category', 'search', 'content'], [35, 35, 22, 8], cd_u(session_id * 16 + step, 'pt')),
            event_type = 'product_view', 'product',
            event_type = 'add_to_cart', 'cart',
            event_type = 'checkout_start', 'checkout', 'confirmation') AS page_type,
    if(event_type = 'page_view', 0, product_id) AS product_id,
    utm_source, utm_medium, device_type, browser, country,
    if(event_type = 'purchase', toDecimal64(20 + 380 * pow(cd_u(session_id, 'rev'), 1.8), 2), toDecimal64(0, 2)) AS revenue
FROM
(
    SELECT
        session_id, session_start, customer_id, product_id, utm_source, utm_medium, device_type, browser, country,
        arrayConcat(
            arrayResize(['page_view'], pv, 'page_view'),
            if(r < 0.62 * k, ['product_view'], []),
            if(r < 0.19 * k, ['add_to_cart'], []),
            if(r < 0.085 * k, ['checkout_start'], []),
            if(r < 0.046 * k, ['purchase'], [])) AS events,
        arrayJoin(arrayEnumerate(events)) AS step,
        events[step] AS event_type
    FROM
    (
        SELECT
            session_id,
            toDateTime(d, 'UTC') + toIntervalSecond(toUInt32(86399 * cd_u(session_id, 'ts'))) AS session_start,
            if(cd_u(session_id, 'known') < 0.45,
               toUInt32(1 + floor(2000000 * pow(dateDiff('day', toDate('2022-01-01'), d) / 1773, 2) * cd_u(session_id, 'cust'))),
               toUInt32(0)) AS customer_id,
            toUInt32(1 + floor(25000 * pow(cd_u(session_id, 'prod'), 2.2))) AS product_id,
            cd_pick([('google', 'organic'), ('google', 'cpc'), ('direct', '(none)'), ('newsletter', 'email'),
                     ('instagram', 'social'), ('facebook', 'social'), ('tiktok', 'social'), ('bing', 'cpc'),
                     ('partner', 'affiliate'), ('reddit', 'referral')],
                    [26, 19, 18, 9, 8 + 4 * t, 7, 3 + 5 * t, 3, 5, 2], cd_u(session_id, 'src')) AS src,
            src.1 AS utm_source,
            src.2 AS utm_medium,
            cd_pick(['desktop', 'mobile', 'tablet'], [44 - 10 * t, 50 + 10 * t, 6], cd_u(session_id, 'dev')) AS device_type,
            multiIf(device_type = 'desktop', cd_pick(['Chrome', 'Safari', 'Edge', 'Firefox'], [62, 16, 14, 8], cd_u(session_id, 'br')),
                    cd_pick(['Safari', 'Chrome', 'Samsung Internet', 'In-App'], [48, 36, 6, 10], cd_u(session_id, 'br'))) AS browser,
            cd_pick(['United States', 'United Kingdom', 'Germany', 'Canada', 'France', 'Australia', 'Netherlands', 'Spain',
                     'Brazil', 'Japan', 'Mexico', 'India', 'Italy', 'Sweden', 'Singapore', 'United Arab Emirates'],
                    [37, 12, 9, 8, 5, 3, 3, 3, 4, 3, 3, 2, 2, 2, 2, 2], cd_u(session_id, 'cty')) AS country,
            toUInt8(1 + floor(5 * pow(cd_u(session_id, 'pv'), 2.0))) AS pv,
            cd_u(session_id, 'funnel') AS r,
            (multiIf(device_type = 'desktop', 1.3, device_type = 'tablet', 1.05, 0.78)
             * multiIf(utm_source = 'newsletter', 1.7, utm_medium = 'cpc', 1.15, utm_source = 'tiktok', 0.55,
                       utm_source = 'reddit', 0.7, 1.0)
             * if(ev >= 2.2, 1.35, 1.0)) AS k
        FROM
        (
            SELECT d, t, ev, toUInt64(idx + 1) * 10000000 + s AS session_id
            FROM demo._days
            ARRAY JOIN range(toUInt32(n_orders * 1.85)) AS s
        )
    )
)
SETTINGS max_insert_threads = 6, max_block_size = 200000;

-- Paid media spend, sized so that ROAS lands in a realistic range per channel.
INSERT INTO demo.marketing_spend
SELECT
    d AS date,
    c.1 AS channel,
    c.2 AS platform,
    c.3 AS campaign,
    toUInt64(spend / c.5 * 1000) AS impressions,
    toUInt64(impressions * c.6 * (0.85 + 0.3 * cd_u(concat(toString(d), c.3), 'ctr'))) AS clicks,
    toDecimal64(n_orders * 480 * c.4 * (0.85 + 0.3 * cd_u(concat(toString(d), c.3), 'sp')), 2) AS spend
FROM demo._days
ARRAY JOIN
    -- (channel, platform, campaign, spend share of revenue, CPM, CTR)
    [('Paid Search', 'Google Ads', 'Brand Search',       0.012, 30.0,  0.09),
     ('Paid Search', 'Google Ads', 'Generic Search',     0.031, 48.0, 0.035),
     ('Paid Search', 'Google Ads', 'Shopping',           0.024, 36.0, 0.028),
     ('Paid Search', 'Microsoft Ads', 'Search',          0.006, 26.0,  0.03),
     ('Paid Social', 'Meta', 'Prospecting',              0.026 + 0.012 * t, 13.0, 0.011),
     ('Paid Social', 'Meta', 'Retargeting',              0.011, 17.0, 0.016),
     ('Paid Social', 'TikTok', 'Creators',               0.004 + 0.016 * t, 8.5, 0.009),
     ('Affiliate', 'Partner Network', 'Cashback & Deals', 0.009, 14.0, 0.02),
     ('Email', 'Klaviyo', 'Lifecycle',                   0.0025, 2.5, 0.04)] AS c;

DROP TABLE IF EXISTS demo._orders_base;
-- demo._days is kept: it documents the daily plan used by the generator.
