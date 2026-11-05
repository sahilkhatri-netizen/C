-- One row per Supabase copy of an external system: when it was last filled and how old it is.
-- Usage: select * from public.freshness;
create or replace view public.freshness
with (security_invoker = true) as
with f(domain, copy_of, last_synced, cadence) as (
  select 'GHL',      'ghl_opportunities / pipeline_cards', max(synced_at),  'ghl-sync every 6h + webhooks'          from public.ghl_opportunities
  union all select 'GHL',      'ghl_appointments',    max(synced_at),   'ghl-closer-sync every 2h'                from public.ghl_appointments
  union all select 'GHL',      'ghl_transactions',    max(synced_at),   'ghl-closer-sync every 2h, full nightly'  from public.ghl_transactions
  union all select 'GHL',      'ghl_events (webhooks)', max(received_at), 'realtime'                              from public.ghl_events
  union all select 'Meta',     'meta_insights_daily', max(synced_at),   'meta-sync 06:45 and 09:45 IST'           from public.meta_insights_daily
  union all select 'Slack',    'slack_messages',      max(msg_time),    'slack-events realtime'                   from public.slack_messages
  union all select 'WhatsApp', 'wa_messages',         max(created_at),  'whatsapp-webhook realtime'               from public.wa_messages
  union all select 'WhatsApp', 'wa_group_messages',   max(created_at),  'wa-group-ingest realtime'                from public.wa_group_messages
  union all select 'Fathom',   'meetings',            max(created_at),  'fathom-sync every 6h'                    from public.meetings
  union all select 'Google',   'gcal_events',         max(synced_at),   'push watch, renewed nightly'             from public.gcal_events
  union all select 'Asana',    'asana_tasks',         max(synced_at),   'asana-sync 09:30 and 16:30 IST'          from public.asana_tasks
  union all select 'Tasks',    'teams_tasks',         max(seen_at),     'task-sync hourly'                        from public.teams_tasks
  union all select 'Content',  'content_posts',       max(synced_at),   'content-ig-sync daily 07:57 IST'         from public.content_posts
)
select domain, copy_of, last_synced,
       to_char(last_synced at time zone 'Asia/Kolkata', 'DD Mon HH24:MI') || ' IST' as last_synced_ist,
       date_trunc('minute', now() - last_synced) as age,
       cadence
from f
order by domain, copy_of;

comment on view public.freshness is 'How old each Supabase copy of an external system is (GHL, Meta, Slack, WhatsApp, Fathom, Google, Asana, tasks, content). Check before quoting a copy as current; use the live connector when age matters.';
