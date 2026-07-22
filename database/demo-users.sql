-- ============================================================================
-- SCHOOL CONNECT DEMO — GUEST ACCOUNTS  (run AFTER complete-schema.sql)
-- ----------------------------------------------------------------------------
-- Creates the five one-tap "Explore as Guest" accounts used by the demo
-- deployment (assets/js/demo.js reads these).  Passwords (shown publicly on
-- the demo login panel — this file is for DEMO USE ONLY, never production):
--   admin@scdemo.school   Demo#Admin1   → role: admin
--   teacher@scdemo.school Demo#Teach1   → role: teacher (linked staff record)
--   parent@scdemo.school  Demo#Parent1  → role: parent  (linked to 2 demo kids)
--   student@scdemo.school Demo#Study1   → role: student (linked student record)
--   bursar@scdemo.school  Demo#Bursar1  → role: bursar
-- Idempotent: re-running only fills what is missing.
-- ============================================================================

create extension if not exists pgcrypto;

-- Demo account catalogue (fixed UUIDs make linking in demo-seed.sql simple)
--   a1 admin · a2 teacher · a3 parent · a4 student · a5 bursar
do $$
declare
  -- flat rows: uuid, email, password, full_name  (5 rows × 4 fields)
  accounts constant text[] := array[
    'd3000000-0000-4000-8000-0000000000a1','admin@scdemo.school','Demo#Admin1','Demo Administrator',
    'd3000000-0000-4000-8000-0000000000a2','teacher@scdemo.school','Demo#Teach1','Funke Alabi',
    'd3000000-0000-4000-8000-0000000000a3','parent@scdemo.school','Demo#Parent1','Mr. Adewale Okafor',
    'd3000000-0000-4000-8000-0000000000a4','student@scdemo.school','Demo#Study1','Adanna Okafor',
    'd3000000-0000-4000-8000-0000000000a5','bursar@scdemo.school','Demo#Bursar1','Demo Bursar'
  ];
  roles constant text[] := array['admin','teacher','parent','student','bursar'];
  a text[4]; i int; b int;
begin
  for i in 1 .. 5 loop
    b := (i-1)*4;
    a := array[accounts[b+1], accounts[b+2], accounts[b+3], accounts[b+4]];
    -- 1) auth.users row (skipped when the email already exists)
    if not exists (select 1 from auth.users where email = a[2]) then
      begin
        insert into auth.users (
          instance_id, id, aud, role, email, encrypted_password,
          email_confirmed_at, created_at, updated_at,
          raw_app_meta_data, raw_user_meta_data
        ) values (
          '00000000-0000-0000-0000-000000000000', a[1]::uuid, 'authenticated', 'authenticated', a[2],
          crypt(a[3], gen_salt('bf')), now(), now(), now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('full_name', a[4], 'demo', true)
        );
      exception when others then
        raise notice 'demo user % insert skipped: %', a[2], sqlerrm;
      end;
      begin
        insert into auth.identities (
          id, user_id, provider_id, provider, identity_data,
          last_sign_in_at, created_at, updated_at
        ) values (
          a[1]::uuid, a[1]::uuid, a[1], 'email',
          jsonb_build_object('sub', a[1], 'email', a[2]),
          now(), now(), now()
        );
      exception when others then
        raise notice 'demo identity % skipped: %', a[2], sqlerrm;
      end;
    end if;
    -- 2) portal profile (role + approved status drive the whole UI)
    insert into public.profiles (id, email, full_name, role, status, phone, campus)
    values (a[1]::uuid, a[2], a[4], roles[i], 'approved', '+234 810 000 000'||i, 'Main Campus')
    on conflict (id) do nothing;
  end loop;
end $$;

select 'Demo guest accounts ready ✅  (admin / teacher / parent / student / bursar @scdemo.school)' as status;
