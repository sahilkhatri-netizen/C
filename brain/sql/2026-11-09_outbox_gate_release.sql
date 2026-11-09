create or replace function public.outbox_send_now(p_id bigint) returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update slack_outbox set status = 'queued', error = null where id = p_id and status = 'held';
  if found then
    perform net.http_post(url := 'https://ugiurxkbbuhtvbehpkvb.supabase.co/functions/v1/slack-events',
      headers := jsonb_build_object('Content-Type','application/json','x-sync-secret',(select value from app_config where key='sync_secret')),
      body := jsonb_build_object('action','post','id', p_id));
  end if;
end $$;

-- every 15 min: messages held for quiet hours / off day / away go out once the window is open for them
create or replace function public.outbox_gate_release() returns text language plpgsql security definer set search_path to 'public' as $$
declare l record; r record; n int := 0;
begin
  for l in select g.*, o.thread_ts, o.text from outbox_gate_log g join slack_outbox o on o.id = g.outbox_id
           where g.decision = 'hold' and g.released_at is null and o.status = 'held' order by g.at loop
    select * into r from outbox_gate_decide(l.channel_id, l.thread_ts, l.text, l.purpose, now(), null);
    if r.decision in ('send','digest') then
      perform outbox_send_now(l.outbox_id);
      update outbox_gate_log set released_at = now() where id = l.id; n := n + 1;
    end if;
  end loop;
  return format('%s released', n);
end $$;

-- 6:30 PM on working days: one DM per person with what the daily limit held back
create or replace function public.outbox_gate_digest() returns text language plpgsql security definer set search_path to 'public' as $$
declare p record; dm text; body text; did bigint; n int := 0; d date := (now() at time zone 'Asia/Kolkata')::date;
begin
  for p in select u, array_agg(g.id order by g.at) gids, array_agg(g.outbox_id order by g.at) oids,
                  string_agg('• ' || left(regexp_replace(regexp_replace(o.text, '<@U[A-Z0-9]+>\s*', '', 'g'), '\s+', ' ', 'g'), 160), chr(10) order by g.at) lines, count(*) c
           from outbox_gate_log g join slack_outbox o on o.id = g.outbox_id, unnest(g.recipients) u
           where g.decision = 'digest' and g.digest_outbox_id is null and o.status = 'held' and (g.at at time zone 'Asia/Kolkata')::date = d
           group by u loop
    select channel_id into dm from slack_channel_members m where m.user_id = p.u and m.channel_id like 'D%' limit 1;
    body := format('*Today''s other updates for you (%s)* — held back so you get at most %s pings a day:', p.c,
                   coalesce((select value from app_config where key='outbox_gate_cap'),'3')) || chr(10) || p.lines;
    insert into slack_outbox(channel_id, text, purpose) values (coalesce(dm, p.u), left(body, 3800), 'digest') returning id into did;
    update outbox_gate_log set digest_outbox_id = did where id = any(p.gids);
    update slack_outbox set status = 'skipped', error = 'gate: sent in digest #' || did where id = any(p.oids) and status = 'held';
    n := n + 1;
  end loop;
  return format('%s digests', n);
end $$;

do $$ declare f text; begin
  foreach f in array array['outbox_send_now(bigint)','outbox_gate_release()','outbox_gate_digest()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop; end $$;
