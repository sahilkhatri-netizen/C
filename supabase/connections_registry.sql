-- Connections registry: every software connection IOC has, and every data point that can be read, as rows.
-- Lookup: select * from public.where_is('calls booked');  select * from public.where_is('spend');
create table if not exists public.connections (
  id              text primary key,
  system          text not null,
  kind            text not null,          -- crm | chat | tasks | ads | meetings | email_calendar_drive | sheets_docs | payments | social | ai | web
  account         text,                   -- the identifier: location id, number, ad account, email, list ids
  owner_slack_id  text,
  access          text not null,          -- how Claude reaches it from Supabase
  read_live       text,                   -- how to read it live, if the copy is too old
  write_path      text,                   -- the only allowed way to write, or 'none'
  tables          text[] default '{}',    -- Supabase copies
  cadence         text,
  freshness_sql   text,                   -- one query that returns the last sync time
  status          text not null default 'active',
  notes           text,
  updated_at      timestamptz not null default now()
);
comment on table public.connections is 'Registry of every connected system (GHL, Slack, WhatsApp, Meta, Fathom, Asana, each Google account, service account, bank mail, Claude API): identifier, owner, how Claude reaches it, live read, allowed write path, Supabase copies, cadence. Query with where_is(). Edit rows when a connection changes.';

create table if not exists public.data_points (
  key              text primary key,
  question         text not null,         -- the question in plain words
  connection_id    text references public.connections(id),
  source           text not null,         -- table, view or function to read
  how              text not null,         -- the query pattern
  live_alternative text,
  caveats          text,
  updated_at       timestamptz not null default now()
);
comment on table public.data_points is 'Where each business data point is read from: question in plain words, the connection, the table/view/function, the query pattern, the live alternative and caveats. Query with where_is(). Add a row whenever a question had to be answered by hand.';

alter table public.connections enable row level security;
alter table public.data_points enable row level security;

insert into public.connections (id, system, kind, account, owner_slack_id, access, read_live, write_path, tables, cadence, freshness_sql, notes) values
('ghl', 'GHL (GoHighLevel)', 'crm', 'location LZkgKOxmYpiZl17MKuno · Sales Pipeline PoShJBh0iBwEx6iq8wfb', 'U0B5K5FB7M4',
 'Claude: GHL connector (mcp__ghl search_operations/describe/execute). ai_jobs: ghl tool (REST). Supabase: edge fns ghl-sync, ghl-closer-sync, ioc-app-events (webhooks).',
 'GHL API: contacts, opportunities/search, calendars/events, forms/submissions, appointment notes',
 'ghl_lead_grade(payload) · ghl_invoice_draft(payload) · appointment notes only via the lead_notes / note2 ai_jobs · power users may use the connector',
 array['ghl_contacts','ghl_opportunities','pipeline_cards','ghl_events','stage_map','ghl_lost_reasons','pipeline_flags','lead_timeline'],
 'ghl-sync every 6h + webhooks realtime; ghl-closer-sync every 2h, full nightly 02:10 IST',
 'select max(synced_at) from ghl_opportunities',
 'Never move stages, mark paid, send invoices, edit client appointments or AI Grade.'),
('ghl_calendars', 'GHL calendars', 'crm', '7 strategy-call calendars: app_config.ioc_live_calendars / ioc_live_calendar_names · team blocks', 'U0B5K5FB7M4',
 'edge fns ghl-closer-sync (appointments), ghl-calendar-events (team blocks); GHL connector live',
 'GHL get-calendar-events {locationId, calendarId, startTime, endTime epoch ms}',
 'internal team meetings/blocks by calendar managers (Aakash, Archita, Sahil) via connector; never client appointments',
 array['ghl_appointments','ghl_calendar_events','ioc_live_posts'],
 'every 2h; booking/status alerts realtime via ioc-app-events',
 'select max(synced_at) from ghl_appointments', 'Count bookings by the call date, not the post time.'),
('ghl_payments', 'GHL Payments & Invoices', 'payments', 'same location', 'U09AS2K83U4',
 'edge fns ghl-closer-sync (transactions), ghl-invoice-record, ghl-invoice-draft; GHL connector live',
 'GHL list-transactions, invoices.list-invoices',
 'ghl_invoice_draft() drafts only (invoices skill, tag Archita)',
 array['ghl_transactions','ghl_transactions_real','ghl_invoices','invoice_drafts','invoice_actions','manual_cash','cash_exclusions','sheet_sales_closed'],
 'every 2h', 'select max(synced_at) from ghl_transactions', 'Never record, confirm or refund payments; never send invoices.'),
