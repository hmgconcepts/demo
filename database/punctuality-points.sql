-- ============================================================================
-- SCHOOL CONNECT — PUNCTUALITY POINTS ENGINE (v1, 2026-07-23)
-- ----------------------------------------------------------------------------
-- Rewards students who ARRIVE on time AND stay through closing:
--   check-in at/before the configurable deadline  AND
--   check-out at/after the configurable closing-window start
-- earns points each school day. Points accumulate per term and can be PUSHED
-- INTO THE STUDENTS' RESULTS (any report-card column — e.g. CA2) at the
-- school's discretion, exactly like CBT scores.
--
-- 100% ADD-ONLY and idempotent. Also ships inside complete-schema.sql from
-- v12.4 (Section 17) — run THIS file only on projects already on v12.x.
--
-- HOW IT FLOWS
--   checkin.html writes student_clock (clock_in / clock_out per date)
--   → compute_punctuality_awards(date) grades every checked student that day
--     (UPsert into punctuality_awards — re-running any day is safe and just
--     re-grades it, so late check-outs still earn their point afterwards)
--   → punctuality.html shows daily awards + term leaderboards
--   → sc_push_punctuality_to_results(term, session, column, class, range)
--     upserts per-student point totals into the Results table with
--     assessment_source='punctuality' and a DETERMINISTIC assessment_ref
--     (md5 → uuid), so re-pushing never duplicates — it updates.
-- ============================================================================

set search_path = public;

-- ── 1) CONFIG (single row, tuned by the school) ─────────────────────────────
create table if not exists public.punctuality_config (
  id int primary key default 1 check (id = 1),
  deadline time not null default '07:30:00',       -- check-in at/before = on time
  checkout_open time not null default '12:30:00',  -- check-out at/after = stayed through closing
  points_full numeric not null default 2,          -- points for a fully-punctual day
  points_partial numeric not null default 0,       -- points for on-time check-in WITHOUT a qualified check-out (0 = strict mode)
  require_checkout boolean not null default true,  -- when false, on-time check-in alone earns full points
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.punctuality_config (id) values (1) on conflict (id) do nothing;

-- ── 2) DAILY AWARDS ─────────────────────────────────────────────────────────
create table if not exists public.punctuality_awards (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  student_id_ref text not null default '', student_name text not null default '',
  class text not null default '',
  date date not null,
  checkin_at timestamptz, checkout_at timestamptz,
  points numeric not null default 0,
  rule text not null default 'none',  -- full | partial | late | no_checkout | config_disabled
  created_at timestamptz not null default now(),
  unique(student_id, date)
);
create index if not exists punctuality_awards_date_idx    on public.punctuality_awards (date);
create index if not exists punctuality_awards_class_idx   on public.punctuality_awards (class, date);
create index if not exists punctuality_awards_student_idx on public.punctuality_awards (student_id, date);

-- ── 2b) RESULTS PUSH COLUMNS (also repairs a latent v12.x gap) ──────────────
-- The Results-table push flow (this pack's AND the existing CBT → Report Card
-- one) writes student_name / student_id_ref / assessment_source /
-- assessment_ref and upserts ON CONFLICT (assessment_source, assessment_ref).
-- On FRESH v12.x installs those columns were only added by the legacy drift
-- block for OLD databases — brand-new installs lacked them, so both pushes
-- failed with 42703. Force-add them here; NULL refs in manual rows never
-- collide (Postgres treats NULLs as distinct).
alter table if exists public.results add column if not exists student_name text;
alter table if exists public.results add column if not exists student_id_ref text not null default '';
alter table if exists public.results add column if not exists assessment_source text not null default 'manual';
alter table if exists public.results add column if not exists assessment_ref uuid;
create unique index if not exists results_assessment_uidx on public.results (assessment_source, assessment_ref);

-- ── 3) DAILY COMPUTE — grade every checked student for one date ─────────────
create or replace function public.compute_punctuality_awards(p_date date default current_date, p_class text default '')
returns int language plpgsql security definer set search_path=public as $$
declare
  cfg record; awarded int := 0;
