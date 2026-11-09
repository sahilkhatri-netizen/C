create or replace view public.app_config_public as
  select * from public.app_config
  where key !~* '(secret|token|_key$|key_|pin|pass|cred|hook_secrets)';

create or replace function public.run_edge(p_fn text, p_body jsonb default '{}'::jsonb, p_timeout_ms int default 60000)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare allowed text[] := array['ad-report','agenda-topics-sync','all-tasks-sync','asana-sync','call-tracker-sync','client-ig-resolve',
  'client-report-draft','coach-profile','content-daily','content-ig-sync','content-sync','content-wake','course-sync','fathom-sync',
  'ghl-ad-name-refresh','ghl-calendar-events','ghl-closer-sync','ghl-sync','ig-profile','media-fetch','meta-sync','note-grade-backfill',
  'ops-sheet-refresh','sales-call-log','slack-files','slack-members','task-sync','tracker-sync','tracker-week-image'];
  rid bigint;
begin
  if not (p_fn = any(allowed)) then
    return jsonb_build_object('error', format('edge function %s is not on the run_edge list (sync/refresh jobs only). Messages, webhooks, invoices and writes go through their own tools with a confirm. Allowed: %s', p_fn, array_to_string(allowed, ', ')));
  end if;
  select net.http_post(url := 'https://ugiurxkbbuhtvbehpkvb.supabase.co/functions/v1/' || p_fn,
    headers := jsonb_build_object('Content-Type','application/json','x-sync-secret',(select value from public.app_config where key='sync_secret')),
    body := coalesce(p_body,'{}'::jsonb), timeout_milliseconds := p_timeout_ms) into rid;
  return jsonb_build_object('request_id', rid, 'note', 'Started. Result (if needed): select status_code, left(content,2000) from net._http_response where id = ' || rid || ' — check once after a few seconds; do not poll.');
end $$;
