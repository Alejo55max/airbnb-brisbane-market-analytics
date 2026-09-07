# Executive Summary — Brisbane Airbnb Market Analysis

*Full SQL: [`sql/01_schema.sql`](sql/01_schema.sql) – [`sql/03_business_analysis.sql`](sql/03_business_analysis.sql). Query execution & charts: [`airbnb_brisbane_market_analysis.ipynb`](airbnb_brisbane_market_analysis.ipynb).*

## Business Problem

Short-term rental platforms are central to Australia's housing-affordability debate, and directly relevant to Brisbane as it scales tourism accommodation ahead of the 2032 Olympics. This analysis asks a specific, testable question using real public data: **is Brisbane's Airbnb market dominated by individuals renting a spare room, or by commercial-scale operators running rental portfolios — and what does that structure imply for pricing, growth, and housing supply?**

## Data

**Source:** [Inside Airbnb](https://insideairbnb.com), Brisbane QLD, snapshot 2026-07-14.

| Table | Rows | Content |
|---|---|---|
| `listings` | 6,358 | One row per active listing: host, suburb, price, property/room type, ratings, estimated revenue & occupancy |
| `calendar` | 2,320,670 | Daily availability per listing, 2026-07-14 → 2027-07-13 (**forward-looking**, not historical) |
| `reviews` | 323,588 | Review date and reviewer per listing, 2011-03-16 → 2026-07-14 |
| `hosts` | 2,762 | Deduplicated host dimension (superhost status, identity verification, etc.) |
| `neighbourhoods` | 131 | Brisbane suburb dimension |

**Data-quality decisions made before analysis (not assumed):**
- Confirmed via direct query that `host_since`, `host_response_time/rate`, `license` and `instant_bookable` are **100% empty** in this export (Airbnb no longer publishes them) — excluded from the schema rather than modeled as unusable columns.
- Manually inspected the top of the price distribution: one listing was priced at **$18,623/night** for a 2-bedroom, 6-guest unit — 2.7x the next-highest price in the dataset, and consistent with the known pattern of hosts setting an unreasonably high "deterrent" price when they don't want bookings. The 99th percentile (**$1,266**) was used as a cutoff for all pricing analysis; occupancy/review analysis (where price isn't used) retains the full dataset.
- `estimated_revenue_l365d` and `estimated_occupancy_l365d` are **Inside Airbnb's own modeled metrics**, derived from price, calendar availability, and review activity — not confirmed host payouts or booking counts. Used throughout as the standard proxy for revenue and demand.

## Methodology

1. **Schema design & ETL** (`sql/00`–`sql/02`): raw CSVs loaded into text-only staging tables 1:1 with the source columns, then transformed into a typed, normalized 5-table schema (foreign keys, `NULLIF`/cast cleaning, price-string parsing) — verified with zero orphaned foreign keys after load.
2. **10 business questions answered entirely in SQL** (`sql/03`), using joins across all 5 tables, CTEs for readability, and window functions (`RANK()`, `ROW_NUMBER()`, `LAG()`, running-total `SUM() OVER`) for ranking, period-over-period comparison, and cumulative concentration measures.
3. **Every query executed and its output inspected** before being written up — no number below is asserted without having been produced by a query run against the live database.

## Results

**1. Market size and geography.** Total estimated annual revenue across the market: **A$154.6M**. Brisbane City (A$31.9M), South Brisbane (A$19.8M) and Fortitude Valley (A$15.6M) — the three inner-city/CBD-adjacent suburbs — together account for **~44% of total estimated revenue**.

**2. Price landscape.** Median entire-home price ranges from ~A$727/night (Moreton Island, a small island-tourism outlier) down to ~A$157–200/night in outer suburbs; inner-city suburbs (Brisbane City, South Brisbane, Fortitude Valley, New Farm) cluster around A$300–360/night median for entire homes, roughly double the median private-room price in the same suburbs.

**3. Revenue concentration.** Of hosts with revenue data, **658 multi-listing hosts (28% of hosts) hold 3,882 listings (70% of priced listings) and capture 71.4% of total market revenue** — versus 1,699 single-listing hosts capturing 28.6%.

**4. The superhost effect.** Restricted to listings with 5+ reviews: superhosts average **133 estimated booked nights/year vs. 90** for regular hosts (+48%), **A$41,147 vs. A$31,302 estimated revenue** (+31%), and a **4.88 vs. 4.67** average rating.

