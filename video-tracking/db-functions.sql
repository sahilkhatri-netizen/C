-- LIVE database pieces of the video tracking, copied from Supabase on 14 Nov 2026 (project ugiurxkbbuhtvbehpkvb).
-- Tables: video_watch, video_watch_events (+ detail jsonb), video_hour_posts. Cron: video-hour-check-5min → select public.video_hour_check();

-- 45 min after a booking: Offer video % (+ testimonials) as a reply in the booking thread, tagging the closer.
CREATE OR REPLACE FUNCTION public.video_hour_check()
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_start timestamptz; r record; v_pct int; v_hint text; v_text text; v_oid bigint; n int := 0;
begin
  select min(e.at) into v_start
    from video_watch_events e join ghl_contacts c on c.id = e.contact_id
   where e.result like 'saved%' and not ('internal-test' = any(coalesce(c.tags, '{}')));
  if v_start is null then return 'waiting for the page script (no real tracking ping yet)'; end if;

  for r in
    select lp.appointment_id, lp.contact_id, o.channel_id, o.slack_ts,
           a.status, coalesce(a.deleted, false) deleted, a.start_time,
           coalesce(nullif(c.name, ''), 'this lead') lead_name, tm.slack_id closer_slack
      from ioc_live_posts lp
      join slack_outbox o on o.id = lp.outbox_id
      left join ghl_appointments a on a.id = lp.appointment_id
      left join ghl_contacts c on c.id = lp.contact_id
      left join team_members tm on tm.ghl_user_id = a.assigned_user_id and tm.active
     where lp.kind = 'booking' and lp.mode = 'live' and o.slack_ts is not null and lp.appointment_id is not null
       and lp.created_at >= v_start
       and lp.created_at <= now() - interval '45 minutes'
       and lp.created_at >  now() - interval '6 hours'
       and not exists (select 1 from video_hour_posts v where v.appointment_id = lp.appointment_id)
     order by lp.created_at
     limit 20
  loop
    if r.deleted or r.status in ('cancelled', 'invalid') or (r.start_time is not null and r.start_time < now()) then
      insert into video_hour_posts(appointment_id, contact_id, note) values (r.appointment_id, r.contact_id, 'skipped: ' || coalesce(r.status, '?'))
      on conflict do nothing;
      continue;
    end if;
    select max_pct into v_pct from video_watch where contact_id = r.contact_id and media_id = 'offer-breakdown';
    v_hint := case
      when v_pct >= 75 then ':white_check_mark: Offer video watched — go straight to triage.'
      when v_pct >= 25 then ':eyes: Partly watched — ask what stood out and ask them to finish it before the call.'
      else ':point_right: Send the Offer Breakdown video on WhatsApp and ask them to reply WATCHED.'
    end;
    v_text := coalesce('<@' || r.closer_slack || '> ', '') || ':tv: *Offer video check · 45 min after booking* — ' || r.lead_name || chr(10)
      || video_line(r.contact_id, 'offer-breakdown', 'Offer Breakdown video') || chr(10)
      || video_testimonial_line(r.contact_id) || chr(10)
      || v_hint || chr(10)
      || '_Counted only with sound on, on the phone/browser they applied from — "not tracked" doesn''t mean they didn''t watch._';
    insert into slack_outbox(channel_id, thread_ts, text, purpose) values (r.channel_id, r.slack_ts, v_text, 'note') returning id into v_oid;
    insert into video_hour_posts(appointment_id, contact_id, outbox_id, note) values (r.appointment_id, r.contact_id, v_oid, 'posted')
    on conflict do nothing;
    n := n + 1;
  end loop;
  return n || ' posted';
end $function$;

CREATE OR REPLACE FUNCTION public.video_line(p_contact text, p_media text, p_label text)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select '• *' || p_label || '*: ' || coalesce(
    (select case when w.max_pct >= 95 then 'watched fully (' else 'watched ' || w.max_pct || '% (' end
            || round(w.watched_sec / 60.0) || ' of ' || round(coalesce(w.duration_sec, 0) / 60.0) || ' min) · last '
            || to_char(w.last_at at time zone 'Asia/Kolkata', 'Dy FMHH12:MI AM')
       from video_watch w where w.contact_id = p_contact and w.media_id = p_media),
    'not tracked yet')
$function$;

CREATE OR REPLACE FUNCTION public.video_testimonial_line(p_contact text)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select '• *Testimonials*: ' || coalesce(
    (select case
        when w.plays > 0 then
          'watched ' || w.plays || ' of ' || coalesce((w.detail->>'total')::int, w.plays) || ' (' || greatest(1, round(w.watched_sec / 60.0)) || ' min)'
          || coalesce(' — ' || (select string_agg(split_part(c->>'n', ' - ', 1), ', ')
                                 from (select c from jsonb_array_elements(w.detail->'clips') c
                                        where (c->>'d')::numeric > 0 and (c->>'w')::numeric >= (c->>'d')::numeric * 0.5 and coalesce(c->>'n','') <> ''
                                        limit 6) x), '')
        else 'started ' || coalesce(jsonb_array_length(w.detail->'clips'), 0) || ', none watched halfway'
      end || ' · last ' || to_char(w.last_at at time zone 'Asia/Kolkata', 'Dy FMHH12:MI AM')
       from video_watch w where w.contact_id = p_contact and w.media_id = 'testimonials'),
    'none watched')
$function$;
