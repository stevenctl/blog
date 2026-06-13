---
title: "Local-first, three sync engines later"
date: 2026-06-10
type: tech
tags: ["random"]
---

I want to write about the hard part of this though: the sync engine. I want
online persistence for two reasons with Bookchoy:

1. I want everything I do to be backed up and accessible on any device. This is
   pretty much a standard expectation for any modern app.
2. The chrome extension is an immediate second device, which means (I hope)
   every user will actually have utility for online persistence.

## Version one: two columns

When I first started developing, there was only a local SQLite. No auth, no
remote database, no sync engine. I knew I'd eventually build one, but I didn't
want to overengineer it before I understood what I actually needed. The whole
mental model was:

```
┌─────────────────────────┐
│   Flutter app           │
│   ┌───────────────┐     │        ┌──────────────────┐
│   │ SQLite        │◀────┼─sync──▶│ Postgres         │
│   │ (the truth)   │     │        │ (a backup that   │
│   └───────────────┘     │        │  other devices   │
│   every read & write    │        │  can read)       │
│   hits THIS, instantly  │        └──────────────────┘
└─────────────────────────┘
```

The remote is just a sync target. The UI never waits on it.

Version one of the sync engine was two columns:

```sql
ALTER TABLE saved_words ADD COLUMN syncable_modified_time timestamptz;
ALTER TABLE saved_words ADD COLUMN syncable_owner_id      text;
```

`syncable_modified_time` is the tiebreaker that decides whether the remote or
local row wins, and `syncable_owner_id` is just the user ID — Postgres RLS keys
off it so users can't touch each other's rows. The entire protocol was "grab
everything, newest wins". Roughly:

```dart
// pull: fetch ALL my rows, keep whichever side is newer
final remote = await supabase.from('saved_words')
    .select()._in('syncable_owner_id', [uid, 'public']);
for (final r in remote) {
  if (r.modifiedTime > local[r.id].modifiedTime) localDb.upsert(r);
}
// push is the mirror image, other direction
```

That's it. That's the whole engine. Full sync on startup, then push/pull
individual rows on mutation:

```
startup:   pull EVERYTHING -> newest-wins per row
mutation:  write SQLite (instant UI) -> push that one row
```

This worked for a while, and every piece of data in the app used it: saved
words and sentences, tags, stories, word lists, review info, etc.

## Version two: the high-water mark

Then I seeded tens of thousands of example sentences under a publicly
accessible `public` owner, and "pull EVERYTHING" became unusable. That's
several megabytes of data. Even when it was only the users own rows it was
still longer than I had liked.

The design needed to be incremental, only syncing changed rows. The design was
still super simple, one more column: `syncable_pushed_at`. Stamp it *just* before pushing, and
then the pull can skip everything older than the newest thing it's already
seen.

```sql
-- push: use syncable_modified_time > syncable_pushed_at as a dirty signal
SELECT * FROM saved_words
WHERE syncable_owner_id = $uid
AND (syncable_pushed_at IS NULL
     OR syncable_modified_time > syncable_pushed_at)
```

```dart
// push: stamp the row as pushed, then send it
localDb.transaction((tx) async {
    // near future re-sync will overfetch, but reduce risk of missed records
    row.syncablePushedAt = DateTime.now().add(const Duration(minutes: 1));
    await tx.update('saved_words',
      {'syncable_pushed_at': row.syncablePushedAt},
      where: 'id = ?', whereArgs: [row.id]);
    await supabase.from('saved_words').upsert(row.toJson());
})
```

```dart
// pull: skip everything I've already seen
final highwatermark = localDb
    .query('SELECT MAX(syncable_pushed_at) FROM saved_words')
    .first
    .subtract(const Duration(seconds: 30)); // grace period for clock skew

final remote = await supabase.from('saved_words').select()
    .eq('syncable_owner_id', uid)
    .gt('syncable_pushed_at', highwatermark);
```


```
rows by pushed_at:  ──●──●───●──●──●──┃──●──●──▶
                       already have   ┃  only pull these
                                 highwatermark
```

Startup sync went from "transfer everything" to "transfer almost nothing."
Great.

Except there are obvious problems with this. Client-side timestamps are totally
unreliable, and when they're off we can get into states where rows are
invisible forever:

