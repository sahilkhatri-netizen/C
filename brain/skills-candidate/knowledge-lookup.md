## Answering questions (never guess)
Look in this order and stop as soon as you have the answer:
1. The brief: snapshot (KEY NUMBERS), thread/DM, CLIENTS MENTIONED, PEOPLE, RELATED COMPANY MEMORY. If it answers the question, answer from it — no extra lookups.
2. Numbers: select period, label, data from ioc_numbers (this_month, same_days_last_month, last_month, last_7_days, prev_7_days) or select ioc_numbers_compute('<from>','<to>'); names and meanings: metric_definitions. Always say which number you quote (cash collected vs revenue closed, calls booked from ads vs all sources).
3. A client: select * from find_client('<name as typed>') (top row if score ≥ 0.85, handles misspellings and nicknames), then public.clients and select public.client_card('<name>').
4. What was said or decided: select * from public.ioc_search('<question in plain English>', 8, <channel_id or 'meetings' or null>, <since or null>); (Hinglish → search with the English meaning). Meeting decisions: select * from public.meeting_insight_get('<topic or name>', 30). Exact words or counts: public.slack_search('<words>', '<channel part or null>', <days>, <limit>).
5. Live systems for "right now": ghl tool (or ghl_* tables if synced in the last 2 hours), asana tool.
6. How a tool works (GHL, Meta, Canva, Razorpay, Slack): web search, then give clear steps.
Missing or conflicting data → say so in one line and what would fix it. Never invent numbers.
Finding a person's call: search meetings by first name and spelling variants in title, participants, summary and transcript, across all dates; with a year or "1st", list all their calls first and pick the match.

## Real column names (use these — guessing names wastes a step)
One SQL statement per call. Name the columns; never select *.
• slack_messages_ist (view): channel_id, channel_name, ts, thread_ts, user_id, text, time_ist, msg_time, deleted — a thread = channel_id = X and (thread_ts = T or ts = T)
• slack_channels: channel_id, name, is_private · slack_outbox: id, channel_id, thread_ts, text, status, slack_ts, error, purpose, update_ts
• meeting_task_replies: id, kind, slack_user, text, msg_ts, thread_ts, channel_id, processed_at
• meetings: id, recording_id, title, meeting_type, meeting_date, duration_min, participants, summary, transcript, action_items, share_url, is_internal
• meeting_schedule: id, team, title, meeting_type, weekdays (int[] 1=Mon), start_time, end_time, attendees, channel_id, active, skip_dates, extra_dates · meeting_drafts: meeting_key, agenda_id, status, note
• ghl_contacts: id, name, email, phone, tags, utm_source, utm_campaign, utm_medium, utm_content (no first_name / full_name)
• ghl_opportunities: id, contact_id, name, pipeline_id, stage_id, status, owner_id, value, custom_fields · pipeline_cards (view): id, contact_id, name, stage, status, value, owner_id, offer, lead_grade, won_date
• ghl_appointments: id, contact_id, calendar_id, assigned_user_id, status, title, start_time, end_time, date_added, date_updated, deleted
• ghl_events: id, event_type, opportunity_id, contact_id, old_value, new_value, occurred_at · lead_timeline (view): name, opportunity_id, occurred_at, event_type, from_value, to_value
• ghl_transactions_real: id, contact_id, contact_name, amount, status, created_at, fulfilled_at (payment date — count cash by this, status = 'succeeded') · ghl_invoices: id, invoice_number, contact_name, status, total, amount_paid, amount_due, issue_date, due_date
• gcal_events: id, account_id, g_event_id, summary, status, start_at, end_at, attendees
• teams_tasks_open (view): row_id, task, owner, due, done, team, source · people_availability: slack_id, starts, ends, kind, status (no table people_away)
• team_members: name, slack_id, team, role, reports_to, ghl_user_id, whatsapp_number, work_days, active
• clients: name, aliases, program, status, ig_handle, phone, email, asana_task_gid, meta_ad_account_id, end_date
• meta_ads: ad_id, ad_name, campaign_name, effective_status · meta_insights_daily: ad_id, date, spend, leads, clicks, ctr
• Functions: metrics_summary(date, date) takes dates; quick_numbers: period, from_d, to_d, data.
Not sure of a column → one query: select column_name from information_schema.columns where table_name = '<t>'.

## IOC facts
• Programs (GHL "Offer"): DIH = Sales Jumpstart (₹1L + GST) · DFY = Sales Accelerator (₹3L + GST) · DFY Scale = Sales Multiplier (₹6L + GST). FCB (₹499/₹998) is low-ticket, reported separately, never counted as DIH.
• FCB buyer UTMs are in the ORIGIN section of the FCB BUYER NOTE in GHL.
• Meeting Log hours / counts: meeting_log_v (sum duration_min).
• Lead grading, the DFY ad report funnel and the application form: lead-grade and dfy-ad-report skills.
• When you find a client field that was empty (IG, phone, email), write it back to public.clients; add new spellings to clients.aliases.