begin
  select * into cfg from public.punctuality_config where id = 1;
  if cfg is null then
    insert into public.punctuality_config (id) values (1) on conflict (id) do nothing returning * into cfg;
    if cfg is null then select * into cfg from public.punctuality_config where id = 1; end if;
  end if;

  -- Re-grade the day from student_clock (first clock-in, last clock-out). A
  -- row with points 0 is kept too, so staff can see exactly WHY no point.
  insert into public.punctuality_awards
    (student_id, student_id_ref, student_name, class, date, checkin_at, checkout_at, points, rule)
  select
    s.id, coalesce(s.admission_no,''), coalesce(s.full_name,''), coalesce(s.class,''),
    p_date, t.first_in, t.last_out,
    case
      when not cfg.enabled then 0
      when t.first_in::time <= cfg.deadline and (not cfg.require_checkout) then cfg.points_full
      when t.first_in::time <= cfg.deadline and t.last_out is not null and t.last_out::time >= cfg.checkout_open then cfg.points_full
      when t.first_in::time <= cfg.deadline then cfg.points_partial
      else 0
    end,
    case
      when not cfg.enabled then 'config_disabled'
      when t.first_in::time <= cfg.deadline and (not cfg.require_checkout) then 'full'
      when t.first_in::time <= cfg.deadline and t.last_out is not null and t.last_out::time >= cfg.checkout_open then 'full'
      when t.first_in::time <= cfg.deadline then 'no_checkout'
      else 'late'
    end
  from (
    select sc.student_id, min(sc.clock_in) as first_in, max(sc.clock_out) as last_out
      from public.student_clock sc
     where sc.date = p_date and sc.student_id is not null
     group by sc.student_id
  ) t
  join public.students s on s.id = t.student_id
  where (p_class = '' or s.class = p_class)
  on conflict (student_id, date) do update
    set checkin_at = excluded.checkin_at, checkout_at = excluded.checkout_at,
        points = excluded.points, rule = excluded.rule,
        student_id_ref = excluded.student_id_ref, student_name = excluded.student_name,
        class = excluded.class;

  select coalesce(sum(case when points > 0 then 1 else 0 end),0)::int into awarded
    from public.punctuality_awards
   where date = p_date and (p_class = '' or class = p_class);
  return awarded;
end $$;

-- ── 4) PUSH TERM POINTS INTO RESULTS (school's choice of column) ────────────
-- Mirrors the CBT → Report Card flow: one Results row per student carrying
-- their point total in the chosen column. assessment_ref is deterministic
-- (md5 → uuid), so re-pushing the same term/class/range UPDATES, never dupes.
create or replace function public.sc_push_punctuality_to_results(
  p_term text, p_session text, p_column text default 'ca2', p_class text default '',
  p_start date default null, p_end date default null, p_subject text default 'PUNCTUALITY')
returns int language plpgsql security definer set search_path=public as $$
declare
  saved int := 0; r record; ref uuid; col text := lower(trim(p_column));
begin
  -- Column must be a REAL numeric column on results (ca1/ca2/ca3/exam or any
  -- custom numeric column the report engine added).
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='results'
                    and column_name=col and data_type='numeric') then
    raise exception 'Punctuality push: "%" is not a numeric Results column. Use ca1/ca2/ca3/exam or a custom numeric report column.', col;
  end if;

  for r in
    select a.student_id,
           max(a.student_name) as student_name, max(a.student_id_ref) as student_id_ref,
           coalesce(nullif(p_class,''), max(a.class)) as class,
           sum(a.points) as points
      from public.punctuality_awards a
      join public.students s on s.id = a.student_id
     where (p_class = '' or a.class = p_class or s.class = p_class)
       and (p_start is null or a.date >= p_start)
       and (p_end   is null or a.date <= p_end)
     group by a.student_id
  loop
    ref := md5('punctuality|'||r.student_id::text||'|'||coalesce(p_term,'')||'|'||coalesce(p_session,'')||'|'||col||'|'||coalesce(nullif(p_class,''),r.class,''))::uuid;
    execute format(
      'insert into public.results (student_id, student_name, student_id_ref, subject, class, term, session, assessment_source, assessment_ref, %I)
       values ($1,$2,$3,$4,$5,$6,$7,''punctuality'',$8,$9)
       on conflict (assessment_source, assessment_ref)
       do update set %I = excluded.%I, student_name = excluded.student_name, class = excluded.class, term = excluded.term, session = excluded.session', col, col, col)
      using r.student_id, r.student_name, r.student_id_ref, p_subject, r.class, p_term, p_session, ref, r.points;
    saved := saved + 1;
  end loop;
  return saved;
end $$;

-- ── 5) RLS (mirrors student_clock: staff manage; student/parent read own) ───
alter table public.punctuality_config enable row level security;
alter table public.punctuality_awards enable row level security;

drop policy if exists "punctuality_config_read" on public.punctuality_config;
create policy "punctuality_config_read" on public.punctuality_config for select using (auth.role()='authenticated');
drop policy if exists "punctuality_config_write" on public.punctuality_config;
create policy "punctuality_config_write" on public.punctuality_config for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

drop policy if exists "punctuality_awards_read" on public.punctuality_awards;
create policy "punctuality_awards_read" on public.punctuality_awards for select using (
  public.is_staff(auth.uid()) or public.is_parent_of(auth.uid(), student_id)
  or exists (select 1 from public.students s where s.id = punctuality_awards.student_id and s.user_id = auth.uid()));
drop policy if exists "punctuality_awards_write" on public.punctuality_awards;
create policy "punctuality_awards_write" on public.punctuality_awards for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

grant execute on function public.compute_punctuality_awards(date, text) to authenticated;
grant execute on function public.sc_push_punctuality_to_results(text, text, text, text, date, date, text) to authenticated;

notify pgrst, 'reload schema';
select pg_notify('pgrst','reload schema');

analyze public.punctuality_awards;

select 'Punctuality Points engine installed ✅ (config + daily awards + term push into Results)' as status;
