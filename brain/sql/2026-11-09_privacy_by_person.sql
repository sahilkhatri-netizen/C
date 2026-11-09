-- Who is asking (set by ai_sql for chat runs; null = scheduled job / no person → no filter)
create or replace function public.asker_id() returns text language sql stable as $$
  select nullif(current_setting('ioc.asker', true), '') $$;

create or replace function public.asker_unrestricted() returns boolean language sql stable security definer set search_path to 'public' as $$
  select public.asker_id() is null
      or public.asker_id() = any(string_to_array(coalesce((select value from app_config where key='bot_trainers'),'U07Q5BDGA87,U0B5K5FB7M4'), ',')) $$;

-- channels the asker may read: public channels, channels they are a member of, their own DMs with the bot
create or replace function public.asker_channels() returns text[] language sql stable security definer set search_path to 'public' as $$
  select coalesce(array_agg(distinct c), '{}') from (
    select channel_id c from slack_channels where is_private = false
    union select channel_id from slack_channel_members where user_id = public.asker_id() and channel_id not like 'D%'
    union select channel_id from meeting_task_replies where slack_user = public.asker_id() and channel_id like 'D%'
  ) x $$;

-- meetings the asker may read: they took part, or it is a team meeting (internal, 3+ speakers)
create or replace function public.asker_meetings() returns bigint[] language sql stable security definer set search_path to 'public' as $$
  with me as (select lower(email) em, lower(split_part(name,' ',1)) fn from team_members where slack_id = public.asker_id())
  select coalesce(array_agg(m.id), '{}') from meetings m left join me on true
  where (me.em is not null and m.participants::text ilike '%' || me.em || '%')
     or (me.fn is not null and exists (select 1 from unnest(coalesce(m.speakers,'{}')) s where lower(s) like me.fn || '%'))
     or (coalesce(m.is_internal,false) and coalesce(array_length(m.speakers,1),0) >= 3) $$;

create or replace view public.slack_messages_seen as
  select * from public.slack_messages_ist where public.asker_unrestricted() or channel_id in (select unnest(public.asker_channels()));
create or replace view public.slack_messages_raw_seen as
  select * from public.slack_messages where public.asker_unrestricted() or channel_id in (select unnest(public.asker_channels()));
create or replace view public.memory_chunks_seen as
  select * from public.memory_chunks where public.asker_unrestricted()
    or (source_type = 'slack' and channel_id in (select unnest(public.asker_channels())))
    or (source_type = 'meeting' and split_part(source_id, ':', 1)::bigint in (select unnest(public.asker_meetings())))
    or source_type not in ('slack','meeting');
create or replace view public.meetings_seen as
  select * from public.meetings where public.asker_unrestricted() or id in (select unnest(public.asker_meetings()));
create or replace view public.meeting_insights_seen as
  select * from public.meeting_insights i where public.asker_unrestricted()
    or exists (select 1 from public.meetings m where m.id in (select unnest(public.asker_meetings())) and (m.recording_id::text = i.recording_id::text or m.meeting_key = i.meeting_key));
create or replace view public.meeting_task_replies_seen as
  select * from public.meeting_task_replies where public.asker_unrestricted() or channel_id in (select unnest(public.asker_channels()));
create or replace view public.slack_outbox_seen as
  select * from public.slack_outbox where public.asker_unrestricted() or channel_id in (select unnest(public.asker_channels()));
create or replace view public.reply_traces_seen as
  select * from public.reply_traces where public.asker_unrestricted() or asker = public.asker_id()
    or (channel_id not like 'D%' and channel_id in (select unnest(public.asker_channels())));
create or replace view public.eod_drafts_seen as
  select * from public.eod_drafts where public.asker_unrestricted() or user_id = public.asker_id();
create or replace view public.people_actions_seen as
  select * from public.people_actions where public.asker_unrestricted() or target = public.asker_id()
    or (channel_id not like 'D%' and channel_id in (select unnest(public.asker_channels())));

create or replace function public.ioc_search_seen(p_query text, p_k integer default 8, p_channel text default null, p_since timestamptz default null, p_skip_thread text default null)
returns table(score numeric, at_ist text, who text, channel text, link text, snippet text, source_id text)
language plpgsql stable security definer set search_path to 'public' as $$
declare a text := public.asker_id();
begin
  if public.asker_unrestricted() then
    return query select * from public.ioc_search(p_query, p_k, p_channel, p_since, p_skip_thread);
  else
    return query select s.* from public.ioc_search(p_query, greatest(p_k * 3, 24), p_channel, p_since, p_skip_thread) s
      where public.brain_can_see(a, s.source_id, null) limit p_k;
  end if;
end $$;

create or replace function public.slack_search_seen(p_query text, p_channel text default null, p_days integer default 30, p_limit integer default 50)
returns table(channel_name text, time_ist timestamp, user_id text, text text, ts text, thread_ts text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if public.asker_unrestricted() then
    return query select * from public.slack_search(p_query, p_channel, p_days, p_limit);
  else
    return query select s.* from public.slack_search(p_query, p_channel, p_days, p_limit * 3) s
      where s.channel_name in (select c.name from slack_channels c where c.channel_id in (select unnest(public.asker_channels())))
      limit p_limit;
  end if;
end $$;

create or replace function public.meeting_insight_get_seen(p_search text default null, p_days integer default 30)
returns table(meeting_date timestamptz, title text, meeting_type text, summary text, decisions jsonb, tasks jsonb, blockers jsonb, open_questions jsonb, comparison jsonb, fathom_diff text, share_url text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if public.asker_unrestricted() then
    return query select * from public.meeting_insight_get(p_search, p_days);
  else
    return query select g.* from public.meeting_insight_get(p_search, p_days) g
      where exists (select 1 from meetings m where m.id in (select unnest(public.asker_meetings())) and m.share_url is not distinct from g.share_url and m.title is not distinct from g.title);
  end if;
end $$;

-- Slack API reads of a channel the asker can't see are refused
create or replace function public.slack_api_seen(p_method text, p_args jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare ch text := coalesce(p_args->>'channel', p_args->>'channel_id');
begin
  if not public.asker_unrestricted() and ch is not null and p_method ~* '^(conversations\.(history|replies|info|members)|pins\.list|bookmarks\.list|files\.list)$'
     and not (ch = any(public.asker_channels())) then
    raise exception 'privacy: this person is not a member of channel %, so its messages are not shown to them', ch;
  end if;
  return public.slack_api(p_method, p_args);
end $$;