```
device A (clock 90s slow)
   pushes row, stamps pushed_at = 10:00:00
   actual time                  = 10:01:30
                  │
                  ▼
        row lands with pushed_at = 10:00:00

device B
   last synced at 10:01:00 → highwatermark = 10:01:00
   next pull: WHERE pushed_at > 10:01:00

        10:00:00 < 10:01:00  →  row is NEVER pulled.
                                 no error. nothing. it's just gone
                                 from device B's reality.
```

Also, because the client is doing the comparisions, it has to fetch each ID that it determined
is dirty, like `WHERE id IN (?, ?, ?, ...)`. There is an upper limit, especially when using PostgREST
which is how we avoid writing an API server in front of our database (thanks Supabase). So we just bail
on being incremental when we have lots of dirty rows.

You can patch around both of these, bigger grace windows, maybe a try/catch rollback,
write-ahead push logs, but every patch is the client doing bookkeeping.

The more complex I made the clientside, the harder any eventual clientside code that isn't
in dart would be to maintain.

## Version three: server authoritative

I wanted something server authoritative, where the app doesn't have to manage
any more sync columns itself. Instead of the client holding all the logic —
conflict resolution, timestamp juggling, deciding what the server has seen — I
moved the whole protocol into a few Postgres functions:

```sql
-- make any existing table syncable. one call, in a migration.
SELECT sync.register('saved_words',
  p_pk_columns => ARRAY['id', 'syncable_owner_id']);
```