**5. Forward booking pace.** The 12 months following the scrape show a booked-out rate starting at 66% (partial current month), dropping to a low of **37.4% in September 2026**, then climbing steadily back to **~59% by mid-2027**. Read as a booking/blocking-pace signal, not a confirmed-bookings trend (see Limitations).

**6. Market concentration by host.** The single largest host, **Bedspoke Brisbane, runs 286 listings and earns an estimated 10.4% of the entire market's revenue alone**. The top 3 hosts combined reach **19.5%** of total market revenue.

**7. Market growth.** Among listings still active today, the number that went live in each year has accelerated sharply: 396 (2022) → 668 (2023) → 968 (2024) → **1,573 (2025)** → 1,005 already by the July 2026 scrape date — the fastest growth on record, ahead of the 2032 Olympics.

**8. Demand momentum.** Review-volume growth (last 12 months vs. prior 12 months) is fastest in outer/suburban areas — Macgregor (+711%), Upper Kedron–Ferny Grove (+411%), Murarrie (+341%) — well above the CBD core (Brisbane City +78%, South Brisbane +22%), suggesting the market's growth edge is shifting into residential suburbs.

**9. Stay-length mix.** 88.0% of listings are genuine short-stay tourism (1–3 night minimum), 10.5% are mid-stay (4–29 nights), and **1.6% (99 listings) require 30+ nights** — functioning like standard leases rather than short-term tourism accommodation.

**10. Value-for-money.** A combined CTE + window-function query identifies one standout listing per suburb (top-rated, 10+ reviews, priced below its suburb-and-room-type median) — a practical output demonstrating the schema can support a recommendation-style query, not just aggregate reporting.

## Interpretation

The popular framing of Airbnb — an individual monetising a spare room — does not match what the data shows for Brisbane. **A minority of hosts (28%) capture the large majority of revenue (71%)**, and market leadership sits with identifiably commercial operators (property-management-style host names, 100+ listing portfolios), not casual hosts. Combined with accelerating year-on-year growth and demand now expanding into outer suburbs, this is consistent with the concerns raised in Australia's housing-supply debate: short-term rental activity increasingly resembles a professionalised accommodation sector operating inside residential housing stock, not a peer-to-peer sharing model.

## Business Recommendations

1. **Any housing-policy or taxation discussion of short-term rentals should account for revenue concentration**, not treat "the average host" as representative — the effect of a regulatory change on 658 commercial operators is very different from its effect on 1,699 individuals with one listing.
2. **Monitor outer-suburb growth specifically**, not just aggregate CBD volume — the suburbs with the fastest-growing demand (Macgregor, Upper Kedron–Ferny Grove, Murarrie) are where short-term rental supply is most actively displacing what would otherwise be long-term rental housing stock.
3. **Separate the ~1.6% of long-stay/lease-like listings from short-stay tourism accommodation** in any regulatory or tax framework, since they serve a functionally different market.

## Limitations

- `estimated_revenue_l365d` / `estimated_occupancy_l365d` are Inside Airbnb's own modeled estimates, not confirmed host payouts, tax records, or platform-verified booking counts.
- `calendar` is forward-looking (365 days after the scrape) and conflates host-blocked dates with genuine bookings — used here as a booking-pace indicator, not validated against actual reservation data.
- The market-growth series (Q7) reflects the **vintage mix of currently active listings only** — it undercounts historical listing volume in earlier years, since listings that have since been delisted are not in this snapshot.
- Single point-in-time snapshot (2026-07-14) — no multi-year Brisbane trend comparison; growth conclusions rely on the *first-review* proxy rather than direct year-over-year snapshots.
- Host identity is by host name/ID as published by Airbnb; multiple listings run under different named "hosts" but the same underlying management company would not be detected by this analysis.

## References

- Inside Airbnb (2026), *Brisbane, Queensland, Australia* dataset, snapshot 2026-07-14. https://insideairbnb.com/brisbane
- PostgreSQL Global Development Group (2026), *PostgreSQL 17 Documentation* — window functions, CTEs. https://www.postgresql.org/docs/
- McKee, M. (2019), 'Inside Airbnb: adding data to the debate', Inside Airbnb project methodology notes. http://insideairbnb.com/about
- The Pandas Development Team (2026), *pandas documentation*. https://pandas.pydata.org/docs/
- Hunter, J. D. (2007), 'Matplotlib: A 2D graphics environment', *Computing in Science & Engineering*, vol. 9, no. 3, pp. 90-95.

---
*Independent project, built to close a specific gap identified against current Australian data-analyst job postings (SQL — see [`README.md`](README.md) for the market-research context). Data: Inside Airbnb, Brisbane QLD, 2026-07-14 snapshot.*
