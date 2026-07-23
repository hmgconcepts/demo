-- ============================================================================
-- SCHOOL CONNECT DEMO — GUEST ACCOUNTS  v4  (run AFTER complete-schema.sql)
-- ----------------------------------------------------------------------------
-- Creates / repairs / ADOPTS the five one-tap "Explore as Guest" accounts used
-- by the demo deployment (assets/js/demo.js).  Passwords (public on the demo
-- login panel — DEMO USE ONLY, never production):
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
-- v4 KEY BEHAVIOUR — ADOPT, NEVER REPLACE:
--   • If an account already exists for a demo email (e.g. you created it via
--     Dashboard "Add user" — the RECOMMENDED method on the newest projects),
--     we keep that native GoTrue row and its id, only resetting its password,
--     confirming the email and fixing its identity + profile. Deleting
--     GoTrue-created users is precisely what newer projects handle badly.
--   • If no account exists, we create one (SQL path, works on older projects
--     and on current ones for valid domains), with hosted-parity shape.
--   • demo-seed.sql links everything BY EMAIL — random Dashboard UUIDs are
--     perfectly fine.
--   • Profiles are UPSERTED to the right role + 'approved' — this is also the
--     fix for the "Account pending approval" screen after a Dashboard-created
--     login (the handle_new_user trigger defaults everyone to pending student).
-- FAILS LOUDLY: ends with a visible ERROR if any account/identity/profile is
-- missing. Idempotent: re-running is always safe and self-heals.
--
-- ETIQUETTE NOTE: these gmail addresses may belong to real people. Keep them
-- PRE-CONFIRMED (this script + Dashboard "Auto Confirm" do exactly that) so no
-- confirmation mail is ever sent, and tell prospects not to use "Forgot
-- password" on the demo (it would mail the real address owners).
-- ============================================================================

-- pgcrypto (crypt/gen_salt) is installed in the `extensions` schema on hosted
-- Supabase. Make every schema visible for THIS run so unqualified calls resolve
-- regardless of where the extension lives.
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
  a text[4]; i int; b int; v_id uuid; errs text := '';
begin
  for i in 1 .. 5 loop
    b := (i-1)*4;
    a := array[accounts[b+1], accounts[b+2], accounts[b+3], accounts[b+4]];

    -- 1) RESOLVE the account by email — adopt native rows, create if absent.
    select id into v_id from auth.users where email = a[2] limit 1;

    if v_id is null then
      -- SQL creation path (a[1] is a fixed uuid so demo data links stay tidy).
      -- NB: role is placed in raw_user_meta_data because the schema's
      -- handle_new_user() trigger auto-creates a profiles row from it.
      v_id := a[1]::uuid;
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
    else
      raise notice 'demo: adopting existing account % (id %)', a[2], v_id;
    end if;

    -- 2) SELF-HEAL credentials + hosted-parity shape (both paths, every run):
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
    --    UPSERT — repairs trigger-created rows (pending student) and any
    --    earlier partial state.
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
    if not exists (select 1 from auth.users u where u.email = a[2] and u.email_confirmed_at is not null) then
      errs := errs || ' user:' || a[2];
    elsif not exists (select 1 from auth.identities i join auth.users u on u.id = i.user_id
                       where u.email = a[2] and i.provider = 'email') then
      errs := errs || ' identity:' || a[2];
    elsif not exists (select 1 from public.profiles p join auth.users u on u.id = p.id
                       where u.email = a[2] and p.role = roles_c[i] and p.status = 'approved') then
      errs := errs || ' profile:' || a[2];
    end if;
  end loop;

  if errs <> '' then
    raise exception 'DEMO-USERS FAILED for: %. See the notices above for the cause. Fix the cause and re-run this file — or create the five users via Dashboard → Authentication → Users → "Add user" (Auto Confirm ON) and re-run.', errs;
  end if;

  raise notice 'demo: all 5 guest accounts verified (auth + identity + approved profile) ✔';
end $$;

-- Visible summary in the SQL Editor result grid — you should see the 5 emails,
-- all confirmed, with identity + approved profile and the right role:
select u.email, (u.email_confirmed_at is not null) as email_confirmed,
       (i.user_id is not null) as has_identity, p.role, p.status
  from auth.users u
  left join auth.identities i on i.user_id = u.id and i.provider = 'email'
  left join public.profiles p on p.id = u.id
 where u.email like '%@gmail.com'
 order by u.email;