('ghl_courses', 'GHL Memberships (courses)', 'crm', 'IOC course posts', 'U0B5K5FB7M4',
 'edge fn course-sync (uploads call recordings as lessons)', null, 'none', array['course_sync_log'], 'on new recording',
 'select max(at) from course_sync_log', 'meetings.course_status tracks each recording.'),
('slack', 'Slack', 'chat', 'bot IOCtopus U0C4RLGR8LT · 46 member channels (slack_channels)', 'U0B5K5FB7M4',
 'edge fns slack-events (ingest), slack-router (replies), slack-commands; SQL slack_api(method, json); Claude Slack connector for reading only what is not stored',
 'slack_api() or Slack connector read',
 'insert into slack_outbox(channel_id, thread_ts, text, purpose) · relay_draft_create() to send as Aakash/Sahil',
 array['slack_messages','slack_messages_ist','slack_channels','slack_outbox','memory_chunks'],
 'realtime; new-channel backfill nightly 02:00 IST', 'select max(msg_time) from slack_messages',
 'Never post from your own Slack connection as the bot. Channel guide: knowledge where kind=slack_channel.'),
('slack_lists', 'Slack Lists', 'tasks', 'Team Tasks F0C5G44LHT7 · Tasks F0C5FL714R3 · Agenda topics F0C56041ELF · Meeting Log F0C7EHWCR8W · Sales Call Log (app_config.sales_call_log)', 'U0B5K5FB7M4',
 'edge fns task-sync, tasks-tracker, agenda-topics-sync, meeting-log, sales-call-log',
 'slack_api(''slackLists.items.list'', ...)',
 'team_task_add() · team_task_update() · agenda_topic_add() · agenda_topic_update() · agenda_sync_now()',
 array['teams_tasks','teams_tasks_open','team_lists','all_tasks_map','task_approvals','meeting_log_rows','sales_call_log_rows'],
 'hourly (tasks), every 10 min (logs)', 'select max(seen_at) from teams_tasks', 'People change only their own tasks.'),
('whatsapp_team', 'WhatsApp Business (Meta Cloud API)', 'chat', 'IOCtopus number · phone_number_id 1337272506139050 · allowed numbers app_config.wa_allowed_numbers', 'U0B5K5FB7M4',
 'edge fn whatsapp-webhook (ingest + replies); SQL send_wa_outbox()',
 null, 'insert into wa_outbox(to_number, text, reply_to, reply_id, purpose) — team members only',
 array['wa_messages','wa_media','wa_outbox'], 'realtime', 'select max(created_at) from wa_messages', 'Never message clients or prospects.'),
('whatsapp_group_reader', 'WhatsApp group reader (device)', 'chat', 'reader 917069998087 · status in app_config.wa_reader_status', 'U08LBV89SM7',
 'edge fn wa-group-ingest', null, 'wa_group_set_status(jid, status, client_gid, by) only',
 array['wa_groups','wa_group_messages','wa_group_hold','wa_reader_events'], 'realtime; pending groups held 72h',
 'select max(created_at) from wa_group_messages', 'Only groups marked client are stored.'),
('whatsapp_coach', 'WhatsApp Business (IOC AI Coach product)', 'chat', 'coach number phone_number_id 1206288092560062 · WABA 1600476401058639', 'U07Q5BDGA87',
 'edge fns coach-api, coach-daily, coach-profile, coach-plan-public', null, 'only inside coach jobs',
 array['coach_accounts','coach_clients','coach_plans','coach_measurements','coach_fees','food_db','exercise_db','ws_sessions'],
 'realtime + nightly', null, 'Separate product. Never mix with IOC team or sales data.'),
('meta_ioc', 'Meta Marketing API (IOC)', 'ads', 'ad account act_1595291421269588 · IG business 17841401458608748 @aakashvarma_fitnessbusiness', 'U08LC2WDZ2M',
 'edge fn meta-sync; Claude Meta connector GET; ai_jobs meta tool GET',
 'Meta Graph GET /act_1595291421269588/... with fields', 'none',
 array['meta_ads','meta_insights_daily','ad_daily_funnel','ad_creative_daily','content_posts','funnel_alerts'],
 'daily 06:45 and 09:45 IST', 'select max(synced_at) from meta_insights_daily', 'Read only. Budget or spend changes are never automated.'),
