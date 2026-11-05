-- Inserts the channel-map skill as a DRAFT (active=false). Body mirrors .claude/skills/channel-map/SKILL.md.
insert into public.skills(slug,title,summary,body,active,locked,version,updated_by,preload_kinds)
values ('channel-map', $cm$Channel map: which table, function or connector serves what$cm$, $cm$Which Supabase table, function, edge function or live connector serves each channel (Slack, WhatsApp, GHL, Fathom, Google, Meta, Asana, tasks, clients, finance, content, bot brain, ai_jobs), how fresh each copy is, which writes are allowed. Load before any Supabase or connector work.$cm$, $cm$
# IOC channel map (project ugiurxkbbuhtvbehpkvb)

This skill is the source of truth. A mirror lives in the GitHub repo sahilkhatri-netizen/C at .claude/skills/channel-map/SKILL.md for Claude Code sessions; when this skill changes, update the mirror.

## How to choose (every time)
1. Name the domain from the table below. One request can touch several.
2. "Now / today / live" questions → the LIVE column. Everything else → the SUPABASE COPY, and say how old it is (`synced_at`, or `select * from public.freshness;`).
3. Writing? Use only the WRITE PATH listed. If none is listed, do not improvise: say which Supabase step is missing.
4. Prefer an existing function (`find_client`, `ioc_search`, `meeting_insight_get`, `meetings_on`, `ig_profile`, `skill_load`) over raw SQL on the big tables.
5. Name the source in the answer ("GHL live", "Supabase copy synced 11:51 IST").
6. Bot behaviour, permissions and hard limits live in the `core`, `permissions` and `knowledge-lookup` skills. Load them with `skill_load()` when acting as or for IOCtopus.

## Domains

| Domain | Live source | Supabase copy (read) | Filled by / cadence | Write path (allowed) | Never |
|---|---|---|---|---|---|
| Slack | Slack connector, read only, when the copy lacks it | `slack_messages_ist` view, `slack_messages`, `slack_channels`, `ioc_search()` (meaning), `slack_search()` (exact words), channel guide: `knowledge where kind='slack_channel'` | `slack-events` edge fn (realtime), `slack-backfill-new-channels` nightly 02:00 IST | Bot and jobs: `insert into slack_outbox(channel_id, thread_ts, text, purpose)`; other API: `slack_api(method, json)`; send-as-person: `relay_draft_create()` | Post from your own Slack connection as the bot; delete other people's messages |
| WhatsApp (team) | WhatsApp Business connector (IOC number) | `wa_messages` (team DMs with IOCtopus), `wa_media` | `whatsapp-webhook` edge fn (realtime) | `insert into wa_outbox(to_number, text, reply_to, reply_id, purpose)` → `send_wa_outbox()` | Message clients or prospects, from any surface |
| WhatsApp (client groups) | none, read-only reader | `wa_groups`, `wa_group_messages`, `wa_group_hold` (72h), `wa_reader_events` | `wa-group-ingest` edge fn | `wa_group_set_status()` only | Store messages from non-client groups |
| WhatsApp (client reports) | Suchita's own phone | `client_wa_reports`, `tracker_image_runs` | `client-report-draft`, `tracker-week-image` edge fns (Tuesday) | Dashboard edits only | Send these from the bot |
| GHL (CRM) | GHL connector, location `LZkgKOxmYpiZl17MKuno`, for anything live | `ghl_contacts`, `ghl_opportunities`, `pipeline_cards` view, `ghl_appointments`, `ghl_events`, `ghl_calendar_events`, `stage_map`, `ghl_lost_reasons`, `pipeline_flags`, `closers`, `lead_timeline` view | `ghl-sync` every 6h (`ghl_sync_runs`), `ghl-closer-sync` every 2h + nightly 02:10 IST, `ioc-app-events` webhooks → `ioc_app_events`, `ioc_live_posts` | Draft invoices `ghl_invoice_draft()`; Lead Grade / Setter Score `ghl_lead_grade()`; appointment notes via `ghl-lead-note` / Note 1 and Note 2 jobs; power users via connector | Move stages, mark paid, send invoices, edit client appointments, touch AI Grade |
| GHL calendars | same | `app_config.ioc_live_calendars` + `ioc_live_calendar_names` (7 strategy-call calendars) | | | |
| Payments / invoices | GHL connector (invoices, transactions) | `ghl_transactions` (`ghl_transactions_real` view = real money), `ghl_invoices`, `invoice_drafts`, `invoice_actions`, `manual_cash`, `cash_exclusions`, `sheet_sales_closed`, `bank_credit_alerts`, `ops_instalments` view | `ghl-closer-sync`, `ghl-invoice-record`, `fcb_payment_sweep()` every 2 min | Draft invoices only (`invoices` skill) | Record or confirm payments, refunds, send invoices |
| Fathom / meetings | Fathom connector, only if the copy has nothing | `meetings` (transcript, summary), `meetings_unique` view, `meeting_insights` + `meeting_insight_get()`, `meeting_log_v`, `meeting_drafts`, `meeting_agendas`, `meeting_schedule` + `meetings_on()` | `fathom-sync` every 6h (`sync_state` per teammate), `fathom_webhooks` | `meeting_insight_save()`; drafts flow via `meeting_drafts` | Re-fetch from Fathom what `meetings` already holds |
| Google (Gmail, Calendar, Drive) | Google connectors in Claude only, not in Supabase jobs | `gcal_events` (6 connected accounts in `google_accounts`), `google_actions` | `google-connect` edge fn, push watches renewed nightly | `select public.google(asker, account, op, args, reply)`; sends need the asker's confirm | Select `google_accounts.refresh_token`; answer "free/busy" from one source |
| Email (outbound) | none | `email_outbox` | `drive-share`, invoice flows | `insert into email_outbox` only where a skill says so | Email clients |
| Meta ads (IOC) | Meta connector, GET only | `meta_ads`, `meta_insights_daily`, `ad_daily_funnel`, `ad_creative_daily` views, `ad_report_db()`, `funnel_page_check()`, `funnel_alerts` | `meta-sync` 06:45 and 09:45 IST (`meta_sync_runs`) | none | Spend or budget changes |
| Meta ads (clients) | Meta connector | `client_ad_accounts`, `client_ads_daily` | IOC Fulfilment Data Sync routine | none | |
| Instagram | `ig_profile(handle)` / `ig_profiles_batch()` | `ig_profiles` cache (24h), `content_posts` (IOC's own IG) | `ig-profile`, `client-ig-resolve`, `content-ig-sync` edge fns | none | Call a profile "not found" on a reader error |
| Asana | Asana connector / asana tool (as Sahil) | `asana_clients` (Client List snapshot), `asana_tasks`, `asana_proposals`, `task_sync`, `task_sync_log` | `asana-sync` 09:30 and 16:30 IST, `asana-webhook`, Fulfilment Data Sync routine | Preview → approve → `asana_proposal_*` → `task-sync`; Client List fields via `asana-client-edit` (`client_field_edits`) | Delete or complete tasks; write without approval |
| Team tasks and agendas (Slack Lists) | Slack Lists via `slack_api` | `teams_tasks`, `teams_tasks_open` view, `team_lists`, `all_tasks_map`, `task_approvals`, `agenda_topic_sync` | `task-sync` hourly, `tasks-tracker`, `agenda-topics-sync` | `team_task_add()`, `team_task_update()`, `agenda_topic_add()`, `agenda_topic_update()`, `agenda_sync_now()` | Edit someone else's task; touch old agenda canvases |
| Clients (fulfilment) | Asana is the source | `clients` via `find_client()` first, `client_weekly_review`, `client_renewals`, `client_tracker_week`, `client_tracker_weekly`, `tracker_source`, `perf_updates`, `win_posts`, `pending_wins`, `client_gaps` view | `asana-sync`, `tracker-sync`, `weekly-review`, `perf_on_meeting` trigger | `wr_propose()` / `wr_confirm_rest()`; write back resolved fields to `clients` with `field_sources` | Reply "client not found" before `find_client()` |
| Sales call notes | GHL appointment notes | `sales_call_note2`, `sales_call_note2_posts`, `sales_call_log_rows`, `sales_call_log_v`, `note2_fires`, `lead_notes_added`, `call_tracker_rows`, `sales_call_attribution` | `ai_jobs` lead_notes (event: `ioc_live_posts`), note2 (event: new recording), `sales-call-log` 10 min, `call-tracker-sync` | The jobs write GHL notes; nothing else | Write a Note 2 by hand (jobs own it); edit a Note 1 from the Note 2 job |
| EOD and SOD | | `eod_drafts`, `eod_posts`, `eod_formats`, `aakash_brief`, `daily_reports` | `ai_jobs` eod_drafts 19:58 IST, `eod_post_all()` 23:00, `sod-aakash` bot job 10:30 | Via the `eod` skill replies only | Post EODs in #team-eods yourself |
| Content | Google Sheets (content tracker) | `content_posts`, `content_state`, `content_events`, `content_settings`, `content_dashboard_cache` | `content-wake` every 15 min, `content-daily` 09:00, `content-ig-sync` 07:57 IST | `content_wake_request()` | |
| Ops / finance sheets | Google Sheets | `ops_sheet_data` (totals only), `ops_bank_balance`, `ops_pipeline_weights`, `ops_dashboard()` | `ops-sheet-refresh` → `ops_sheet_load()` | `ops_set_bank_balance()` | Salaries, commission, bank details, per-person pay, anywhere |
| People | | `team_members`, `people_availability`, `people_actions`, `person_card()`, `ioc_holidays` | `people_detect_away()` from #general | `people_away_add()`, `people_rule_add()` | Store pay or health facts |
| Knowledge and memory | | `knowledge` (rule, client, process, decision, offer, metric, tool, person, slack_channel), `memory_chunks` via `ioc_search()` | `mem_kick()` every minute, `embed` edge fn | Add `knowledge` rows; supersede, never delete | Let an old fact outvote a newer one |
| Bot brain | | `skills` + `skill_load()`, `skill_versions`, `skill_tests`, `bot_rules` + `bot_rules_list()`, `bot_notes`, `bot_feedback` + `bot_feedback_review` view, `reply_traces`, `bot_actions`, `bot_jobs`, `bot_job_runs`, `bot_reminders`, `bot_open_loops`, `app_config` | `slack-router`, `ai-worker`, `ai_tick()` every 2 min, nightly `daily_review` job 00:05 IST | `skill_write()`, `skill_undo()`, `skill_test_add()`, `bot_rule_save()`, `job_save()`, `reminder_add()` | Edit `core` without Aakash or Sahil; read `app_config` values whose key contains secret, token, key, pin |
| AI jobs (Supabase-side Claude runs) | | `ai_jobs` (instructions, tools, shadow), `ai_queue`, `ai_usage`, `ai_cost_daily` view, `ai_job_parts`, `job_locks`; shared preamble `app_config.ai_tool_guide` | `ai_tick()` every 2 min, `ai_enqueue()` from cron | `ai_enqueue(job, payload, ref, dedupe)`; edit instructions only on request | Flip `ai_kill_switch`, raise `ai_monthly_cap_usd` |
| IOC AI Coach (separate product) | WhatsApp coach number | `coach_*`, `food_db`, `exercise_db`, `ws_*` | `coach-api`, `coach-daily`, `coach-profile` | Only inside coach jobs | Mix coach data with IOC team data |

## Naming rules
- `*_sync_runs`, `*_log`, `task_sync_log`, `teams_tasks_mirror_runs`: run logs. Read first when checking whether a job worked. Never the raw Supabase logs unless a table cannot answer.
- `*_outbox`: queued sends. Insert, then read back `status` and `error`. Never call the Slack or WhatsApp API directly to send.
- `*_backup_*`, `fix_*_20261003`, `dupe_cleanup_*`, `dup_cleanup_log`, `*_old`, `_hdfc_survey`, `_rzp_survey`, `gemini_test_results`, `client_ig_preview_probe`: frozen or scratch. Do not read for answers, do not write.
- `build_plans` with status planned: do not build until Aakash says go.
- Views (`*_v`, `pipeline_cards`, `meetings_unique`, `teams_tasks_open`, `ghl_transactions_real`): read-only, already de-duplicated. Prefer them for counts.

## Freshness at a glance
`select * from public.freshness;` returns one row per copy with the last sync time and age. Rule of thumb: GHL copy under 2h is fine for history, never for "right now"; Meta is daily; Slack and WhatsApp are realtime; Fathom and Asana are hourly to 6-hourly.

## Who may ask for what (ids)
Aakash U07Q5BDGA87, Sahil U0B5K5FB7M4, Akhtar U08LC2WDZ2M are power users. Invoice requesters, grade requesters, Asana requesters: `app_config` keys `invoice_requesters`, `grade_requesters`, `asana_requesters`. Closers get only their own calls, leads, deals, /win and draft invoices.
$cm$, false, false, 1, 'claude-code', '{}')
on conflict (slug) do nothing;
insert into public.skill_versions(slug,version,body,summary,change_note,author)
select 'channel-map', 1, $cm$
# IOC channel map (project ugiurxkbbuhtvbehpkvb)

This skill is the source of truth. A mirror lives in the GitHub repo sahilkhatri-netizen/C at .claude/skills/channel-map/SKILL.md for Claude Code sessions; when this skill changes, update the mirror.

## How to choose (every time)
1. Name the domain from the table below. One request can touch several.
2. "Now / today / live" questions → the LIVE column. Everything else → the SUPABASE COPY, and say how old it is (`synced_at`, or `select * from public.freshness;`).
3. Writing? Use only the WRITE PATH listed. If none is listed, do not improvise: say which Supabase step is missing.
4. Prefer an existing function (`find_client`, `ioc_search`, `meeting_insight_get`, `meetings_on`, `ig_profile`, `skill_load`) over raw SQL on the big tables.
5. Name the source in the answer ("GHL live", "Supabase copy synced 11:51 IST").
6. Bot behaviour, permissions and hard limits live in the `core`, `permissions` and `knowledge-lookup` skills. Load them with `skill_load()` when acting as or for IOCtopus.

## Domains

| Domain | Live source | Supabase copy (read) | Filled by / cadence | Write path (allowed) | Never |
|---|---|---|---|---|---|
| Slack | Slack connector, read only, when the copy lacks it | `slack_messages_ist` view, `slack_messages`, `slack_channels`, `ioc_search()` (meaning), `slack_search()` (exact words), channel guide: `knowledge where kind='slack_channel'` | `slack-events` edge fn (realtime), `slack-backfill-new-channels` nightly 02:00 IST | Bot and jobs: `insert into slack_outbox(channel_id, thread_ts, text, purpose)`; other API: `slack_api(method, json)`; send-as-person: `relay_draft_create()` | Post from your own Slack connection as the bot; delete other people's messages |
| WhatsApp (team) | WhatsApp Business connector (IOC number) | `wa_messages` (team DMs with IOCtopus), `wa_media` | `whatsapp-webhook` edge fn (realtime) | `insert into wa_outbox(to_number, text, reply_to, reply_id, purpose)` → `send_wa_outbox()` | Message clients or prospects, from any surface |
| WhatsApp (client groups) | none, read-only reader | `wa_groups`, `wa_group_messages`, `wa_group_hold` (72h), `wa_reader_events` | `wa-group-ingest` edge fn | `wa_group_set_status()` only | Store messages from non-client groups |
| WhatsApp (client reports) | Suchita's own phone | `client_wa_reports`, `tracker_image_runs` | `client-report-draft`, `tracker-week-image` edge fns (Tuesday) | Dashboard edits only | Send these from the bot |
| GHL (CRM) | GHL connector, location `LZkgKOxmYpiZl17MKuno`, for anything live | `ghl_contacts`, `ghl_opportunities`, `pipeline_cards` view, `ghl_appointments`, `ghl_events`, `ghl_calendar_events`, `stage_map`, `ghl_lost_reasons`, `pipeline_flags`, `closers`, `lead_timeline` view | `ghl-sync` every 6h (`ghl_sync_runs`), `ghl-closer-sync` every 2h + nightly 02:10 IST, `ioc-app-events` webhooks → `ioc_app_events`, `ioc_live_posts` | Draft invoices `ghl_invoice_draft()`; Lead Grade / Setter Score `ghl_lead_grade()`; appointment notes via `ghl-lead-note` / Note 1 and Note 2 jobs; power users via connector | Move stages, mark paid, send invoices, edit client appointments, touch AI Grade |
| GHL calendars | same | `app_config.ioc_live_calendars` + `ioc_live_calendar_names` (7 strategy-call calendars) | | | |
| Payments / invoices | GHL connector (invoices, transactions) | `ghl_transactions` (`ghl_transactions_real` view = real money), `ghl_invoices`, `invoice_drafts`, `invoice_actions`, `manual_cash`, `cash_exclusions`, `sheet_sales_closed`, `bank_credit_alerts`, `ops_instalments` view | `ghl-closer-sync`, `ghl-invoice-record`, `fcb_payment_sweep()` every 2 min | Draft invoices only (`invoices` skill) | Record or confirm payments, refunds, send invoices |
| Fathom / meetings | Fathom connector, only if the copy has nothing | `meetings` (transcript, summary), `meetings_unique` view, `meeting_insights` + `meeting_insight_get()`, `meeting_log_v`, `meeting_drafts`, `meeting_agendas`, `meeting_schedule` + `meetings_on()` | `fathom-sync` every 6h (`sync_state` per teammate), `fathom_webhooks` | `meeting_insight_save()`; drafts flow via `meeting_drafts` | Re-fetch from Fathom what `meetings` already holds |
| Google (Gmail, Calendar, Drive) | Google connectors in Claude only, not in Supabase jobs | `gcal_events` (6 connected accounts in `google_accounts`), `google_actions` | `google-connect` edge fn, push watches renewed nightly | `select public.google(asker, account, op, args, reply)`; sends need the asker's confirm | Select `google_accounts.refresh_token`; answer "free/busy" from one source |
| Email (outbound) | none | `email_outbox` | `drive-share`, invoice flows | `insert into email_outbox` only where a skill says so | Email clients |
| Meta ads (IOC) | Meta connector, GET only | `meta_ads`, `meta_insights_daily`, `ad_daily_funnel`, `ad_creative_daily` views, `ad_report_db()`, `funnel_page_check()`, `funnel_alerts` | `meta-sync` 06:45 and 09:45 IST (`meta_sync_runs`) | none | Spend or budget changes |
| Meta ads (clients) | Meta connector | `client_ad_accounts`, `client_ads_daily` | IOC Fulfilment Data Sync routine | none | |
| Instagram | `ig_profile(handle)` / `ig_profiles_batch()` | `ig_profiles` cache (24h), `content_posts` (IOC's own IG) | `ig-profile`, `client-ig-resolve`, `content-ig-sync` edge fns | none | Call a profile "not found" on a reader error |
| Asana | Asana connector / asana tool (as Sahil) | `asana_clients` (Client List snapshot), `asana_tasks`, `asana_proposals`, `task_sync`, `task_sync_log` | `asana-sync` 09:30 and 16:30 IST, `asana-webhook`, Fulfilment Data Sync routine | Preview → approve → `asana_proposal_*` → `task-sync`; Client List fields via `asana-client-edit` (`client_field_edits`) | Delete or complete tasks; write without approval |
| Team tasks and agendas (Slack Lists) | Slack Lists via `slack_api` | `teams_tasks`, `teams_tasks_open` view, `team_lists`, `all_tasks_map`, `task_approvals`, `agenda_topic_sync` | `task-sync` hourly, `tasks-tracker`, `agenda-topics-sync` | `team_task_add()`, `team_task_update()`, `agenda_topic_add()`, `agenda_topic_update()`, `agenda_sync_now()` | Edit someone else's task; touch old agenda canvases |
| Clients (fulfilment) | Asana is the source | `clients` via `find_client()` first, `client_weekly_review`, `client_renewals`, `client_tracker_week`, `client_tracker_weekly`, `tracker_source`, `perf_updates`, `win_posts`, `pending_wins`, `client_gaps` view | `asana-sync`, `tracker-sync`, `weekly-review`, `perf_on_meeting` trigger | `wr_propose()` / `wr_confirm_rest()`; write back resolved fields to `clients` with `field_sources` | Reply "client not found" before `find_client()` |
| Sales call notes | GHL appointment notes | `sales_call_note2`, `sales_call_note2_posts`, `sales_call_log_rows`, `sales_call_log_v`, `note2_fires`, `lead_notes_added`, `call_tracker_rows`, `sales_call_attribution` | `ai_jobs` lead_notes (event: `ioc_live_posts`), note2 (event: new recording), `sales-call-log` 10 min, `call-tracker-sync` | The jobs write GHL notes; nothing else | Write a Note 2 by hand (jobs own it); edit a Note 1 from the Note 2 job |
| EOD and SOD | | `eod_drafts`, `eod_posts`, `eod_formats`, `aakash_brief`, `daily_reports` | `ai_jobs` eod_drafts 19:58 IST, `eod_post_all()` 23:00, `sod-aakash` bot job 10:30 | Via the `eod` skill replies only | Post EODs in #team-eods yourself |
| Content | Google Sheets (content tracker) | `content_posts`, `content_state`, `content_events`, `content_settings`, `content_dashboard_cache` | `content-wake` every 15 min, `content-daily` 09:00, `content-ig-sync` 07:57 IST | `content_wake_request()` | |
| Ops / finance sheets | Google Sheets | `ops_sheet_data` (totals only), `ops_bank_balance`, `ops_pipeline_weights`, `ops_dashboard()` | `ops-sheet-refresh` → `ops_sheet_load()` | `ops_set_bank_balance()` | Salaries, commission, bank details, per-person pay, anywhere |
| People | | `team_members`, `people_availability`, `people_actions`, `person_card()`, `ioc_holidays` | `people_detect_away()` from #general | `people_away_add()`, `people_rule_add()` | Store pay or health facts |
| Knowledge and memory | | `knowledge` (rule, client, process, decision, offer, metric, tool, person, slack_channel), `memory_chunks` via `ioc_search()` | `mem_kick()` every minute, `embed` edge fn | Add `knowledge` rows; supersede, never delete | Let an old fact outvote a newer one |
| Bot brain | | `skills` + `skill_load()`, `skill_versions`, `skill_tests`, `bot_rules` + `bot_rules_list()`, `bot_notes`, `bot_feedback` + `bot_feedback_review` view, `reply_traces`, `bot_actions`, `bot_jobs`, `bot_job_runs`, `bot_reminders`, `bot_open_loops`, `app_config` | `slack-router`, `ai-worker`, `ai_tick()` every 2 min, nightly `daily_review` job 00:05 IST | `skill_write()`, `skill_undo()`, `skill_test_add()`, `bot_rule_save()`, `job_save()`, `reminder_add()` | Edit `core` without Aakash or Sahil; read `app_config` values whose key contains secret, token, key, pin |
| AI jobs (Supabase-side Claude runs) | | `ai_jobs` (instructions, tools, shadow), `ai_queue`, `ai_usage`, `ai_cost_daily` view, `ai_job_parts`, `job_locks`; shared preamble `app_config.ai_tool_guide` | `ai_tick()` every 2 min, `ai_enqueue()` from cron | `ai_enqueue(job, payload, ref, dedupe)`; edit instructions only on request | Flip `ai_kill_switch`, raise `ai_monthly_cap_usd` |
| IOC AI Coach (separate product) | WhatsApp coach number | `coach_*`, `food_db`, `exercise_db`, `ws_*` | `coach-api`, `coach-daily`, `coach-profile` | Only inside coach jobs | Mix coach data with IOC team data |

## Naming rules
- `*_sync_runs`, `*_log`, `task_sync_log`, `teams_tasks_mirror_runs`: run logs. Read first when checking whether a job worked. Never the raw Supabase logs unless a table cannot answer.
- `*_outbox`: queued sends. Insert, then read back `status` and `error`. Never call the Slack or WhatsApp API directly to send.
- `*_backup_*`, `fix_*_20261003`, `dupe_cleanup_*`, `dup_cleanup_log`, `*_old`, `_hdfc_survey`, `_rzp_survey`, `gemini_test_results`, `client_ig_preview_probe`: frozen or scratch. Do not read for answers, do not write.
- `build_plans` with status planned: do not build until Aakash says go.
- Views (`*_v`, `pipeline_cards`, `meetings_unique`, `teams_tasks_open`, `ghl_transactions_real`): read-only, already de-duplicated. Prefer them for counts.

## Freshness at a glance
`select * from public.freshness;` returns one row per copy with the last sync time and age. Rule of thumb: GHL copy under 2h is fine for history, never for "right now"; Meta is daily; Slack and WhatsApp are realtime; Fathom and Asana are hourly to 6-hourly.

## Who may ask for what (ids)
Aakash U07Q5BDGA87, Sahil U0B5K5FB7M4, Akhtar U08LC2WDZ2M are power users. Invoice requesters, grade requesters, Asana requesters: `app_config` keys `invoice_requesters`, `grade_requesters`, `asana_requesters`. Closers get only their own calls, leads, deals, /win and draft invoices.
$cm$, $cm$Which Supabase table, function, edge function or live connector serves each channel (Slack, WhatsApp, GHL, Fathom, Google, Meta, Asana, tasks, clients, finance, content, bot brain, ai_jobs), how fresh each copy is, which writes are allowed. Load before any Supabase or connector work.$cm$, $cm$Initial channel map drafted from schema, cron, edge functions and existing skills (Claude Code, 5 Nov 2026). Inactive until Aakash/Sahil review.$cm$, 'claude-code'
where not exists (select 1 from public.skill_versions where slug='channel-map');
-- to activate after review:
-- update public.skills set active = true where slug = 'channel-map';
