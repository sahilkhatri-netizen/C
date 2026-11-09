-- Quiet gate for unrequested bot messages (9 Nov 2026). Mode in app_config 'outbox_gate_mode': observe | enforce | off.
insert into public.app_config(key, value) values ('outbox_gate_mode','observe') on conflict (key) do nothing;
insert into public.app_config(key, value) values ('outbox_gate_cap','3') on conflict (key) do nothing;

create table if not exists public.outbox_gate_log (
  id bigserial primary key, outbox_id bigint, at timestamptz default now(), mode text, decision text, reason text,
  recipients text[], purpose text, channel_id text, released_at timestamptz, digest_outbox_id bigint);
create index if not exists outbox_gate_log_day on public.outbox_gate_log (at);
alter table public.outbox_gate_log enable row level security;

-- people a message is addressed to: DM owner, or @-mentions at the start (else every team member mentioned)
create or replace function public.outbox_recipients(p_channel text, p_text text)
returns text[] language plpgsql stable security definer set search_path to 'public' as $$
declare ids text[]; lead text[]; head text;
begin
  if p_channel like 'D%' then
    return coalesce((select array_agg(user_id) from slack_channel_members where channel_id = p_channel and user_id <> 'U0C4RLGR8LT'), '{}');
  end if;
  if p_channel like 'U%' then return array[p_channel]; end if;
  select coalesce(array_agg(distinct x[1]), '{}') into ids from regexp_matches(coalesce(p_text,''), '<@(U[A-Z0-9]+)>', 'g') x;
  head := substring(coalesce(p_text,'') from '^[^A-Za-z0-9]*((?:<@U[A-Z0-9]+>[\s,&and]*)+)');
  select coalesce(array_agg(distinct x[1]), '{}') into lead from regexp_matches(coalesce(head,''), '<@(U[A-Z0-9]+)>', 'g') x;
  if cardinality(lead) = 0 then lead := ids; end if;
  return array(select u from unnest(lead) u where exists (select 1 from team_members t where t.slack_id = u and t.active));
end $$;

-- the decision, as of time p_at. p_sent_today: unrequested messages each recipient already got today (for the cap).
create or replace function public.outbox_gate_decide(p_channel text, p_thread text, p_text text, p_purpose text, p_at timestamptz, p_sent_today jsonb default null)
returns table(decision text, reason text, recipients text[])
language plpgsql stable security definer set search_path to 'public' as $$
declare ist timestamp := p_at at time zone 'Asia/Kolkata'; d date := (p_at at time zone 'Asia/Kolkata')::date;
  rec text[]; u text; cap int := coalesce((select value::int from app_config where key='outbox_gate_cap'), 3); n int;
begin
  -- streams the gate never touches: replies, work alerts to the owner, payments, urgent and confirm cards
  if coalesce(p_purpose,'') in ('chat','chat_reply','note','ghl_update','payment-alert','payment-fcb-thread','payment-fcb-fallback',
       'payment-recorded','funnel_alert','course_sync','google-confirm','google-expired','google-connected','relay','eval-alert',
       'disqualified','bank-digest','digest') then
    return query select 'send'::text, 'not gated: '||coalesce(p_purpose,'?'), '{}'::text[]; return;
  end if;
  rec := public.outbox_recipients(p_channel, p_text);
  -- stopped streams
  if p_text ~ '^⏰ <@U[A-Z0-9]+> your EOD posts in #team-eods' then
    return query select 'stop'::text, 'stopped stream: 10:30 PM EOD reminder (0 of 36 confirmed)', rec; return;
  end if;
  -- asked for: the person wrote in this DM / thread in the last 30 minutes
  if exists (select 1 from slack_messages m where m.channel_id = p_channel and m.user_id = any(rec)
               and m.msg_time between p_at - interval '30 minutes' and p_at
               and (p_thread is null or m.thread_ts = p_thread or m.ts = p_thread)) then
    return query select 'send'::text, 'asked for (person wrote here in the last 30 min)', rec; return;
  end if;
  -- quiet hours, Sundays, company off days
  if extract(isodow from ist) = 7 or exists (select 1 from ioc_holidays h where h.day = d and h.kind = 'off') then
    return query select 'hold'::text, 'off day (Sunday / company holiday)', rec; return;
  end if;
  if ist::time < time '10:00' or ist::time >= time '19:00' then
    return query select 'hold'::text, 'outside 10 AM–7 PM', rec; return;
  end if;
  -- away (only when everyone it is for is away)
  if cardinality(rec) > 0 and not exists (select 1 from unnest(rec) r where not exists (
       select 1 from people_availability a where a.slack_id = r and a.status = 'active' and d between a.starts and a.ends)) then
    return query select 'hold'::text, 'recipient away', rec; return;
  end if;
  -- daily cap per person
  foreach u in array rec loop
    n := coalesce((p_sent_today->>u)::int, (select count(*) from outbox_gate_log l where l.decision = 'send' and l.reason = 'gated: within limits'
            and u = any(l.recipients) and (l.at at time zone 'Asia/Kolkata')::date = d)::int);
    if n >= cap then
      return query select 'digest'::text, format('daily limit (%s) reached for %s', cap, u), rec; return;
    end if;
  end loop;
  return query select 'send'::text, 'gated: within limits', rec;