('meta_clients', 'Meta Marketing API (client accounts)', 'ads', '33 client ad accounts (client_ad_accounts)', 'U08LC2XF6CR',
 'IOC Fulfilment Data Sync routine; Meta connector', 'Meta Graph GET per client ad account', 'none',
 array['client_ad_accounts','client_ads_daily'], 'daily', 'select max(synced_at) from client_ad_accounts', null),
('fathom', 'Fathom', 'meetings', 'team sync for aakash, akhtar, archita, jayesh, sahil, suchita, suhel, vansh, yash', 'U0B5K5FB7M4',
 'edge fn fathom-sync + fathom_webhooks; Claude Fathom connector only as fallback',
 'Fathom connector list_meetings / get_meeting_transcript', 'meeting_insight_save()',
 array['meetings','meetings_unique','meeting_insights','meeting_log_v','meeting_drafts','sync_state'],
 'every 6h + webhooks', 'select max(last_run_at) from sync_state', 'Supabase first; Fathom only when meetings has nothing.'),
('asana', 'Asana', 'tasks', 'as Sahil · IOC Client List + 30 client projects', 'U0B5K5FB7M4',
 'edge fns asana-sync, asana-webhook, asana-client-edit, task-sync; ai_jobs asana tool; Claude Asana connector',
 'Asana connector / asana tool', 'preview → approve → asana_proposal_save/done → task-sync; Client List fields via asana-client-edit',
 array['asana_clients','asana_tasks','asana_proposals','task_sync','task_sync_log','client_field_edits'],
 '09:30 and 16:30 IST + webhook', 'select max(synced_at) from asana_tasks', 'Asana is the source for the client list. Never delete or complete tasks.'),
('google:aakash', 'Google account', 'email_calendar_drive', 'aakashvarmafitnessbusiness@gmail.com', 'U07Q5BDGA87',
 'public.google(asker, ''aakash'', op, args, reply) via edge fn google-connect', 'gmail.search/get, calendar.list/freebusy, drive.search/read, sheets.values, api.get',
 'gmail.send/reply, calendar.create/update, drive.share, api.write — confirm card to the asker', array['gcal_events','google_actions'],
 'calendar push realtime', 'select max(synced_at) from gcal_events where account_id=''aakash''', 'Archita manages the calendar only.'),
('google:aakash-payments', 'Google account', 'email_calendar_drive', 'engineeringfitness.co.in@gmail.com', 'U07Q5BDGA87',
 'public.google(asker, ''aakash-payments'', op, args)', 'gmail.search on the payments label', 'confirm ops as above', array['bank_credit_alerts'],
 'gmail push on one label', 'select max(received_at) from bank_credit_alerts', 'The watched label feeds bank_credit_alerts (HDFC, Razorpay).'),
('google:archita', 'Google account', 'email_calendar_drive', 'archita@engineeringfitness.in', 'U09AS2K83U4', 'public.google(asker, ''archita'', op, args)', 'read ops', 'confirm ops', array['gcal_events'], 'calendar push', 'select max(synced_at) from gcal_events where account_id=''archita''', null),
('google:sahil', 'Google account', 'email_calendar_drive', 'sahilkhatri@engineeringfitness.in', 'U0B5K5FB7M4', 'public.google(asker, ''sahil'', op, args)', 'read ops', 'confirm ops', array['gcal_events'], 'calendar push', 'select max(synced_at) from gcal_events where account_id=''sahil''', null),
('google:suchita', 'Google account', 'email_calendar_drive', 'suchita@engineeringfitness.in', 'U08LBV89SM7', 'public.google(asker, ''suchita'', op, args)', 'read ops', 'confirm ops', array['gcal_events'], 'calendar push', 'select max(synced_at) from gcal_events where account_id=''suchita''', null),
('google:suhail', 'Google account', 'email_calendar_drive', 'tech@engineeringfitness.in', 'U08LC2XF6CR', 'public.google(asker, ''suhail'', op, args)', 'read ops', 'confirm ops', array['gcal_events'], 'calendar push', 'select max(synced_at) from gcal_events where account_id=''suhail''', null),
('google:ioctopus', 'Google account (bot)', 'email_calendar_drive', 'ioctopusioc@gmail.com', 'U07Q5BDGA87', 'public.google(asker, ''ioctopus'', op, args); Sahil manages', 'read ops', 'confirm ops', array[]::text[], 'calendar push', null, 'Files the bot owns.'),
('google_service_account', 'Google service account (ioc-sheets-bot)', 'sheets_docs', 'files shared with the service account as editor', 'U0B5K5FB7M4',
 'edge fns sheets-api {spreadsheetId, ops}, drive-doc-write {fileId, html}, content-*, tracker-sync, ops-sheet-refresh, call-tracker-sync; key in Vault',
 'sheets-api op get', 'sheets-api values/append/batchUpdate · drive-doc-write replaces a Doc',
 array['content_state','content_posts','ops_sheet_data','tracker_source','client_tracker_week','call_tracker_rows'],
 'content every 15 min; ops and trackers daily', 'select max(synced_at) from content_posts', 'Server-side, no confirm card. Never print the key.'),
