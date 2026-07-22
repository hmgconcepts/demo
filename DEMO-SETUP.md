# Demo Deployment Guide — School Connect Demonstration College

This ZIP is a **DEMO build**: it lets prospective clients explore a complete,
fully-simulated school instantly — no sign-up or data entry needed.

## What is inside
- Everything a production School Connect ZIP contains.
- `database/demo-users.sql` — creates five ready-made guest accounts
  (Admin, Teacher, Parent, Student, Bursar — all @scdemo.school).
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
3. Run **database/demo-users.sql** once (creates the five guest accounts).
4. Run **database/demo-seed.sql** once (loads the simulated school).
5. Edit **assets/js/config.js**: paste your Supabase URL + anon key.
6. Host the folder anywhere free — Vercel / Netlify / GitHub Pages / Cloudflare Pages —
   and share the link with your prospect.

## Guest logins (also shown on the login page)
| Role | Email | Password |
|------|-------|----------|
| Admin | admin@scdemo.school | Demo#Admin1 |
| Teacher | teacher@scdemo.school | Demo#Teach1 |
| Parent | parent@scdemo.school | Demo#Parent1 |
| Student | student@scdemo.school | Demo#Study1 |
| Bursar | bursar@scdemo.school | Demo#Bursar1 |

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
