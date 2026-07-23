-- ============================================================================
-- SCHOOL CONNECT DEMO — GUEST ACCOUNTS  v5  (run AFTER complete-schema.sql)
-- ----------------------------------------------------------------------------
-- Creates / repairs / ADOPTS / MIGRATES the five one-tap "Explore as Guest"
-- accounts used by the demo deployment (assets/js/demo.js).
-- Passwords (public on the demo login panel — DEMO USE ONLY, never production):
--   admin@gmail.com   Demo#Admin1   → role: admin
--   teacher@gmail.com Demo#Teach1   → role: teacher (linked staff record)
--   parent@gmail.com  Demo#Parent1  → role: parent  (linked to 2 demo kids)
--   student@gmail.com Demo#Study1   → role: student (linked student record)
--   bursar@gmail.com  Demo#Bursar1  → role: bursar
--
-- WHY @gmail.com (v4, 2026-07-23): Supabase's newest auth (GoTrue v2.193+)
-- validates email DOMAINS and rejects non-resolvable ones (@scdemo.school) on
-- the signup API, in Dashboard "Add user" ("Database error checking email")
-- and even when its internal queries touch SQL-inserted rows (500
-- "Database error querying schema"). @gmail.com passes everywhere (verified
-- live), so demo accounts work on every project generation.
--
-- v5 FIX (2026-07-23) — ERROR 23505 users_pkey duplicate key:
--   "duplicate key value violates unique constraint \"users_pkey\"
--    Key (id)=(d3000000-...-a2) already exists."
--   CAUSE: an older version of this script (v1–v3) already created demo
--   accounts at the five FIXED UUIDs below — with the OLD @scdemo.school
--   addresses. v4 looked accounts up by email only, found no gmail row, and
--   tried to INSERT at an occupied UUID.
--   FIX in v5: for every account we now resolve in THREE steps:
--     1) email match (any id)        → ADOPT that row (Dashboard-created or
--                                      previously migrated — the recommended
--                                      state on the newest projects);
--     2) fixed-UUID row with a NON-gmail (legacy) email → MIGRATE it in place
--        (UPDATE email + identity_data; never DELETE — deleting GoTrue rows
--        is what newer projects handle badly);
--     3) fixed UUID occupied by one of our OTHER gmail accounts (shouldn't
--        happen, but never crash) → create at a fresh random UUID instead.
--   Result: v5 turns ANY prior state (v1–v3 leftovers, half-finished v4 runs,
--   Dashboard-created users, or a mix of all three) into the same clean,
--   fully-working end state — with ZERO 23505 errors.
--
-- KEY BEHAVIOUR — ADOPT / MIGRATE, NEVER REPLACE:
--   • Dashboard "Add user" accounts are kept with their native GoTrue ids;
--     we only reset the password, confirm the email, fix identity + profile.
--   • Profiles are UPSERTED to the right role + 'approved' — the fix for the
--     "Account pending approval" screen after a Dashboard-created login
--     (handle_new_user() defaults everyone to pending student).
--   • demo-seed.sql links everything BY EMAIL — random Dashboard UUIDs are
--     perfectly fine.
-- FAILS LOUDLY: ends with a visible ERROR if any account/identity/profile is
-- missing. Idempotent: re-running is always safe and self-heals.
--
-- ETIQUETTE NOTE: these gmail addresses may belong to real people. Keep them
-- PRE-CONFIRMED (this script + Dashboard "Auto Confirm" do exactly that) so
-- no confirmation mail is ever sent, and tell prospects not to use "Forgot
-- password" on the demo (it would mail the real address owners).
-- ============================================================================

-- pgcrypto (crypt/gen_salt) lives in the `extensions` schema on hosted
-- Supabase; make every schema visible for THIS run so calls resolve wherever
-- the extension is installed.
set search_path = public, extensions, auth;

create extension if not exists pgcrypto;