('bank_mail', 'Bank and gateway emails (HDFC, Razorpay)', 'payments', 'payments label on aakash-payments Gmail', 'U09AS2K83U4',
 'google-connect gmail push → bank_credit_alerts; fcb_payment_sweep() every 2 min', 'gmail.search on aakash-payments', 'none',
 array['bank_credit_alerts','_hdfc_survey','_rzp_survey'], 'realtime push', 'select max(received_at) from bank_credit_alerts', 'Match to invoices; never mark paid.'),
('instagram_public', 'Instagram public profiles', 'social', 'via edge fn ig-profile (reader) and client-ig-resolve (Graph lookup)', 'U0B5K5FB7M4',
 'select ig_profile(handle) / ig_profiles_batch(handles)', 'ig_profile(handle, true) forces a fresh read', 'none',
 array['ig_profiles'], '24h cache', 'select max(fetched_at) from ig_profiles', 'A reader error is not proof the account does not exist.'),
('claude_api', 'Anthropic Claude API', 'ai', 'ai-worker edge fn running ai_jobs; preamble app_config.ai_tool_guide', 'U0B5K5FB7M4',
 'ai_enqueue(job, payload, ref, dedupe); ai_tick() every 2 min', null, 'ai_enqueue() only; edit ai_jobs.instructions on request',
 array['ai_jobs','ai_queue','ai_usage','ai_cost_daily','ai_job_parts'], 'every 2 min', 'select max(created_at) from ai_usage', 'Never flip ai_kill_switch or raise ai_monthly_cap_usd.'),
('dashboards', 'IOC web dashboards', 'web', 'dash-api, closer-dashboard, content-dashboard, ops_dashboard(); users app_config.dash_users', 'U0B5K5FB7M4',
 'edge fns dash-api, closer-api, closer-dashboard, content-dashboard, publish-page', null, 'dashboard edits write to client_field_edits, client_wa_reports, client_weekly_review',
 array['dashboard_pages','aakash_brief','content_dashboard_cache'], 'on request', null, null)
on conflict (id) do update set system=excluded.system, kind=excluded.kind, account=excluded.account, owner_slack_id=excluded.owner_slack_id, access=excluded.access, read_live=excluded.read_live, write_path=excluded.write_path, tables=excluded.tables, cadence=excluded.cadence, freshness_sql=excluded.freshness_sql, notes=excluded.notes, updated_at=now();

insert into public.data_points (key, question, connection_id, source, how, live_alternative, caveats) values
('bookings', 'How many calls were booked (today / yesterday / this week), who booked', 'ghl_calendars', 'ghl_appointments',
 $v$select count(*) from ghl_appointments where calendar_id in (select jsonb_array_elements_text(value::jsonb) from app_config where key='ioc_live_calendars') and (start_time at time zone 'Asia/Kolkata')::date = <day> and not deleted and status <> 'cancelled'$v$,
 'GHL get-calendar-events per calendar', 'Count by call date, not post time. #appointments-booking-updates posts are the same events.'),