end $$;

create or replace function public.trg_outbox_gate() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare mode text := coalesce((select value from app_config where key='outbox_gate_mode'),'off'); r record;
begin
  if mode = 'off' or new.update_ts is not null or coalesce(new.status,'queued') <> 'queued' then return new; end if;
  select * into r from public.outbox_gate_decide(new.channel_id, new.thread_ts, new.text, new.purpose, now());
  insert into outbox_gate_log(outbox_id, mode, decision, reason, recipients, purpose, channel_id)
  values (new.id, mode, r.decision, r.reason, r.recipients, new.purpose, new.channel_id);
  if mode = 'enforce' and r.decision in ('hold','digest') then new.status := 'held'; new.error := 'gate: '||r.reason;
  elsif mode = 'enforce' and r.decision = 'stop' then new.status := 'skipped'; new.error := 'gate: '||r.reason;
  end if;
  return new;
exception when others then return new;  -- the gate must never block a message by failing
end $$;

create or replace trigger trg_outbox_gate before insert on public.slack_outbox for each row execute function public.trg_outbox_gate();

-- replay: what the gate would have done to past messages (for the approval test)
create or replace function public.outbox_gate_replay(p_from timestamptz, p_to timestamptz)
returns table(outbox_id bigint, created_at timestamptz, purpose text, decision text, reason text, recipients text[])
language plpgsql stable security definer set search_path to 'public' as $$
declare o record; r record; sent jsonb := '{}'; cur date; u text;
begin
  for o in select * from slack_outbox s where s.created_at >= p_from and s.created_at < p_to and s.update_ts is null
             and coalesce(s.status,'') not in ('deleted') order by s.created_at loop
    if cur is distinct from (o.created_at at time zone 'Asia/Kolkata')::date then sent := '{}'; cur := (o.created_at at time zone 'Asia/Kolkata')::date; end if;
    select * into r from public.outbox_gate_decide(o.channel_id, o.thread_ts, o.text, o.purpose, o.created_at, sent);
    if r.decision = 'send' and r.reason = 'gated: within limits' then
      foreach u in array r.recipients loop sent := jsonb_set(sent, array[u], to_jsonb(coalesce((sent->>u)::int,0) + 1)); end loop;
    end if;
    outbox_id := o.id; created_at := o.created_at; purpose := o.purpose; decision := r.decision; reason := r.reason; recipients := r.recipients;
    return next;
  end loop;
end $$;

do $$ declare f text; begin
  foreach f in array array['outbox_recipients(text,text)','outbox_gate_decide(text,text,text,text,timestamptz,jsonb)','outbox_gate_replay(timestamptz,timestamptz)','trg_outbox_gate()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  execute 'revoke all on public.outbox_gate_log from anon, authenticated';
end $$;
