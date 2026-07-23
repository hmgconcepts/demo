# Demo Deployment Guide — School Connect Demonstration College

This ZIP is a **DEMO build**: it lets prospective clients explore a complete,
fully-simulated school instantly — no sign-up or data entry needed.

## What is inside
- Everything a production School Connect ZIP contains.
- `database/demo-users.sql` — creates five ready-made guest accounts
  (Admin, Teacher, Parent, Student, Bursar — all @gmail.com; see the note
  below on why resolvable domains are required).
- `database/demo-seed.sql` — a complete simulated school: 18 students,
  8 staff, parent links, fee structures & payments, attendance, check-ins,
  results + report-card columns/scores/comments/traits, a published CBT exam
  with real questions + submissions, polls, announcements, gallery, diary,
  conduct, health, assignments, lesson plans, survey, leave, visitors,
  helpdesk, hostel, staff clock-ins, timetable data, shop products and ID cards.
- `assets/js/demo.js` — renders the one-tap "Explore as Guest" panel on the
  login page and the slim demo ribbon everywhere else.

## Deploy in 6 steps (~10 minutes, 100% free tier)
1. Create a free Supabase project → open its **SQL Editor**.
2. Run **database/complete-schema.sql** once (self-contained, idempotent).
3. Create the five guest accounts — **Method B (Dashboard, RECOMMENDED):**
   Authentication → Users → **Add user** × 5 with the emails + passwords below
   and "Auto Confirm User" ON. **Method A (SQL):** run
   **database/demo-users.sql** v5 once — it adopts the dashboard accounts if
   they already exist (or creates them itself) and force-sets the approved
   roles. Either is enough — demo-seed links by EMAIL, so random dashboard
   UUIDs are perfectly fine. Afterwards run demo-users.sql once in any case:
   it fixes the "Account pending approval" screen (the signup trigger defaults
   every new profile to *pending student*).
4. Run **database/demo-seed.sql** once (loads the simulated school; works even
   with zero accounts — links appear once accounts exist).
5. Edit **assets/js/config.js**: paste your Supabase URL + anon key.
6. Host the folder anywhere free — Vercel / Netlify / GitHub Pages / Cloudflare Pages —
   and share the link with your prospect.

> Why @gmail.com: the newest hosted Supabase auth (GoTrue v2.193+) validates
> email DOMAINS on every auth path — the signup API, Dashboard "Add user"
> ("Database error checking email") and even internal queries
> (500 "Database error querying schema"). Non-resolvable domains such as
> scdemo.school are rejected everywhere; gmail.com works. Keep the addresses
> pre-confirmed so no email is ever sent to the real owners (both methods
> above pre-confirm automatically; tell prospects not to use "Forgot password"
> on the demo).

## Guest logins (also shown on the login page)
| Role | Email | Password |
|------|-------|----------|
| Admin | admin@gmail.com | Demo#Admin1 |
| Teacher | teacher@gmail.com | Demo#Teach1 |
| Parent | parent@gmail.com | Demo#Parent1 |
| Student | student@gmail.com | Demo#Study1 |
| Bursar | bursar@gmail.com | Demo#Bursar1 |

## Troubleshooting: "Demo login failed"
The login panel now shows the *real* error with a matching fix. In short:
| Error text | Cause → Fix |
|---|---|
| `Database error querying schema` / `unexpected_failure` (500) | The project's auth version rejects SQL-created rows → use **Method B** (Dashboard → Add user, auto-confirm ON) with the @gmail.com accounts, then re-run demo-seed.sql. demo-users.sql v5 adopts those accounts and matches the modern hosted auth shape (instance_id NULL). |
| `duplicate key value violates unique constraint "users_pkey"` (23505) when running demo-users.sql | Leftover accounts from demo-users.sql v1–v3 sitting on the fixed demo UUIDs (old @scdemo.school emails) → **just run demo-users.sql v5**: it MIGRATES those legacy rows in place (no delete, no collision) and finishes green. Never edit the five fixed UUIDs by hand. |
| `Invalid login credentials` | The five accounts are missing or have different passwords → (re)run **demo-users.sql v5** in the SQL Editor of the **same project** whose URL is in `assets/js/config.js`. v5 resets passwords and **fails visibly** if anything is wrong. |
| `Email not confirmed` | → re-run demo-users.sql (it pre-confirms emails), or Auth → Providers → Email → **turn off "Confirm email"**. |
| `Failed to fetch` / network | → wrong SUPABASE_URL / anon key in `assets/js/config.js`. |
| project paused / 503 | → free projects pause after ~7 idle days: Supabase dashboard → **Restore project**. |

Quick health check (SQL Editor — should return 5 rows, all `true`):
```sql
select u.email, (u.email_confirmed_at is not null) as confirmed,
       (i.user_id is not null) as has_identity, p.role
  from auth.users u
  left join auth.identities i on i.user_id=u.id and i.provider='email'
  left join public.profiles p on p.id=u.id
 where u.email like '%@gmail.com' order by u.email;
```

## Refreshing / resetting the demo
The three SQL files are idempotent — re-running demo-seed.sql only tops up
what is missing (it never deletes rows visitors created). To reset completely:
Supabase → **Table Editor** → delete rows from the transactional tables
(students, staff, results, fee_payments, attendance, cbt_results, …) and
re-run demo-seed.sql.

## Notes for HMG
- Demo data is synthetic; banners remind visitors not to enter real data.
- The demo build runs the same license engine as production; demo deployments
  are generated with a **lifetime demo license** so they never lock.
- All guest accounts are ordinary rows in `auth.users` + `profiles`; you can
  suspend them any time on the Approvals page.
