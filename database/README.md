# Database installation — School Connect v12.1

Run only the root `complete-schema.sql` once in the Supabase SQL Editor. It is
self-contained, idempotent and purely additive: safe to run on a brand-new
project AND on the existing demo database. It repairs missing tables, missing
columns (extended 42703 drift-hardening), missing unique keys, and reloads the
PostgREST schema cache at the end. No other SQL file is required.