('confirmed_calls', 'How many calls confirmed / showed', 'ghl_calendars', 'ghl_appointments', $v$... where status in ('confirmed','showed') and (start_time at time zone 'Asia/Kolkata')::date = <day>$v$, 'GHL get-calendar-events', 'Confirmed by us vs by them: check whether the prospect ever replied.'),
('no_shows', 'How many no-shows', 'ghl_calendars', 'ghl_appointments', $v$... where status = 'noshow'$v$, 'GHL', 'No-shows are sometimes posted late; use the call date.'),
('applications', 'How many applications / disqualified applications', 'ghl', 'pipeline_cards + stage_map', $v$select count(*) from ghl_opportunities o join stage_map s on s.stage_id=o.stage_id where s.name='Disqualified App' and o.created_at::date = <day>$v$, 'GHL get-forms-submissions {formId IuUSlqmw9cHzItecqR5s}', 'Counting rules live in the dfy-ad-report skill.'),
('pipeline_stage', 'What stage is lead X in / pipeline by stage', 'ghl', 'pipeline_cards, stage_map', $v$select name, stage, ... from pipeline_cards where name ilike '%<name>%'$v$, 'GHL search-opportunity by contactId', 'Supabase copy can be up to 6h old; webhooks update stage changes faster (ghl_events).'),
('lead_profile', 'Everything about a lead: source, UTM, form answers, history', 'ghl', 'ghl_contacts, lead_timeline, ghl_events', $v$select * from lead_timeline where contact_id = '<id>' order by at$v$, 'GHL get-contact, forms/submissions, contacts/{id}/appointments, appointment notes', 'Form answers and Note 1 are in GHL notes, not in Supabase.'),
('ad_spend', 'Ad spend / CPL / results by day or campaign', 'meta_ioc', 'meta_insights_daily, ad_daily_funnel', $v$select date, sum(spend) from meta_insights_daily where date between <from> and <to> group by 1$v$, 'Meta Graph GET insights if before today''s 09:45 sync', 'Meta is daily. Say the sync time.'),
('ad_report', 'Daily DFY ad report numbers and funnel check', 'meta_ioc', 'ad_report_db(day), funnel_page_check()', $v$select * from ad_report_db(<day>)$v$, null, 'The ad_report ai_job posts it at 10:00 IST in #funnel-ads-aakash.'),
('payments_received', 'Which payments came in / did X pay', 'ghl_payments', 'ghl_transactions_real, bank_credit_alerts', $v$select * from ghl_transactions_real where created_at >= <from>; select * from bank_credit_alerts where received_at >= <from>$v$, 'GHL list-transactions; gmail.search on aakash-payments', 'Never say paid unless a transaction or confirmed bank alert exists. Never mark paid.'),
('invoice_status', 'Invoice status / amount due', 'ghl_payments', 'ghl_invoices, invoice_drafts', $v$select invoice_number, status, total, amount_due, due_date from ghl_invoices where contact_name ilike '%<name>%'$v$, 'GHL invoices.list-invoices', 'Drafts only through the invoices skill.'),
('cash_and_sales', 'Cash collected, sales by program, closer numbers', 'ghl_payments', 'closer_metrics_v2(from,to), ops_dashboard(key,from,to), sheet_sales_closed', $v$select * from closer_metrics_v2(<from>, <to>)$v$, null, 'Program names: DIH = Sales Jumpstart, DFY = Sales Accelerator, DFY Scale = Sales Multiplier. FCB separate.'),
('call_recording', 'Find a sales or team call, its recording and transcript', 'fathom', 'meetings', $v$select recording_id, title, meeting_date, duration_min, share_url from meetings where (title ilike '%<name>%' or participants::text ilike '%<email>%') order by meeting_date desc$v$, 'Fathom list_meetings', 'Search all dates and spelling variants before saying not found. Transcript in 25k chunks.'),
('meeting_decisions', 'What was decided / discussed in a meeting', 'fathom', 'meeting_insight_get(name_or_topic, days), ioc_search(q, 8, ''meetings'')', $v$select * from meeting_insight_get('<topic>', 30)$v$, null, 'Insight first, transcript second.'),
('slack_said', 'Who said what in Slack / what did we decide in a thread', 'slack', 'ioc_search(), slack_search(), slack_messages_ist', $v$select * from ioc_search('<question in plain words>', 8, null, null)$v$, 'Slack connector only for channels not stored', 'Scores >= 24 are strong. Team Slack is in English.'),
('channel_purpose', 'Which Slack channel holds what / how to count from it', 'slack', 'knowledge (kind = slack_channel)', $v$select subject, fact from knowledge where kind='slack_channel' and not superseded$v$, null, null),
('who_is_free', 'Is X free at <time> / what is on X''s calendar', 'google:aakash', 'meetings_on(day), ghl_appointments, ghl_calendar_events, gcal_events', $v$select * from meetings_on(<day>); select * from gcal_events where account_id='<id>' and start_at::date=<day>; select * from ghl_appointments where assigned_user_id='<ghl user>' and start_time::date=<day>$v$, 'public.google(asker, account, ''calendar.freebusy'', ...)', 'Check all three sources and say which. Never from one.'),
('team_meetings', 'When is the <team> meeting / recurring team meetings', 'google:aakash', 'meeting_schedule, meetings_on(day)', $v$select * from meetings_on(current_date)$v$, 'gcal_events for moved/cancelled instances', 'Quote the synced calendar time when it differs from the fixed schedule and say moved.'),
('team_availability', 'Is X on leave / who is away today', 'slack', 'people_availability, person_card(slack_id), ioc_holidays', $v$select * from person_card('<slack id>')$v$, null, 'Leave posts in #general are picked up automatically.'),
('open_tasks', 'X''s open tasks / team tasks / overdue', 'slack_lists', 'teams_tasks_open, asana_tasks, person_task_counts(slack_id)', $v$select * from teams_tasks_open where owner ilike '%<name>%'$v$, 'Asana connector for status', 'Asana created time is not the assigned date.'),
('client_profile', 'Everything about client X (program, tier, IG, phone, Asana card, ad account, tracker)', 'asana', 'find_client(q) → clients', $v$select * from find_client('<whatever was typed>'); then select * from clients where name = <top row>$v$, 'Asana IOC Client List card', 'Run find_client before saying not found. Write back resolved fields.'),
('client_health', 'How is client X doing / weekly review / renewal risk', 'asana', 'client_weekly_review, client_renewals, client_tracker_week, perf_updates, client_gaps', $v$select * from client_weekly_review where client ilike '%<name>%' order by week desc$v$, null, 'Suchita''s review is the source for tier and behaviour.'),
('client_launches', 'When does client X launch / are their ads live', 'meta_clients', 'asana_tasks, client_ads_daily, knowledge (#ioc-launch-update)', $v$select * from client_ads_daily where client ilike '%<name>%' order by day desc$v$, 'Meta GET on the client ad account', 'Live only if a launched post or spend exists.'),
('client_messages', 'What did client X say in their WhatsApp group', 'whatsapp_group_reader', 'wa_group_messages', $v$select sent_at, sender_name, body from wa_group_messages m join wa_groups g on g.jid=m.group_jid where g.client_gid = '<asana gid>' order by sent_at desc$v$, null, 'Client groups only; voice notes as transcript.'),
('eod_status', 'Did X post their EOD / what did it say', 'slack', 'eod_posts, eod_drafts', $v$select * from eod_posts where day = <day>$v$, null, 'No EODs on Sunday.'),
('email_lookup', 'Find an email / what did X email about', 'google:aakash', 'public.google(asker, account, ''gmail.search'', {q})', $v$select public.google('<asker>', '<account id>', 'gmail.search', '{"q":"from:x subject:y newer_than:7d","max":10}')$v$, null, 'Only the account owner, its managers, Aakash or Sahil can read it.'),
('file_lookup', 'Find a Google Doc / Sheet / Drive file and read it', 'google:aakash', 'public.google(asker, account, ''drive.search'' / ''drive.read'')', $v$select public.google('<asker>', '<account>', 'drive.search', '{"name":"<part of name>"}'); then 'drive.read' with {file_id}$v$, null, 'Docs export as text, Sheets as CSV.'),
('sheet_values', 'Read a range from a Google Sheet', 'google_service_account', 'sheets-api op get, or public.google sheets.values', $v$select public.google('<asker>', '<account>', 'sheets.values', '{"spreadsheet_id":"<id>","range":"Sheet1!A1:F50"}')$v$, 'sheets-api if the file is shared with the service account', null),
('ig_profile', 'Instagram profile of a lead or client', 'instagram_public', 'ig_profile(handle)', $v$select ig_profile('<handle>')$v$, 'ig_profile(handle, true) to force refresh', 'Use the exact handle from the form. Error is not not-found.'),
('team_whatsapp', 'What did a teammate ask IOCtopus on WhatsApp', 'whatsapp_team', 'wa_messages', $v$select created_at, direction, body from wa_messages where from_number='<number>' or to_number='<number>' order by created_at desc$v$, null, null),
('content_metrics', 'IG post performance / content pipeline status', 'meta_ioc', 'content_posts, content_state', $v$select posted_at, caption, views, reach, likes, saves from content_posts order by posted_at desc$v$, null, null),
('job_health', 'Did job X run / why did it fail / is data fresh', 'claude_api', 'freshness view, cron.job_run_details, ghl_sync_runs, meta_sync_runs, task_sync_log, slack_outbox.error, ai_queue, ai_usage', $v$select * from public.freshness; select * from cron.job_run_details where jobid=<id> order by start_time desc limit 5$v$, null, 'Raw Supabase logs last, short window.'),
('ai_cost', 'How much did the AI jobs cost', 'claude_api', 'ai_cost_daily, ai_usage', $v$select * from ai_cost_daily order by day desc limit 14$v$, null, null),
('who_owns_what', 'Who does what / who to ask / reporting line', 'slack', 'team_members, knowledge (kind = person), people rules', $v$select name, team, function, reports_to from team_members where active$v$, null, 'Personal rules in team_members.personal_rules.'),
('program_prices', 'What does DIH / DFY / DFY Scale cost', 'ghl_payments', 'app_config.program_prices, knowledge (kind = offer)', $v$select value from app_config where key='program_prices'$v$, null, 'Prices are + GST.'),
('sales_call_log', 'Sales call log / outcome / score per call', 'slack_lists', 'sales_call_log_v, sales_call_note2', $v$select * from sales_call_log_v where call_date between <from> and <to>$v$, null, 'Filled every 10 min from GHL appointments and Note 2.'),
('rules_and_skills', 'What rules has the bot been taught / what skills exist', 'claude_api', 'bot_rules_list(), skills, skill_versions', $v$select * from bot_rules_list(null); select slug, title, summary, version from skills where active$v$, null, 'Core is locked.')
on conflict (key) do update set question=excluded.question, connection_id=excluded.connection_id, source=excluded.source, how=excluded.how, live_alternative=excluded.live_alternative, caveats=excluded.caveats, updated_at=now();

