-- Inserts the playbook skill as a DRAFT (active=false). Body mirrors .claude/skills/playbook/SKILL.md.
insert into public.skills(slug,title,summary,body,active,locked,version,updated_by,preload_kinds)
values ('playbook', $pb$Task playbook: best way to get each IOC task done$pb$, $pb$How to get any IOC task done: best path, which account or channel, exact call, fallback. Google Docs/Sheets/Gmail/Calendar/Drive through the 7 connected accounts via public.google(), Slack, WhatsApp, GHL, Asana, team tasks, reminders, jobs, lookups. Load before saying anything cannot be done.$pb$, $pb$
# IOC task playbook (project ugiurxkbbuhtvbehpkvb)

This skill is the source of truth; mirror in GitHub repo sahilkhatri-netizen/C at .claude/skills/playbook/SKILL.md. Companion to `channel-map` (where data lives). This skill is about doing.

## Rule zero: never say "can't" before checking four doors
1. A skill covers it? `select slug, summary from skills where active;` then `skill_load(slug)`.
2. A Supabase function or edge function does it? Look in the task table below, then `\df`-style: `select proname from pg_proc where pronamespace='public'::regnamespace and proname ilike '%<word>%';`
3. A connected account can do it? Seven Google accounts are reachable from SQL through `public.google()`. GHL, Asana, Slack and WhatsApp are reachable through functions and outboxes. The session's own connectors are the fourth option, not the first.
4. Only after 1 to 3 fail: say in one line what is missing and which Supabase step would fix it. Never "not available in this chat".

## Google through connected accounts (works from SQL, from the bot, from ai_jobs)
Call: `select public.google('<asker Slack id>', '<account id>', '<op>', '<args>'::jsonb, '{"slack_channel":"<channel>","thread_ts":"<ts or null>"}'::jsonb);`

| Account id | Email | Owner | Extra access |
|---|---|---|---|
| `aakash` | aakashvarmafitnessbusiness@gmail.com | Aakash | Archita: calendar only |
| `aakash-payments` | engineeringfitness.co.in@gmail.com | Aakash | Gmail watch on the payments label |
| `archita` | archita@engineeringfitness.in | Archita | |
| `sahil` | sahilkhatri@engineeringfitness.in | Sahil | |
| `suchita` | suchita@engineeringfitness.in | Suchita | |
| `suhail` | tech@engineeringfitness.in | Suhel | |
| `ioctopus` | ioctopusioc@gmail.com | Aakash | Sahil manages; the bot's own account for files it owns |

Access: the owner, listed managers, Aakash and Sahil can use an account fully. Calendar managers get Calendar only. Anyone else gets a refusal with the reason; relay that reason.

| Op | Args | Confirm card? |
|---|---|---|
| `gmail.search` | `{q, max}` | no |
| `gmail.get`, `gmail.thread` | `{message_id}` / `{thread_id}` | no |
| `gmail.draft` | `{to, cc, subject, body}` | no (logged to `bot_actions`) |
| `gmail.send` | `{to, cc, bcc, subject, body, thread_id}` | yes |
| `gmail.reply` | `{message_id, body, reply_all}` | yes |
| `gmail.send_draft`, `gmail.trash`, `gmail.modify` | | yes |
| `calendar.list` | `{calendar_id, time_min, time_max}` | no |
| `calendar.freebusy`, `calendar.calendars` | | no |
| `calendar.create` | `{calendar_id, event, send_updates, add_meet}` | yes |
| `calendar.update` / `calendar.delete` | `{event_id, event}` | yes |
| `drive.search` | `{name}` or `{text}` or `{q}`, `max` | no |
| `drive.read` | `{file_id, max_chars}` (Docs → text, Sheets → CSV) | no |
| `drive.share` | `{file_id, email, role, notify}` | yes |
| `drive.trash` | `{file_id}` | yes |
| `sheets.values` | `{spreadsheet_id, range, max_rows}` | no |
| `contacts.search`, `tasks.lists`, `tasks.list`, `youtube.*` | | no |
| `api.get` | `{url}` any googleapis.com GET | no |
| `api.write` | `{url, method, body}` any googleapis.com POST/PUT/PATCH/DELETE | yes |

Confirm cards go to the asker in the chat the request came from and expire after 15 minutes. Only the asker can tap Confirm. The result row lands in `google_actions`.

`api.write` is the general key: Docs `documents/{id}:batchUpdate`, Sheets `values/{range}?valueInputOption=USER_ENTERED` (PUT), Slides, Forms. Anything the account's scopes allow.

## Google through the IOC service account (no confirm, for jobs and shared files)
Files shared with the IOC sheets service account (the "ioc-sheets-bot" editor) can be written server-side:
- Sheets: edge function `sheets-api`, body `{spreadsheetId, ops:[{type: meta|get|values|append|batchUpdate|clear, ...}]}`.
- Docs: edge function `drive-doc-write`, body `{fileId, html}` replaces the whole document from HTML.
Both take the sheets key header from Vault (see how the `content-daily` cron job calls them with `net.http_post`). Never print the key. Use this path for recurring reports; use `public.google()` when a person asks for a one-off change to their own file.

## Task table

| Task | Best path | Account / channel | Fallback | Never |
|---|---|---|---|---|
| Update a Google Sheet | File shared with the service account → `sheets-api`. Else `google(asker, owner_account, 'api.write', {url: sheets values PUT})` | Owner of the sheet (`drive.search` shows `owners`) | Session's Google Sheets connector | "Not available" before trying |
| Update a Google Doc | Shared with service account → `drive-doc-write`. Else `google(..., 'api.write', {url: docs batchUpdate})` | Owner of the doc | Session's Google Drive connector | Overwrite a doc nobody shared |
| Read a doc, sheet or file | `google(asker, account, 'drive.read', {file_id})`; find it with `drive.search` | Any account the asker may use | Session connector | |
| Send an email | `google(asker, asker_account, 'gmail.send', ...)` → confirm card | The asker's own account; Aakash can use `aakash-payments` | `gmail.draft` and tell them where it is | Email a client or prospect; send from someone else's account without their confirm |
| Reply to an email | `gmail.search` → `gmail.reply` | same | | |
| Find an email, invoice mail, payment mail | `gmail.search {q}` | `aakash-payments` for payments, `archita` for ops | `bank_credit_alerts` for HDFC credits | |
| Is X free / what's on X's calendar | `meetings_on(day)` + GHL appointments (`ghl_appointments`, `ghl_calendar_events`) + `gcal_events` or `calendar.freebusy`; merge, name each source | Person's account | | Answer from one source |
| Book an internal meeting | GHL calendar via GHL connector or `ghl` tool first; else `google(..., 'calendar.create')` | Calendar managers: Aakash, Archita, Sahil | | Client appointments |
| Share a Drive file | `google(asker, account, 'drive.share', {file_id, email, role})` → confirm | Owner | `drive-share` edge fn for job-driven shares | |
| Post to a Slack channel | `insert into slack_outbox(channel_id, thread_ts, text, purpose)` then read `status` | Channel from the routing table below | `slack_api()` for other methods | Own Slack connection as the bot |
| DM a teammate on Slack | `slack_outbox` with their DM channel (`slack_channels` name `dm:<id>`) | | | |
| Send as a person (Aakash or Sahil) | `relay_draft_create()` → Send/Edit/Cancel card | `app_config.relay_senders` | | |
| WhatsApp a teammate | `insert into wa_outbox(to_number, text, reply_to, reply_id, purpose)` | `team_members.whatsapp_number` (Aakash, Akhtar, Sahil, Suchita have one) | Slack DM | Clients |
| Notify, nudge, remind someone | Tag in thread via `slack_outbox`; log `bot_actions`; check `person_card()` for leave first | | `reminder_add()` for timed | Nudge Aakash in public |
| Timed reminder / recurring job | `reminder_add(channel, text, due_ist, target, created_by, on_behalf, thread)`; `job_save(...)` proposed, starts on "go" | | | Remind clients |
| GHL: appointment note | Note 1 / Note 2 are owned by `ai_jobs`; ad-hoc notes via `ghl` tool POST `/calendars/appointments/{id}/notes` | Closer's GHL user id from `team_members.ghl_user_id` | | Write Note 2 by hand |
| GHL: Lead Grade / Setter Score | `ghl_lead_grade(payload)` (lead-grade skill) | Requesters: `app_config.grade_requesters` | | AI Grade |
| GHL: draft invoice | `ghl_invoice_draft(payload)` (invoices skill), tag Archita | Requesters: `app_config.invoice_requesters` | | Send invoices, mark paid |
| GHL: anything else live | GHL connector / `ghl` tool, location `LZkgKOxmYpiZl17MKuno` | Power users only for writes | Supabase copy for history | Stages, payments, client appointments |
| Asana task | Preview → asker replies approve → `asana_proposal_save/done` (asana-tasks skill) | As Sahil; requesters Suchita, Aakash, Sahil | | Create without approve; edit or delete existing |
| Team task add / update | `team_task_add()`, `team_task_update()`; agendas `agenda_topic_add()` / `agenda_topic_update()` then `agenda_sync_now()` | Team's Slack List from `team_lists` | | Others' tasks |
| Client question | `find_client(name)` → `clients` → Asana/GHL/Meta only for empty fields, then write back | | | "Client not found" before `find_client` |
| What was said / decided | `meeting_insight_get()`, `ioc_search()`, `slack_search()`, then `meetings.transcript` in 25k chunks | | Fathom connector only if `meetings` lacks it | Guess |
| Instagram check | `select ig_profile('handle')` | | WebFetch imginn per lead-notes rules | "Not found" on a reader error |
| Ads numbers | `meta_insights_daily`, `ad_daily_funnel`, `ad_report_db(day)` | | Meta connector GET if older than today's sync | Budget changes |
| Payments received | `ghl_transactions_real`, `bank_credit_alerts`, #payment-updates posts | | `aakash-payments` Gmail | Say paid; share bank details |
| Run an edge function | `select net.http_post(url := 'https://ugiurxkbbuhtvbehpkvb.supabase.co/functions/v1/<fn>', headers := jsonb_build_object('Content-Type','application/json','x-sync-secret',(select value from app_config where key='sync_secret')), body := '{}'::jsonb);` | | | Print the secret |
| Did a job run / why did it fail | `cron.job_run_details`, `ghl_sync_runs`, `meta_sync_runs`, `task_sync_log`, `slack_outbox.error`, `ai_queue`, `ai_usage.error`, `bot_job_runs` | | Supabase logs, short window, last | |
| Teach the bot a rule | Aakash/Sahil in DM: `bot_rule_save()`; procedure: `skill_write()`; observation: `bot_notes` | | | Save one-offs or secrets |
| Build something new | Check `build_plans` first; status planned = wait for Aakash | | | |

## Routing: task → Slack destination
| Purpose | Channel |
|---|---|
| EOD posts | `C09BZDM1CNL` #team-eods |
| Payment updates | `C0CB7U6U3A6` #payment-updates |
| New booking / cancelled | `C0C3NATALD9` #appointments-booking-updates |
| Confirmed / no-show, Note 1 threads | `C0C41761J04` #appointments-confirmed-updates |
| Disqualified applications | `C0C3JAH938X` #appointments-disqualified-updates |
| FCB buyers | `C0C462JPFEW` #appointments-fcb-updates |
| DFY ads, funnel, ad report, zero-booking alert | `C08U7AC95S4` #funnel-ads-aakash |
| Aakash SOD | `C09B6109T53` #aakash-action-plan |
| Task-sync signals | `C0CA82T5Y65` #ioctopus-tasks |
| Team: sales / fulfilment / content / marketing / ops / profit-scale | `C08PL2A6532` / `C09B0TL8G4B` / `C08QV8VQ3TP` / `C08P18NQ074` / `C09RGG3L999` / `C0AEVH2Q7FH` |
| Slack Lists | Team Tasks `F0C5G44LHT7`, Tasks `F0C5FL714R3`, Agenda topics `F0C56041ELF`, Meeting Log `F0C7EHWCR8W` |
Channel guide with what each holds: `select subject, fact from knowledge where kind='slack_channel' and not superseded;`

## Routing: person → handles
| Person | Slack | Google account | GHL user | WhatsApp | Asana | Team |
|---|---|---|---|---|---|---|
| Aakash Varma | U07Q5BDGA87 | `aakash`, `aakash-payments`, `ioctopus` | wyD6iOScp1NU3uVXU78L | yes | yes | Founder, ops |
| Sahil Khatri | U0B5K5FB7M4 | `sahil` (+ manages `ioctopus`) | id4Djgr9aqYqGXn7MNRo | yes | yes | Sales + automation |
| Akhtar Ansari | U08LC2WDZ2M | none connected | none | yes | yes | Marketing |
| Suchita Sinha | U08LBV89SM7 | `suchita` | none | yes | yes | Fulfilment |
| Suhel Shikalgar | U08LC2XF6CR | `suhail` (tech@) | none | no | yes | Marketing tech |
| Archita Hazarika | U09AS2K83U4 | `archita` (+ Aakash's calendar) | none | no | yes | Ops / finance |
| Sujata Bhuyan | U0C0KRSE5S5 | none | none | no | no | Content |
| Pratik Banjan | U08MB6M87CL | none | none | no | no | Content (editor) |
| Jayesh Gupta | U0C78LJF98F | none | PZrL16teQZX74J8Aexlf | no | no | Closer |
| Yash Chhabra | U0C8VU48R7G | none | TX9dI0BYPFjzqJC52Gn4 | no | no | Closer |
| Jai Maloth | U0C8T2HM0GM | none | nNzMLKeQ8OvxB2rg7qlS | no | no | Closer |
| Vansh Mehta | U0CA6FMSKM4 | none | none | no | no | Closer |
Live version: `select name, slack_id, ghl_user_id, team from team_members where active;` and `select id, label, owner_slack_id, managers from google_accounts where revoked_at is null;`. Closers never receive internal data.
$pb$, false, false, 1, 'claude-code', '{}')
on conflict (slug) do nothing;
insert into public.skill_versions(slug,version,body,summary,change_note,author)
select 'playbook', 1, s.body, s.summary, $pb$Initial task playbook drafted from google-connect ops, edge functions, functions and existing skills (Claude Code, 5 Nov 2026). Inactive until Aakash/Sahil review.$pb$, 'claude-code' from public.skills s
where s.slug='playbook' and not exists (select 1 from public.skill_versions where slug='playbook');
-- to activate after review:
-- update public.skills set active = true where slug = 'playbook';
