# CBT & Report Card Guide — School Connect Gen v8

## CBT (Computer-Based Testing)
- Engine: `assets/js/cbt-engine.js` (17 question types, anti-cheat config, instant scoring, certificate codes).
- Schema: `database/cbt-schema.sql` (includes `cbt_get_public_exam` answer-stripping RPC for students).
- Pages: `assets/templates/pages/cbt.html`, `cbt-exam.html`, `cbt-multi.html`, `cbt-prompts.html`, `entrance.html`.
- Question import: CSV upload (see `database/sample-question-bank.csv` and `database/sample-questions.csv`).
- Anonymous/entrance mode: guests can sit entrance exams; results, certificates and admission letters are generated instantly (single + bulk).

## Report Cards
- Engine: `assets/js/report-engine.js` — report card, broadsheet and scoresheet outputs.
- Schema: `database/reportcard-schema.sql` (includes `cbt_push_to_reportcard` to export CBT scores into results).
- Page: `assets/templates/pages/report-cards.html` — branded, printable, includes digital-library reading marks.

## Flow
1. Teacher creates exam (CBT page) → students take it (cbt-exam) →
2. Scores pushed to results via `cbt_push_to_reportcard` →
3. Report cards printed / broadcast to parents (WhatsApp / email / SMS).
