create table if not exists public.zz_ab_runs (id bigserial primary key, case_id text, orig_id bigint, mode text, reply_id bigint, queue_id bigint, created_at timestamptz default now());
create or replace function public.zz_ab_start(p_case text, p_orig bigint, p_mode text, p_text text default null) returns bigint
language plpgsql security definer set search_path to 'public' as $$
declare o record; nid bigint; qid bigint; pl text;
begin
  select * into o from meeting_task_replies where id = p_orig;
  insert into meeting_task_replies(agenda_id, kind, slack_user, text, msg_ts, thread_ts, channel_id, fired, fire_note)
  values (o.agenda_id, o.kind, o.slack_user, coalesce(p_text, o.text), o.msg_ts, o.thread_ts, o.channel_id, true,
          case when p_mode = 'candidate' then 'candidate test 9 Nov' else 'ab test current 9 Nov' end) returning id into nid;
  select payload into pl from ai_queue where job = 'ioctopus' and ref = p_orig::text and payload like 'CHAT RUN%' order by id limit 1;
  if pl is null then
    pl := format('CHAT RUN: meeting_task_replies.id=%s. <@%s> sent the IOC app a DIRECT MESSAGE in DM channel %s, message ts %s. Answer via slack_outbox with channel_id=%s and thread_ts=null (reply in the DM, not a thread).', nid, o.slack_user, o.channel_id, o.msg_ts, o.channel_id);
  else
    pl := replace(pl, 'meeting_task_replies.id=' || p_orig, 'meeting_task_replies.id=' || nid);
    if p_text is not null then pl := replace(pl, o.text, p_text); end if;
  end if;
  insert into ai_queue(job, ref, payload, shadow, dedupe_key) values ('ioctopus', nid::text, pl, true, 'ab-' || nid) returning id into qid;
  insert into zz_ab_runs(case_id, orig_id, mode, reply_id, queue_id) values (p_case, p_orig, p_mode, nid, qid);
  perform net.http_post(url := 'https://ugiurxkbbuhtvbehpkvb.supabase.co/functions/v1/ai-worker',
    headers := jsonb_build_object('Content-Type','application/json','x-sync-secret',(select value from app_config where key='sync_secret')),
    body := jsonb_build_object('queue_id', qid), timeout_milliseconds := 5000);
  return qid;
end $$;
revoke all on function public.zz_ab_start(text,bigint,text,text) from public, anon, authenticated;
alter table public.zz_ab_runs enable row level security;
