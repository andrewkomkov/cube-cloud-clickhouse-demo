# Cube demo: Cube Cloud vs self-hosted Cube on ClickHouse

One data source, one semantic model, two runtimes. Use it to compare
[Cube Cloud](https://cube.dev/product/cube-cloud) with self-hosted Cube Core.

## Data

ClickHouse database `demo` with a synthetic omnichannel retailer, "Northwind Outfitters",
2023-01-01 .. 2026-11-08. The generator in `seed/` is deterministic (cityHash64).

| Table | Rows | Notes |
|---|---|---|
| `orders` | 12.8M | channel, device, payment, promo, status, totals |
| `order_items` | 24.6M | product lines, discounts, COGS, returns |
| `web_events` | 76.6M | 10% clickstream sample, funnel page_view → purchase |
| `customers` | 2M | geography, segment, acquisition channel, loyalty tier |
| `products` | 25k | 8 categories, 24 subcategories, 20 brands |
| `marketing_spend` | 12.7k | daily spend, impressions, clicks per campaign |

Patterns in the data:

- 3x growth over the period, with weekly and yearly seasonality.
- Black Friday and Cyber Monday peaks, and a July sale.
- An outage on 2025-03-18: orders fall by 70%.
- The share of mobile and BNPL payments increases.
- Conversion is lower on mobile and on TikTok traffic.
- The marketplace channel has more returns.

## Semantic model (`model/`)

- Cubes: `orders`, `order_items`, `customers`, `products`, `web_events`, `marketing_spend`.
- Views (the public interface): `sales`, `product_performance`, `customer_360`,
  `web_funnel`, `marketing`.
- Rollup pre-aggregations, partitioned by month, incremental refresh with a 7-day update window:
  `orders.sales_daily`, `order_items.product_daily`, `web_events.funnel_daily`,
  `customers.signups_daily`, `marketing_spend.spend_daily`.
- Examples of modelling features: filtered measures, ratios, `rolling_window` (7-day, YTD),
  `sub_query` dimensions (customer lifetime value and value tier), `case` buckets.

ClickHouse notes:

- All pre-aggregations are `external: true`. Cube Store keeps them.
- The ClickHouse driver requires at least one index on each rollup.
- The driver cannot export HLL states. Thus the rollups do not include distinct counts
  (`orders.buyers`, `web_events.visitors`). These queries go to ClickHouse.

## Connection settings (same for both runtimes)

| Variable | Value |
|---|---|
| `CUBEJS_DB_TYPE` | `clickhouse` |
| `CUBEJS_DB_HOST` | `cube-ch.encaps.me` (Cloud) / `clickhouse` (self-hosted) |
| `CUBEJS_DB_PORT` | `443` (Cloud, HTTPS via Caddy) / `8123` |
| `CUBEJS_DB_SSL` | `true` (Cloud) |
| `CUBEJS_DB_NAME` | `demo` |
| `CUBEJS_DB_USER` | `cube` (read-only on `demo.*`) |
| `CUBEJS_DB_PASS` | from the secret store, not in this repository |
| `CUBEJS_DB_CLICKHOUSE_READONLY` | `true` |

## Self-hosted runtime (`deploy/`)

`deploy/docker-compose.yml` runs ClickHouse, Cube API (v1.6.77) and a Cube Store
cluster (router + 2 workers). `deploy/deploy.sh` syncs the files and starts the stack.
The script reads passwords from the local `secret` store. It does not write them to disk.

```sh
deploy/deploy.sh                       # all services
ssh -L 4400:localhost:4400 -L 15432:localhost:15432 dedic
open http://localhost:4400             # Playground (dev mode)
psql -h localhost -p 15432 -U cube     # SQL API, password = CUBEJS_API_SECRET
```

Seeding (inside the ClickHouse container, about 2 minutes):

```sh
for f in 01_schema 02_dimensions 03_facts 04_web_marketing; do
  docker exec cube-demo-clickhouse clickhouse-client --multiquery --queries-file /seed/$f.sql
done
```

## Cube Cloud runtime

- Deployment: "ClickHouse Retail Demo" in GCP `europe-west3`.
- Source: this repository over SSH (read-only deploy key). A GitHub webhook
  starts a build on each push to `main`.
- Environment: the variables in the table above, set in the deployment settings.
