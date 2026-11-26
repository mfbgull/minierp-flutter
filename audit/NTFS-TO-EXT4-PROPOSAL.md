# Proposal: move the repo off NTFS to ext4

**Status: DONE (verified 2026-11-26). The move happened; this record is kept
for the evidence trail. Nothing in the proposal is still to do.**

## Closure (2026-11-26)

Gull reported the repo is already on ext4. That was verified, not taken on
trust:

| Check | Result |
|---|---|
| `findmnt -T .` | `/home` → `/dev/nvme0n1p8`, **ext4**, `rw,relatime` |
| Repo root | `/home/fawad/minierp` — on that mount |
| Old NTFS path (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter`) | **does not exist** |
| `server/node_modules` | ext4 (same mount) |
| `core.filemode` | `true` — git honours the exec bit |

The stall this proposal was written about is gone:

| Measure | In the proposal | Measured 2026-11-26 |
|---|---|---|
| `/proc/pressure/io` `avg300` "some" | ~28% | 2.81% |
| `/proc/pressure/io` `avg300` "full" | ~8% | 0.94% |

Two differences from the plan are recorded so nobody looks for them later:

- The chosen root is `/home/fawad/minierp`, not the `/home/fawad/repos/…` path
  the proposal suggested. Both are on the same ext4 volume.
- `database/` does not exist at the repo root. The dev database is not in this
  tree, so the "keep the live DB with the tree" risk no longer applies here.

One loose end found during closure and fixed in the same commit:
`scripts/check.sh` was tracked mode `100644`, so `./scripts/check.sh` exited
126 ("permission denied") and only `bash scripts/check.sh` worked. The mode is
now `100755`, matching its own usage header and `AGENTS.md`. See
`audit/FINDINGS-STATUS.md` for the two earlier gates that hit exit 126.

The sections below are the original proposal text, unchanged.

## Where things used to live

| Path | Filesystem | Type | Mount |
|---|---|---|---|
| `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter` (repo root) | `/dev/nvme0n1p4` | **fuseblk (NTFS)** | FUSE, `udisks2` |
| `server/node_modules` | same | **fuseblk (NTFS)** | inside the repo |
| `database/erp.db` (live dev DB) | same | **fuseblk (NTFS)** | inside the repo |
| `build/`, `server/.tmp-test/` | same | **fuseblk (NTFS)** | inside the repo |

So the repo, its dependencies and the SQLite database are all on a FUSE-mounted
NTFS volume. The durable artifacts I already moved — worktrees and logs — sit on
ext4 (`/home`, `/dev/nvme0n1p8`).

## Why it matters

SQLite journals through `fsync`/`fsync`-style commits. On this FUSE mount a
worker process enters uninterruptible sleep (`D` state) on
`jbd2_log_wait_commit`, because FUSE serialises and re-orders the metadata
writes that a local journal does cheaply.

Observed, not inferred:

- A jest worker sits in `D` state during the current run (`pid 67789`,
  `node .../jest-worker/build/processChild.js`).
- System IO pressure is sustained: `/proc/pressure/io` `avg300` ≈ 28% "some",
  ≈ 8% "full".
- A full server suite on this mount has taken ~1400–2120 s. The same suite on a
  warm cache is minutes. Three suites were earlier recorded as "hanging ~11.6 h"
  locally (BUG-011) but pass on CI — the same stall, not a code hang.

The cost is wall-clock, not correctness. No test failed because of it.

## Proposed move

1. Create the target on ext4: `/home/fawad/repos/minierp-flutter`.
2. Copy the working tree, excluding caches that are regenerable:
   `build/` (2.2 G), `server/.tmp-test/` (483 M), `.codegraph/` (115 M).
   The copy is then roughly `5.3 G − 2.8 G ≈ 2.5 G`.
3. Keep `server/node_modules` by copying it, or rebuild with `npm ci` on ext4.
   A rebuild is safest: a binary built on one filesystem can hold a stale native
   path. `better-sqlite3` is the one native module to watch.
4. Point the existing worktrees and scripts at the new root, or recreate them.
5. Leave the NTFS copy in place until a full `scripts/check.sh` passes on ext4.
   Then remove it.

### Space

`/home` (ext4, `/dev/nvme0n1p8`) has **20 G free** of 117 G (83% used). A ~2.5 G
copy fits. Do not copy `build/` first if space is tight; it is regenerable.

### Risks

- **Native module rebuild.** `better-sqlite3` must be rebuilt or re-fetched for
  the target; node is v24.22.2 (`NODE_MODULE_VERSION` 137).
- **Path lengths and links.** Git hooks, `.pi/`, `.omo/` and any absolute paths
  in scripts or worktree metadata reference the old root. `git worktree` entries
  store absolute paths and must be repaired (`git worktree repair`).
- **The live dev DB.** Move `database/erp.db` with the tree, or point
  `DATABASE_PATH` at the new location. Do not leave two copies that can diverge.
- **Disk full.** 20 G free is enough now but not generous; deleting `build/`
  before the copy is the safe order.

## Recommendation

Do the move. The stall costs hours per full run locally, and it is the reason
BUG-011 looked like a hang. Move the tree and `node_modules` together, keep the
live DB with it, and re-run `scripts/check.sh` on ext4 to confirm the timing.
