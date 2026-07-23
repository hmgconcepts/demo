# Database installation

Run **`complete-schema.sql`** once in the Supabase SQL Editor. It is the single,
self-contained, dependency-ordered, idempotent v12 schema for a **fresh** deployment —
and it also **repairs** older School Connect databases (missing tables, columns, unique
keys, policies) without touching your data.

Files:
- `complete-schema.sql` — **run this** (currently **v12.3**; ends with PostgREST cache reload).
- `complete-schema-v12-clean.sql` — identical named copy (kept in sync with `complete-schema.sql`).
- `complete-schema-v11-LEGACY-MERGED.sql` — historical reference only; do NOT run on new projects.
- `*.csv` — import templates & sample question banks.

- `demo-users.sql` / `demo-seed.sql` — demo-deployment guest accounts + simulated school (see DEMO-SETUP.md in a demo ZIP).
- `cbt-1000-scale.sql` — **optional additive pack** for projects already on v12.x: idempotent CBT submissions (client_ref), the v2 exam-fetch/submit functions and hot-path indexes so **1000 students can write one exam simultaneously**. Included inside `complete-schema.sql` from v12.3 onward, so fresh installs already have it.

## v12.3 patch — CBT 1000-concurrent scale pack (2026-07-23)
Section 16 of the schema now ships the scale pack: submissions are IDEMPOTENT
(a retry after a network drop returns the original result instead of a
duplicate), grading stays 100% server-side and is shuffle-safe (graded by each
question's `_orig_index`, not screen position), attempt limits and the exam
close-window are enforced by the database, and the exam page syncs its clock to
the server. The client needs no changes and falls back to the v1 functions on
older schemas. For live projects already on v12.1/v12.2, run
`database/cbt-1000-scale.sql` once — same content, standalone.

## v12.1 patch — 42703 "column student_id does not exist" (2026-07-22)
If you saw `ERROR: 42703: column "student_id" does not exist` while running
`complete-schema.sql` on an EXISTING database, your database was built by an
older schema generation whose tables (e.g. `support_plans`, `certificates`,
`lms_submissions`, `idcards`, `results.teacher_id`, `poll_votes.candidate_id`,
`profiles.role/status`, …) pre-date the hardening added in v12. RLS policies
validate their column references at creation time, so the run aborted.
v12.1 extends the drift-hardening block: every column referenced by any
policy / view / function / constraint / index is now force-added
(`ADD COLUMN IF NOT EXISTS`) before first use. Just re-run the updated
`complete-schema.sql` — it is idempotent and purely additive; nothing is
dropped from your database.