`register` does three things to the table: adds one engine-owned column (and an
index), attaches stamping triggers, and records the table in a catalog so the
generic `push`/`pull` functions know how to handle it. There is no per-table
sync code anywhere. Not in the Postgres and not in the app (kinda, it's in a library).

The RPCs give back a server-tracked cursor. For now, it's still a timestamp.
But that timestamp is always coming from the server, and not compared with any
local timestamps. The client has a bookkeeping table for the server-provided
per-table cursors.

The client leverages the other two functions as RPCs:

```dart
// the wire protocol, in its entirety: two RPCs
final page = await rpc('pull', table: 'saved_words', since: cursor);
await rpc('push',  table: 'saved_words', rows: dirtyRows);
```

But app code doesn't know about these RPCs, or how `cursor` or `dirtyRows` are computed.
That's wrapped up in a sync engine library:

```dart
const savedWords = TableSpec(
  name: 'saved_words',
  pkColumns: ['id', 'syncable_owner_id'],
);

final engine = SyncEngine(
  SqlLocalStore(db, [savedWords]),   // wraps SQLite
  SupabaseTransport(supabase),       // wraps the remote db
);


await engine.syncTable(savedWords);  // that's the whole sync call
```

A few things happen under the hood here:

1. The engine init sets up the bookkeeping table for server provided cursors:

```sql
-- bookkeeping setup at engine init
CREATE TABLE IF NOT EXISTS _syncable_cursors (
    table_name TEXT PRIMARY KEY,
    seq        INTEGER NOT NULL DEFAULT 0 -- secretly, this is a timestamp; opaque to the app
                                          -- one day it could be a monotonic sequence...
);
```

2. At init time, we also add system columns to tables listed in `TableSpec`s:


```sql
-- per registered table: the engine's two private columns
ALTER TABLE saved_words ADD COLUMN _syncable_overflow        TEXT NOT NULL DEFAULT '{}';
ALTER TABLE saved_words ADD COLUMN _syncable_local_pushed_at TEXT;

-- and a partial index over ONLY the dirty rows, so push never table-scans
CREATE INDEX IF NOT EXISTS saved_words_syncable_dirty_idx
ON saved_words (syncable_modified_time) -- still a convention the app must adhere to :(
WHERE syncable_modified_time > coalesce(_syncable_local_pushed_at, '');
```

Eventually that convention around `_syncable_local_pushed_at` and `syncable_modified_time` could be exposed
at the library level to allow custom mark-dirty strategies, but this works for what my app does. Library user
is still responsible for the `syncable_modified_time`.


## Pulling without missing rows

`pull` is a cursor walk over that server-stamped column:

```sql
SELECT * FROM saved_words
WHERE _syncable_server_wrote_at > $cursor
  AND syncable_owner_id = ANY($owners)
ORDER BY _syncable_server_wrote_at
LIMIT 1000;
```

There's a subtlety (even in the old design) I noticed as I implemented the new
framework. Rows don't become *visible* in stamp order. The trigger stamps at
write time, but the transaction commits later. A row stamped at 10:00:00 might
commit after a row stamped at 10:00:02. If your cursor already advanced past
10:00:00, you skip it.

My hack for now is, on the last page of a pull, to give a cursor that is at
least 45 seconds in the past: the newest row returned, or 45 seconds before the
present, whichever is older. For a table actively being written to, the next
pull re-reads the last 45 seconds of rows. An idle table's cursor sits exactly
at the newest row, and re-pulls nothing.

This leaves an unfortunate, but manageable, failure mode: if more than 45
seconds pass between a row being stamped and its transaction committing,
clients can miss it. Normal sync writes commit in milliseconds, so in practice
this means bulk jobs, anything holding a big transaction open has to commit in
chunks. And because the whole mechanism is server-side, it's recoverable:
touching an affected row re-stamps it, every client re-pulls it on the next
sync, and re-applying is a no-op.


```
rows by server_wrote_at:        committed ──────────┐  still in-flight
  ───●───●───●────●──●─●──●─●──●─────────────────────○──────▶ time
                                                  ▲       ▲
                                       cursor parks HERE  now
                                          (now - 45s)

next sync re-scans only the last 45 seconds — catches the late
commit ○, never re-pulls settled history, and an idle table
converges to re-pulling NOTHING.
```

Why not use a monotonic counter? Timestamps seem to be a headache, but I did
try switching to a `BIGINT` sequence to no avail. I had the same race and the
rewind mechanism is less obvious when you're subtracting some number rather
than a time interval.

The fundamental issue is the same: we need a mechanism to advance our cursor at
commit time. At some point, I could potentially fix it on the pull side using
`pg_snapshot_xmin(pg_current_snapshot())` to only pull rows from before the
_oldest open transaction_. Even in the race case where a later transaction
commits first. I punted on this as there are a few open questions:

* We need the *start time* of the oldest open transation, from
  `pg_stat_activity` or something. The RPCs are `SECURITY INVOKER` so it won't
  have `pg_read_all_stats` without some priveleged helper.
* It's cluster-wide and conservative: a long running write pins the cursor rather than
  our current optimistic 45 second window.
* I'm not a Postgres expert. These are just the first few issues with the idea that LLMs
  and Google surfaced.

The timestamp view of the world is easier for me to wrap my head around and
manually fix when things go wrong.

## Conflict resolution in one place

`push` sends dirty rows up as JSON, and the *server* merges them per column. By
default, we use a simple last-writer-wins merge rule based on trusting
`syncable_modified_time` from the client. This isn't too bad, as I want offline
edits that came later to work, and the best I can do if two devices edit the
same row is to trust their clocks. I'm not planning on any multi-user concurrent edits
right now. Just the same human saving a word on their browser and reviewing it on their phone.

A per-row sequence/version number (aka logical clock) would be more robust, but
then I have to make decisions on version-LWW or on-conflict reconciliation. This is
all stuff that I don't need, and when I do it can be a tack-on configuration per-table.

Even though client clocks aren't reliable the failure mode here is a single
wrong row, and only if a user modified it on multiple devices with a
misconfigured clock. The other client-clock issues in the old design would
break sync entirely.

The effective SQL in `push` would be something like:

```sql
INSERT INTO saved_words AS t (...)
SELECT ... FROM jsonb_populate_recordset(null::saved_words, $rows)
ON CONFLICT (id, syncable_owner_id) DO UPDATE SET
  note = CASE WHEN excluded.syncable_modified_time > t.syncable_modified_time
              THEN excluded.note ELSE t.note END,
  -- ...one CASE per column, generated from the catalog...
WHERE excluded.syncable_modified_time > t.syncable_modified_time;
```

The `WHERE` makes it so a stale push is an actual no-op. When you `push` you
get back the authoritative rows. If your write loses, you'll know and fix your
local copy.

There is a bit of customization available on the merge rules:

```sql
SELECT sync.register('reviewables',
    p_pk_columns  => array['item_id','item_type','syncable_owner_id'],
    p_merge_rules => '{"last_reviewed":"greatest"}'::jsonb
);
```

It's limited. Each column gets one of: `lww` (default), `greatest`, `least`.
These apply per-column. If `lww`, the last writer wins based on
`syncable_modified_time`. If `greatest` or `least` the server will pick `lww`
for the other columns and that column will pick one of the values.

It's limited but I only had one usecase for it: my SRS should never go back in
time when tracking the recency of reviewing some item.

## Hard-ish deletes

Currently, I did something pretty simple. You set `syncable_deleted_at` (if the
table in question _wants_ to support deletes) and we sync it like any other
column. The clients, however, treat it specially and hard delete locally. This
isn't a great solution, but it helps keep the on-device database from growing
indefinitely.

Later, I plan on implementing a proper tombstone system. An extra table that
only tracks `primary_key, owner, deleted_at` and gets synced like any other
table and we use that to communicate hard deletes. Then the server's data
doesn't need to grow indefinitely. The only small piece of complexity is that
`push` needs a resurrection guard: reject incoming writes that predate the `syncable_deleted_at`.
There's probably some cursor ordering stuff to consider too. And if we garbage
collect the tombstone we'll need to detect the case where some long-offline
client comes along and detect that it needs to do a full-resync rather than
rely on our incremental mode.

## Distributed rollback problem?

Gone, by ordering rather than by transactions:

```
pull:  fetch page → apply rows locally → THEN advance cursor  (one local txn)
push:  send dirty rows → server merges → THEN mark clean      (one local txn)

crash anywhere? replay. merging is idempotent, so re-applying
or re-pushing the same rows is a no-op.
```

The client never has to coordinate a local write with a remote write. Each
side's bookkeeping only advances *after* the other side is durably ahead of it,
and replays are harmless. That's the whole atomicity story — no rollback, just
replay.

## On-demand cache tables

```dart
TableSpec(
  name: 'story_content',
  localName: 'StoryContent',
  pkColumns: const ['id'],
  // these are enforced via RLS, but the local filter prevents us from wastefully
  // sending stuff that will get rejected or getting an error from the rpc.
  pushFilter: (row) =>
      row['syncable_owner_id'] != 'public' && AuthService.instance.isPremium,
  // only pull updates for content that we have locally already
  cursorMode: CursorMode.onDemandCache,
  manageEngineColumns: true,
  dirtyHandoffSql: _pushedAtHandoff,
)
```

The app doesn't fetch the entire catalog of content and store it locally. We do
have the ability to download stories manually, and when we do we want to keep
them up to date. The `CursorMode.onDemandCache` mode means the engine will only
pull changes for rows that we have locally already.

Calling `syncTable` with `ids: [theStoryIWantToDownload]` will do the initial pull.
Subsequent `syncTable` without explicit `ids` from the user will do a `localIds()`
list under the hood. The usecases for this are pretty specific, so it's acceptable to
me that we send O(10s) of IDs on each pull to the RPC. Even O(100s) is probably ok.

The sync here is still incremental and we won't get back rows that haven't changed
based on the cursor.

## Post-sync Hooks

```dart
engine.syncTable(
    storyContentSpec,
    owners: [uid, 'public'],
    postSync: (r) async => _reconcileDownloadedStoryAudio(r.pulled),
);
```

We can get a list of what rows changed and perform some action after the sync
finishes. Here I have some things that fetch files from object storage, or
perform other re-indexing/bookkeeping operations.

## Big initial sync could be slow

This is a problem in both versions. In the old version I worked around this by doing
a `count` to get an idea of how many pages I needed, then send some rate-limited parallel
requests for all the pages.

The pages in the old system were maxed out at 1000 rows, PostgREST default limit.
In the new version, the RPC design lets me do whatever I want. I tuned to around 4k
row pages for certain tables to minimize HTTP round trips.

The first draft of the new engine serialized the pagination though. A small optimization
here is to make sure the writes to the local database aren't serialized along with the network
I/O, so the total time is `max(network, local apply)`, not `network + local apply`.

```
network:   [── pull p1 ──][── pull p2 ──][── pull p3 ──]
local:                    [ apply p1 ]   [ apply p2 ]   [ apply p3 ]
cursor:                              ▲p1            ▲p2            ▲p3
```

Finally, we do want some parallelization. After our first fetch, we can discover
we need more pages, we can then grab `pull_boundaries` and fetch ranges in
parallel (concurrency limited).

```
  page 1 ──► has_more ──┬──► page 2          (since = p1.next_seq, known already)
                        └──► pull_boundaries ──► pages 3..K in parallel
```

We do not advance the cursor in a way that skips any pages, so if we miss one
of our parallel fetches, a future sync will re-pull pages.

```
rows by server_wrote_at:        committed ──────────┐   still in-flight
    ───●───●───●────●──●─●──●─●──●─────────────────────○──○────▶ time
       └── page 1 ──┴── page 2 ──┘                     fetched out of
          applied, cursor here ▲                       order, applied later

new rows can only come after the pages we're fetching ─────────────▶
```



## Can we avoid touching user tables?

I didn't love the fact that this engine would `ALTER` my tables. I wanted to
keep my schema clean. A couple ideas I had:

* A shadow table per syncable table, fully owned by the engine.
* Using Postgres's built-in `pg_xact_commit_timestamp` instead of my own column (maybe also solves some of the above issues!).

`pg_xact_commit_timestamp` is not indexable, so that's immediately a
non-starter. The shadow table is possible, but the queries look like this:

```sql
SELECT b.* FROM (
  SELECT id, syncable_owner_id FROM sync.cursor_saved_words
  WHERE syncable_owner_id = ANY($owners) AND server_wrote_at > $cursor
  ORDER BY server_wrote_at LIMIT 1000          -- limit BEFORE the join
) s JOIN saved_words b USING (id, syncable_owner_id);
```

That `JOIN` isn't really free. I needed to benchmark:

```
per pull:
                          column   shadow    commit-ts (unindexable)
incremental (~60 rows)    0.17ms   0.33ms    10.5ms
first page of 30k         2.8ms    5.5ms     15.0ms
first page of 300k        2.7ms    5.2ms     47.7ms
empty poll (0 rows)       0.01ms   0.01ms    5.6ms
```

> (Benchmark: Postgres 16, 1M rows — 300k-row system partition, 30k-row heavy user — single connection,
>  prepared statements, warm cache. Latencies are per-pull means.)

The shadow column is about 2x the cost of adding a column inline, when data
changes. For me, the operational cost of dirtying my tables with system stuff
is fine. If this framework was a library for others to use, it should be
feasible to make this tradeoff configurable.


## Schema drift

The schema will inevitably change as the app evovles. Usually, hopefully
always, the server before the client. When the client receives columns from the
server it doesn't know what to do with, ignoring the row wholesale and
re-pulling it every time isn't a great experience. There are a ton of features
that depend on one column and don't care about the new column and we shouldn't
break sync for them.

To handle this, the engine adds a client-side `_syncable_overflow` JSON column
to dump the stuff we don't know about yet.

```
 new client writes:   { id, note, streak_count }      ← streak_count is new
                                │ pull
                                ▼
  old client (no streak_count column):
     id, note  ───────────────► real columns
     streak_count ────────────► _syncable_overflow = {"streak_count": 7}
                                │ push (later edit to note)
                                ▼
  server splices overflow back out:
     note         ← from the old client (changed)
     streak_count ← 7, restored from overflow, never clobbered
```

On pull, the engine just dumps unknown state there, and on push we can
gracefully handle missing columns. Rather than doing LWW for the whole row,
missing columns preserve their remote copy as the client can't have changed
them.

During engine init (~app launch), after applying any local migrations we scan
for `_syncable_overflow IS NOT NULL` and attempt to reconcile things back into
real columns.

## Where it landed

| phase (per table) | old engine | new engine | winner |
|---|---|---|---|
| figure out what to push | read entire local table into Dart, diff in memory (200 row limit for incremental mode comparison, fallback to full scan) | partial-index peek at dirty rows only | new, O(dataset)→O(changes) |
| push | upsert rows wholesale (rewrites even unchanged) | dirty rows only; server suppresses no-op writes | new |
| conflict resolution | in Dart, after materializing both sides | in the upsert's ON CONFLICT, set-based | new |
| figure out what to pull | > highwatermark | one indexed cursor query, paged ≤1000 | ~perf parity, complexity win |
| apply pulls | diff then write | write changed rows only | ~perf parity, complexity win |
| delete reconciliation | full snapshots of both sides + verify queries | a null-check on rows already in hand | new |
| nothing-changed total | one table scan + one filtered query per table | one index peek + one empty pull per table | ~parity |

So my Flutter app's dart sync went from about 3000 total lines of awkward generics to this (per table):

```dart
final reviewablesSpec = TableSpec(
  name: 'reviewables',
  localName: 'Reviewables',
  pkColumns: const ['item_id', 'type', 'syncable_owner_id'],
  manageEngineColumns: true,
);

// ...
await engine.syncTable(
    spec,
    ids: ids,
    owners: owners,
    incremental: ignoreHighwatermark ? false : null,
);
```

The framework lives in a separate module, with tons of conformance and
integration tests. On top of that, there is a separate TypeScript
implementation, which now backs the chrome extension. I managed to layer on
some backwards and forwards compatibility to keep old clients in the wild from
breaking when the new schema changes rolled out. This is in production now and
seems to working well (for my tiny little userbase).
