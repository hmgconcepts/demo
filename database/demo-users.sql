-- ============================================================================
-- SCHOOL CONNECT DEMO — GUEST ACCOUNTS  v3  (run AFTER complete-schema.sql)
-- ----------------------------------------------------------------------------
-- Creates / repairs the five one-tap "Explore as Guest" accounts used by the
-- demo deployment (assets/js/demo.js).  Passwords (public on the demo login
-- panel — DEMO USE ONLY, never production):
--   admin@scdemo.school   Demo#Admin1   → role: admin
--   teacher@scdemo.school Demo#Teach1   → role: teacher (linked staff record)
--   parent@scdemo.school  Demo#Parent1  → role: parent  (linked to 2 demo kids)
--   student@scdemo.school Demo#Study1   → role: student (linked student record)
--   bursar@scdemo.school  Demo#Bursar1  → role: bursar
--
-- v3 (2026-07-23) — adds hosted-Supabase auth-row parity:
--   • instance_id is NULL (the shape GoTrue writes on current hosted projects;
--     older/self-hosted projects also accept NULL — the zero-uuid era is over).
--   • NOTE: on the newest hosted projects the public *signup* API may reject
--     @scdemo.school (domain validation) — Dashboard "Add user" and this SQL are
--     NOT affected and remain the supported way to create demo accounts.
--
-- v2 (2026-07-22) — hardened against every silent failure seen in the field:
--   • search_path set explicitly (pgcrypto lives in the `extensions` schema on
--     Supabase — without this, crypt()/gen_salt() can fail unnoticed).
--   • FAILS LOUDLY: if any account/identity/profile is missing at the end, the
--     script raises a visible ERROR telling you exactly what is missing —
--     successes are never confused with failures again.
--   • SELF-HEALING: re-running always resets the demo passwords, (re)confirms
--     the emails, and inserts any missing auth.identities rows — so it repairs
--     accounts created by earlier partial runs or by the Auth dashboard.
--   • If a stray account with a demo email exists under a different user id,
--     it is replaced with the fixed-id demo account so every link in
--     demo-seed.sql (staff/student/parent user_id) stays valid.
-- Idempotent: re-running is always safe.
-- ============================================================================

-- pgcrypto (crypt/gen_salt) is installed in the `extensions` schema on hosted
-- Supabase. Make every schema visible for THIS run so unqualified calls resolve
-- regardless of where the extension lives.
set search_path = public, extensions, auth;

create extension if not exists pgcrypto;

do $$
declare
  accounts constant text[] := array[
    'd3000000-0000-4000-8000-0000000000a1','admin@scdemo.school','Demo#Admin1','Demo Administrator',
    'd3000000-0000-4000-8000-0000000000a2','teacher@scdemo.school','Demo#Teach1','Funke Alabi',
    'd3000000-0000-4000-8000-0000000000a3','parent@scdemo.school','Demo#Parent1','Mr. Adewale Okafor',
    'd3000000-0000-4000-8000-0000000000a4','student@scdemo.school','Demo#Study1','Adanna Okafor',
    'd3000000-0000-4000-8000-0000000000a5','bursar@scdemo.school','Demo#Bursar1','Demo Bursar'
  ];
  roles_c constant text[] := array['admin','teacher','parent','student','bursar'];
  a text[4]; i int; b int; stray uuid; errs text := '';
begin
  for i in 1 .. 5 loop
    b := (i-1)*4;
    a := array[accounts[b+1], accounts[b+2], accounts[b+3], accounts[b+4]];

    -- 0) Replace any stray account with the same email but a different id
    --    (e.g. someone signed up via the site first). Deleting cascades to its
    --    identity + profile; the fixed-id account is (re)created below so all
    --    demo-seed.sql user_id links stay valid.
    select id into stray from auth.users where email = a[2] and id <> a[1]::uuid limit 1;
    if stray is not null then
      delete from auth.users where id = stray;
      raise notice 'demo: replaced stray account % (%) — links need the fixed demo id', a[2], stray;
    end if;

    -- 1) auth.users (create if missing). NB: role is also placed in
    -- raw_user_meta_data because the schema's handle_new_user() trigger
    -- auto-creates a profiles row from it on auth.users insert — without it
    -- every account would be created as a *student*.
    if not exists (select 1 from auth.users where id = a[1]::uuid) then
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data
      ) values (
        null, a[1]::uuid, 'authenticated', 'authenticated', a[2],
        crypt(a[3], gen_salt('bf')), now(), now(), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', a[4], 'demo', true, 'role', roles_c[i])
      );
    end if;

    -- 2) SELF-HEAL credentials + shape: correct password, confirmed email and
    --    the hosted-parity instance_id (NULL), every run.
    update auth.users
       set encrypted_password = crypt(a[3], gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           instance_id = null,
           aud = 'authenticated', role = 'authenticated',
           updated_at = now()
     where id = a[1]::uuid;

    -- 3) auth.identities (GoTrue requires a matching email identity to log in).
    --    Modern Supabase: unique(provider_id, provider) → upsert. Older shapes:
    --    plain fallback insert (still verified by the end-check below).
    begin
      insert into auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
      ) values (
        a[1]::uuid, a[1]::uuid, a[1]::text, 'email',
        jsonb_build_object('sub', a[1], 'email', a[2], 'email_verified', true, 'phone_verified', false),
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
        a[1]::uuid, a[1]::uuid, a[1]::text, 'email',
        jsonb_build_object('sub', a[1], 'email', a[2], 'email_verified', true, 'phone_verified', false),
        now(), now(), now()
      )
      on conflict do nothing;
    end;

    -- 4) portal profile (role + approved status drive the whole UI).
    --    UPSERT — repairs rows pre-created by the handle_new_user() trigger
    --    or by earlier partial runs.
    insert into public.profiles (id, email, full_name, role, status, phone, campus)
    values (a[1]::uuid, a[2], a[4], roles_c[i], 'approved', '+234 810 000 000'||i, 'Main Campus')
    on conflict (id) do update
       set role = excluded.role, status = 'approved',
           full_name = excluded.full_name, email = excluded.email;
  end loop;

  -- 5) FAIL LOUDLY: verify every account end-to-end (user + identity + profile)
  for i in 1 .. 5 loop
    b := (i-1)*4;
    a := array[accounts[b+1], accounts[b+2], accounts[b+3], accounts[b+4]];
    if not exists (select 1 from auth.users where id = a[1]::uuid and email_confirmed_at is not null) then
      errs := errs || ' user:' || a[2];
    elsif not exists (select 1 from auth.identities where user_id = a[1]::uuid and provider = 'email') then
      errs := errs || ' identity:' || a[2];
    elsif not exists (select 1 from public.profiles where id = a[1]::uuid) then
      errs := errs || ' profile:' || a[2];
    end if;
  end loop;

  if errs <> '' then
    raise exception 'DEMO-USERS FAILED for: %. See the notices above for the cause (commonly: crypt()/gen_salt() not on search_path, or a non-standard auth schema). Fix the cause and re-run this file.', errs;
  end if;

  raise notice 'demo: all 5 guest accounts verified (auth + identity + profile) ✔';
end $$;

-- Visible summary in the SQL Editor result grid — you should see the 5 emails:
select u.email, (u.email_confirmed_at is not null) as email_confirmed,
       (i.user_id is not null) as has_identity, (p.role is not null) as has_profile, p.role
  from auth.users u
  left join auth.identities i on i.user_id = u.id and i.provider = 'email'
  left join public.profiles p on p.id = u.id
 where u.email like '%@scdemo.school'
 order by u.email;
