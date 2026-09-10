# Query optimisation notes

The query from Part 5:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

The index that was added for it, in `db/migrations/002_indexes.sql`:

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

Everything below was measured on the seeded data set: 50,000 bookings, 58,735
events, of which 12,454 bookings are in Delhi and 3,018 fall inside the 30 day
window. Numbers come from `EXPLAIN (ANALYZE, BUFFERS)` on Postgres 16.

## Why this shape

**`city` first, `created_at` second.** A b-tree can only apply a range bound to
the column that comes after the equality predicates. With `(city, created_at)`
Postgres descends straight to `city = 'delhi'` and then walks forward from the
30 day boundary, touching only entries it will actually return. Reverse the
columns and the range predicate becomes the leading one, so the scan has to
cover every city inside the time window and discard most of what it reads.

**`org_id`, `status` and `amount` as `INCLUDE` payload.** They are never
searched on, they are only projected - two grouping keys and one aggregate
input. Carrying them in the index leaf pages turns the scan into an *index-only
scan*: the aggregate is answered without visiting the table at all. Putting them
in the key instead would make the b-tree bigger and the comparisons more
expensive for no gain, because nothing sorts or searches by them.

## Measured, four ways

| Index | Plan | Buffers | Execution |
|---|---|---|---|
| none | Seq Scan | 725 | 8.09 ms |
| `(created_at, city)` | Bitmap Index + Heap Scan | 746 (32 index + 714 heap) | 2.53 ms |
| `(city, created_at)` | Bitmap Index + Heap Scan | 721 (7 index + 714 heap) | 2.36 ms |
| `(city, created_at) INCLUDE (org_id, status, amount)` | **Index Only Scan** | **41** | **1.30 ms** |

Buffers matter more than the millisecond figures here. On a laptop with a 13 MB
table everything is already in cache, so wall time understates the difference.
On an RDS instance where the working set does not fit in `shared_buffers`, 725
buffer reads against 41 is the whole story - that is 684 fewer 8 KB pages
pulled per execution of a query that a dashboard runs constantly.

### Before - sequential scan

```
HashAggregate (actual time=8.027..8.034 rows=30 loops=1)
  Group Key: org_id, status
  Buffers: shared hit=725
  ->  Seq Scan on hotel_bookings (actual time=0.015..7.320 rows=3018 loops=1)
        Filter: (((city)::text = 'delhi'::text) AND (created_at >= (now() - '30 days'::interval)))
        Rows Removed by Filter: 46982
        Buffers: shared hit=725
Execution Time: 8.085 ms
```

46,982 rows read and thrown away to return 3,018.

### After - index-only scan

```
HashAggregate (actual time=1.237..1.243 rows=30 loops=1)
  Group Key: org_id, status
  Buffers: shared hit=41
  ->  Index Only Scan using idx_hotel_bookings_city_created_at on hotel_bookings (actual time=0.155..0.644 rows=3018 loops=1)
        Index Cond: ((city = 'delhi'::text) AND (created_at >= (now() - '30 days'::interval)))
        Heap Fetches: 0
        Buffers: shared hit=41
Execution Time: 1.301 ms
```

`Heap Fetches: 0` is the line to check. It means every row was answered from the
index. If that number climbs, the visibility map has gone stale - the table
needs a vacuum, and until then the "index-only" scan is quietly paying for heap
lookups anyway. That is why `seed.sql` ends with `VACUUM ANALYZE` and why
`restore.sh` runs one after a restore.

### The two near-misses

Without `INCLUDE`, the index finds the right rows in 7 buffer reads and then
spends 714 more visiting the heap for `org_id`, `status` and `amount`:

```
Bitmap Heap Scan on hotel_bookings (actual time=0.298..1.185 rows=3018 loops=1)
      Heap Blocks: exact=714
      Buffers: shared hit=714 read=7
```

With the columns reversed, the index part alone costs 32 buffers instead of 7 -
four and a half times the index pages, because `city` can no longer be used as a
search bound and is only a filter:

```
Bitmap Index Scan on tmp_rev (actual time=0.587..0.587 rows=3018 loops=1)
      Index Cond: ((created_at >= (now() - '30 days'::interval)) AND ((city)::text = 'delhi'::text))
      Buffers: shared read=32
```

## Things deliberately not done

**A partial index on the last 30 days.** Tempting, and it would be smaller, but
`NOW()` is not immutable so the predicate has to be a hard-coded date. The index
then silently stops matching the query as the date drifts, and someone has to
remember to rebuild it. Not worth the operational trap for a table this size.

**Indexing `lower(city)`.** The query filters on the literal `'delhi'` and the
seed data is lower-case throughout. If real traffic sends `'Delhi'`, the right
fix is normalising on write or a `citext` column, not a second functional index
that only papers over inconsistent data.

**A GIN index on `booking_events.payload`.** Nothing in this exercise queries
inside the JSONB. The moment something does - filtering on `payload->>'channel'`,
say - `CREATE INDEX ... USING gin (payload jsonb_path_ops)` is the answer, but
an unused GIN index is pure write amplification.

## Second index

```sql
CREATE INDEX idx_booking_events_booking_id_created_at
    ON booking_events (booking_id, created_at DESC);
```

This one is not for Part 5. It covers the other obvious access pattern in this
schema - "show me the history of this booking, newest first" - and it also backs
the foreign key on `booking_id`, so deleting a booking does not have to
sequentially scan the events table to find its children.

## How to re-check any of this

```bash
docker compose exec postgres psql -U bookings_app -d bookings -f /work/db/queries/booking_rollup.sql
```

To see the "before" plan without permanently dropping the index:

```sql
BEGIN;
DROP INDEX idx_hotel_bookings_city_created_at;
EXPLAIN (ANALYZE, BUFFERS) SELECT org_id, status, COUNT(*), SUM(amount)
  FROM hotel_bookings
  WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
  GROUP BY org_id, status;
ROLLBACK;   -- the index is never actually gone
```
