# Moving off Supabase — everything that has to change

Inventory taken 5 Nov 2026 across the seven repos in this workspace plus the two Claude routines. One Supabase project is used everywhere: `ugiurxkbbuhtvbehpkvb.supabase.co`. Nothing is Supabase-specific in `hyperframes-ioc`.

Supabase is doing five different jobs today. Each needs a replacement, and the code below is tied to it.

| Job Supabase does today | What depends on it |
|---|---|
| **Postgres database** (tables below) | every edge function, dashboards, coach app, closer workspace, course bot, Note 2 routine |
| **Edge Functions** (Deno) | `dash-api`, `ops-sheet-refresh`, `client-report-draft`, `coach-api`, `coach-daily`, `coach-profile`, `coach-plan-public`, `closer-api`, plus ones not in these repos: `wa-group-ingest`, `course-sync`, `asana-client-edit`, `google-connect` |
| **Auth** (Google sign-in, PKCE, `verify_jwt`) | dashboards site, coach app site |
| **pg_cron schedules** | `coach-daily` 8:00 am IST, `coach-profile-nightly` 2:00 am IST, hourly Fathom → `meetings` sync |
| **Supabase MCP connector** (`execute_sql`) | Note 2 routine, dashboards `ads.html` / `ad-table.html` / `fulfilment.html` |

---

## 1. Front ends (hard-coded project URL and publishable key)

| File | What to change |
|---|---|
| `ioc-dashboards/site/index.html` lines 105–111, 143–145 | `supabase-js` CDN script, `SB_URL`, `SB_KEY`, `createClient` with Google PKCE auth, `/functions/v1/dash-api` and `/functions/v1/ops-sheet-refresh` URLs, the `execute_sql` passthrough |
| `ioc-dashboards/site/ads.html` ~789, `ad-table.html` ~824, `fulfilment.html` 751, 1065, 1089 | call the Supabase MCP tool `execute_sql` with `project_id = ugiurxkbbuhtvbehpkvb` directly |
| `ioc-dashboards/site/attention.html`, `closers.html`, `content.html`, `ops.html`, `sw.js` | one Supabase mention each (comments or the shared client); re-check after `index.html` changes |
| `ioc-ai-coach-app/site/index.html` lines 10, 177–179, 213 | CDN script, `SUPABASE_URL`, publishable key `sb_publishable_…`, Google PKCE sign-in, `coach-api` call with `forceFunctionRegion=ap-northeast-2` |
| `ioc-ai-coach-app/site/p.html` line 43 | `coach-plan-public` URL |
| `ioc-closer-workspace/app.js` line 2 | `closer-api` URL; the Slack-DM login code flow (`ws_login_codes`, `ws_sessions`) lives behind it |

## 2. Edge functions in these repos (Deno; all read `SUPABASE_URL` + service key)

| Function | Repo path | Supabase-specific bits |
|---|---|---|
| `dash-api` | `ioc-dashboards/supabase/dash-api/index.ts` | direct Postgres via `SUPABASE_DB_URL`; `verify_jwt`; calls `asana-client-edit` and other functions by `${SUPABASE_URL}/functions/v1/…` with `x-sync-secret`; Google SA key |
| `ops-sheet-refresh` | `ioc-dashboards/supabase/ops-sheet-refresh/index.ts` | `SUPABASE_DB_URL`; checks the caller through `/auth/v1/user` with `SUPABASE_ANON_KEY`; writes `ops_sheet_data` |
| `client-report-draft` | `ioc-dashboards/supabase/client-report-draft/index.ts` | service-role client; RPC `client_report_next`; Google SA key |
| `coach-api` | `ioc-ai-coach-app/supabase/coach-api/index.ts` | `verify_jwt`, reads JWT claims; tables `coach_accounts`, `coach_clients`, `coach_plans`, `coach_fees`, `coach_measurements`, `wa_messages`, `food_db`, `exercise_db`, `ai_usage`; Claude key; `coach_wa_token`; calls sibling functions via `${SUPABASE_URL}/functions/v1/…` |
| `coach-daily` | `ioc-ai-coach-app/supabase/coach-daily/index.ts` | pg_cron trigger 8:00 am IST |
| `coach-profile` | `ioc-ai-coach-app/supabase/coach-profile/index.ts` | pg_cron trigger 2:00 am IST |
| `coach-plan-public` | `ioc-ai-coach-app/supabase/coach-plan-public/index.ts` | `verify_jwt` OFF, token in query string |
| `closer-api` | `ioc-closer-workspace/supabase/functions/closer-api/index.ts` | service-role client; `team_members`, `ws_login_codes`, `ws_sessions`, `ws_actions`, `slack_outbox`, `ghl_opportunities`, `stage_map`, `ghl_lost_reasons`; RPC `ghl_sync_secrets`; GHL token from env or `app_config` |