create or replace function public.where_is(p text)
returns table(kind text, key text, question text, connection_id text, source text, how text, live_alternative text, caveats text, score real)
language sql stable
set search_path = public, extensions
as $f$
with q as (select lower(trim(p)) as q),
w as (select w from q, regexp_split_to_table(q.q, '\s+') w where length(w) > 2),
dp as (
  select 'data_point'::text kind, d.key, d.question, d.connection_id, d.source, d.how, d.live_alternative, d.caveats,
    ( (select count(*) from w where d.question ilike '%'||w.w||'%' or d.key ilike '%'||w.w||'%' or d.source ilike '%'||w.w||'%' or coalesce(d.caveats,'') ilike '%'||w.w||'%')::real
      + greatest(extensions.similarity(d.key, q.q), extensions.similarity(d.question, q.q)) ) as score
  from data_points d, q
),
cn as (
  select 'connection'::text kind, c.id as key, c.system||' · '||c.kind||' · '||coalesce(c.account,'') as question, c.id as connection_id,
    c.access as source, coalesce(c.read_live,'') as how, coalesce(c.write_path,'') as live_alternative,
    coalesce(c.notes,'')||' tables: '||array_to_string(c.tables,', ') as caveats,
    ( (select count(*) from w where c.id ilike '%'||w.w||'%' or c.system ilike '%'||w.w||'%' or coalesce(c.account,'') ilike '%'||w.w||'%' or array_to_string(c.tables,' ') ilike '%'||w.w||'%' or coalesce(c.notes,'') ilike '%'||w.w||'%')::real
      + greatest(extensions.similarity(c.id, q.q), extensions.similarity(c.system, q.q)) ) as score
  from connections c, q where c.status = 'active'
)
select * from (select * from dp union all select * from cn) x
where score >= 0.6
order by score desc, kind
limit 12;
$f$;
comment on function public.where_is(text) is 'Resolve a question or topic to the right data point and connection: select * from where_is(''calls booked yesterday''). Returns the table/view/function to read, the query pattern, the live alternative and caveats. Use before any Supabase or connector work.';