do $$
declare
  accounts constant text[] := array[
    'd3000000-0000-4000-8000-0000000000a1','admin@gmail.com','Demo#Admin1','Demo Administrator',
    'd3000000-0000-4000-8000-0000000000a2','teacher@gmail.com','Demo#Teach1','Funke Alabi',
    'd3000000-0000-4000-8000-0000000000a3','parent@gmail.com','Demo#Parent1','Mr. Adewale Okafor',
    'd3000000-0000-4000-8000-0000000000a4','student@gmail.com','Demo#Study1','Adanna Okafor',
    'd3000000-0000-4000-8000-0000000000a5','bursar@gmail.com','Demo#Bursar1','Demo Bursar'
  ];
  roles_c constant text[] := array['admin','teacher','parent','student','bursar'];
  a text[4]; i int; b int; v_id uuid; v_occ text; errs text := '';
begin
  for i in 1 .. 5 loop
    b := (i-1)*4;
    a := array[accounts[b+1], accounts[b+2], accounts[b+3], accounts[b+4]];

    -- 1) RESOLVE, in three steps -------------------------------------------
    select id into v_id from auth.users where lower(email) = lower(a[2]) limit 1;

    if v_id is not null then
      -- STEP 1: an account with this exact email exists → ADOPT it.
      raise notice 'demo: adopting existing account % (id %)', a[2], v_id;

    else
      v_id := a[1]::uuid;
      select email into v_occ from auth.users where id = v_id;

      if found and v_occ like '%@gmail.com' then
        -- STEP 3 guard: fixed UUID taken by one of our OTHER demo gmail
        -- accounts → create at a fresh UUID rather than touching it.
        v_id := gen_random_uuid();
        insert into auth.users (
          instance_id, id, aud, role, email, encrypted_password,
          email_confirmed_at, created_at, updated_at,
          raw_app_meta_data, raw_user_meta_data
        ) values (
          null, v_id, 'authenticated', 'authenticated', a[2],
          crypt(a[3], gen_salt('bf')), now(), now(), now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('full_name', a[4], 'demo', true, 'role', roles_c[i])
        );
        raise notice 'demo: created account % (fresh id — fixed id belonged to %)', a[2], v_occ;

      elsif found then
        -- STEP 2: fixed UUID occupied by a LEGACY row from demo-users.sql
        -- v1–v3 (e.g. teacher@scdemo.school — the exact 23505 users_pkey
        -- collision reported live). MIGRATE it in place: UPDATE, never
        -- DELETE. The profiles row at the same id is healed in step 4.
        update auth.users
           set email = a[2],
               instance_id = null,
               aud = 'authenticated', role = 'authenticated',
               raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
               raw_user_meta_data = jsonb_build_object('full_name', a[4], 'demo', true, 'role', roles_c[i]),
               updated_at = now()
         where id = v_id;
        -- Repoint the legacy identity at the new email. identities.email is a
        -- GENERATED column (from identity_data->>'email') on modern GoTrue, so
        -- updating identity_data keeps everything consistent automatically.
        update auth.identities
           set identity_data = jsonb_build_object('sub', v_id::text, 'email', a[2], 'email_verified', true, 'phone_verified', false),
               updated_at = now()
         where user_id = v_id and provider = 'email';
        raise notice 'demo: migrated legacy account % → % (kept id %)', v_occ, a[2], v_id;

      else
        -- STEP 2b: nobody holds the email or the fixed UUID → fresh create.
        -- NB: role goes in raw_user_meta_data because the schema's
        -- handle_new_user() trigger auto-creates a profiles row from it.
        insert into auth.users (
          instance_id, id, aud, role, email, encrypted_password,
          email_confirmed_at, created_at, updated_at,
          raw_app_meta_data, raw_user_meta_data
        ) values (
          null, v_id, 'authenticated', 'authenticated', a[2],
          crypt(a[3], gen_salt('bf')), now(), now(), now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('full_name', a[4], 'demo', true, 'role', roles_c[i])
        );
        raise notice 'demo: created account % (fixed id)', a[2];
      end if;
    end if;

    -- 2) SELF-HEAL credentials + hosted-parity shape (every path, every run):
    --    correct password, confirmed email, instance_id NULL (modern shape;
    --    older projects accept NULL too).
    update auth.users
       set encrypted_password = crypt(a[3], gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           instance_id = null,
           aud = 'authenticated', role = 'authenticated',
           updated_at = now()
     where id = v_id;

    -- 3) auth.identities (GoTrue requires a matching email identity to log in).
    --    Modern Supabase: unique(provider_id, provider) → upsert. Older shapes:
    --    plain fallback insert (still verified by the end-check below).
    begin
      insert into auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
      ) values (
        v_id, v_id, v_id::text, 'email',
        jsonb_build_object('sub', v_id::text, 'email', a[2], 'email_verified', true, 'phone_verified', false),
        now(), now(), now()
      )
      on conflict (provider_id, provider) do update
         set user_id = excluded.user_id,
             identity_data = excluded.identity_data,
             updated_at = now();
    exception when others then
      insert into auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
      ) values (
        v_id, v_id, v_id::text, 'email',
        jsonb_build_object('sub', v_id::text, 'email', a[2], 'email_verified', true, 'phone_verified', false),
        now(), now(), now()
      )
      on conflict do nothing;
    end;

    -- 4) portal profile (role + approved status drive the whole UI).
    --    UPSERT — repairs trigger-created rows (pending student), legacy rows
    --    whose email changed during a migrate, and any earlier partial state.
    insert into public.profiles (id, email, full_name, role, status, phone, campus)
    values (v_id, a[2], a[4], roles_c[i], 'approved', '+234 810 000 000'||i, 'Main Campus')
    on conflict (id) do update
       set role = excluded.role, status = 'approved',
           full_name = excluded.full_name, email = excluded.email;
  end loop;

  -- 5) FAIL LOUDLY: verify every account end-to-end (user + identity + profile)
  for i in 1 .. 5 loop
    b := (i-1)*4;
    a := array[accounts[b+1], accounts[b+2], accounts[b+3], accounts[b+4]];
    if not exists (select 1 from auth.users u where lower(u.email) = lower(a[2]) and u.email_confirmed_at is not null) then
      errs := errs || ' user:' || a[2];
    elsif not exists (select 1 from auth.identities i join auth.users u on u.id = i.user_id
                       where lower(u.email) = lower(a[2]) and i.provider = 'email') then
      errs := errs || ' identity:' || a[2];
    elsif not exists (select 1 from public.profiles p join auth.users u on u.id = p.id
                       where lower(u.email) = lower(a[2]) and p.role = roles_c[i] and p.status = 'approved') then
      errs := errs || ' profile:' || a[2];
    end if;
  end loop;

  if errs <> '' then
    raise exception 'DEMO-USERS FAILED for: %. See the notices above for the cause. Fix the cause and re-run this file — or create the five users via Dashboard → Authentication → Users → "Add user" (Auto Confirm ON) and re-run.', errs;
  end if;

  raise notice 'demo: all 5 guest accounts verified (auth + identity + approved profile) ✔';
end $$;

-- Visible summary in the SQL Editor result grid — the 5 demo emails, all
-- confirmed, with identity + approved profile and the right role:
select u.email, (u.email_confirmed_at is not null) as email_confirmed,
       (i.user_id is not null) as has_identity, p.role, p.status
  from auth.users u
  left join auth.identities i on i.user_id = u.id and i.provider = 'email'
  left join public.profiles p on p.id = u.id
 where lower(u.email) in ('admin@gmail.com','teacher@gmail.com','parent@gmail.com','student@gmail.com','bursar@gmail.com')
 order by u.email;

-- ────────────────────────────────────────────────────────────────────────────
-- OPTIONAL TIDY-UP (safe to skip): leftover login rows from demo-users.sql
-- v1–v3 use the old @scdemo.school addresses and can NEVER sign in on the
-- newest Supabase auth. They harm nothing (v5 simply ignores or migrates
-- them), but if you want them gone, uncomment BOTH lines and run this file:
--   delete from public.profiles where email like '%@scdemo.school';
--   delete from auth.users where email like '%@scdemo.school';
-- (auth.identities follows by ON DELETE CASCADE; profiles first in case your
--  project has no cascade on profiles.id.)
-- ────────────────────────────────────────────────────────────────────────────