Secrets they read (set in the Supabase dashboard today, must move with them): `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEYS`, `SUPABASE_DB_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_SA_KEY`, `IOC_CLAUDE_KEY` / `ANTHROPIC_API_KEY`, `coach_wa_token`, `ghl_api_token` / `GHL_API_TOKEN`, `x-sync-secret` value.

## 3. Edge functions NOT in any repo (only deployed in Supabase — export them first)

- `wa-group-ingest` — target of `ioc-group-reader` (`INGEST_URL` env, `index.js` line 26); decides which WhatsApp groups are kept, transcribes voice notes; tables `wa_groups`, `wa_group_messages`, `client_wa_reports`
- `course-sync` — the whole course bot back end (`ioc-course-bot/runner.mjs` line 5, `bot.mjs`); hot-fix code stored in `app_config.course_bot_code`; GitHub Action `ioc-course-bot/.github/workflows/course-bot.yml` polls it every 3 h with `COURSE_WORKER_SECRET`
- `asana-client-edit` — called from `dash-api`
- `google-connect` — the Gmail/Calendar OAuth links Sahil sent Aakash (22 and 24 Oct); payment alerts into Slack depend on it
- The IOCtopus Slack bot itself (Note-1/Note-2 mirroring, `/win`, "Note added to GHL" posts, nudges) reads `slack_outbox`, `team_members`, `meetings`, `app_config`; its code is not in these repos
- Hourly Fathom → `meetings` sync (both Sahil's and Aakash's recordings)

## 4. Database objects to migrate

Tables referenced in code: `app_config`, `coach_accounts`, `coach_clients`, `coach_plans`, `coach_fees`, `coach_measurements`, `wa_messages`, `wa_groups`, `wa_group_messages`, `client_wa_reports`, `food_db`, `exercise_db`, `ai_usage`, `meetings`, `team_members`, `slack_outbox`, `ws_login_codes`, `ws_sessions`, `ws_actions`, `ghl_opportunities`, `stage_map`, `ghl_lost_reasons`, `tracker_source`, `asana_clients`, `ops_sheet_data`.
RPC / SQL functions: `client_report_next`, `ghl_sync_secrets`. pg_cron jobs: `coach-daily`, `coach-profile-nightly`, Fathom sync.
Seed SQL in repo: `ioc-ai-coach-app/supabase/sql/food_db.sql`, `exercise_db.sql`, `exercise_db.py`.
`app_config` rows that are configuration, not data: `dash_users` (dashboard access list), `course_bot_code`, GHL token fallback, course-bot controls.

## 5. Claude routines and skills

| Where | What to change |
|---|---|
| `C/routines/note2-post-call-prompt.txt` lines 10–16, 54 | "Supabase FIRST" — raw SQL against `meetings` (`SELECT … FROM meetings WHERE meeting_date BETWEEN …`, transcript read in 25,000-char `substring` chunks). Needs a new connector or a Fathom-only path; also the FINISH line "source (Supabase / Fathom)" |
| `C/routines/README.md` row 2 | connector list says "Supabase (read only)" |
| Routine connectors in the Claude app | remove the Supabase connector from the Note 2 routine once the replacement is wired |
| Note 1 outputs | the "Supabase reader" / "our IG reader" mentioned in notes is the Instagram reader hosted as a Supabase function; the Note 1 prompt does not name Supabase, but the reader URL used by the routine's web fetches will move |
| Skill `anthropic-skills:ioc-lead-grading` | no Supabase reference found; nothing to change |

## 6. Docs to update after the move

`ioc-dashboards/README.md`, `ioc-ai-coach-app/README.md`, `ioc-closer-workspace/README.md`, `ioc-course-bot/README.md`, `ioc-dashboards/supabase/jobs/aakash_brief.md`, the header comments in `ioc-group-reader/index.js`.

## Suggested order

1. Export the four functions and the pg_cron definitions that exist only in Supabase (section 3) into a repo, so nothing is lost.
2. Stand up the new database, run the schema + `app_config` rows, backfill `meetings`, `wa_*`, `coach_*`.
3. Port the edge functions (section 2) and point the two cron jobs and the GitHub Action at the new host.
4. Swap auth (Google sign-in) for the dashboards and coach app; update the publishable key and URLs in the five front-end files.
5. Re-point `ioc-group-reader` `INGEST_URL`, `ioc-course-bot` `API`, `ioc-closer-workspace` `API`.
6. Update the Note 2 routine prompt and its connectors; retire the Supabase MCP calls in the three dashboard pages.
7. Update the READMEs; delete the Supabase project only after a week of clean runs.
