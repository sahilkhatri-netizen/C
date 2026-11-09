alter function public.ai_sql(text,boolean,boolean) rename to ai_sql_v1;
CREATE OR REPLACE FUNCTION public.ai_sql(p_sql text, p_commit boolean DEFAULT false, p_risky boolean DEFAULT false, p_asker text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  q text := regexp_replace(btrim(coalesce(p_sql,'')), ';\s*$', '');
  res jsonb; n bigint;
  is_risky boolean;
  restricted boolean;
  t text;
begin
  if q = '' then return jsonb_build_object('error','empty query'); end if;
  -- never: secrets, tokens, server files, killing sessions
  if q ~* '\m(vault|auth)\.'
     or q ~* '\m(pg_read_file|pg_read_binary_file|pg_ls_dir|lo_import|lo_export|dblink|pg_terminate_backend|pg_cancel_backend|decrypted_secret)\M'
     or q ~* '(decrypted_secret|google_rt_|google_confirm|google_push_key|ghl_sync_secrets|lead_notes_secrets)'
     or q ~* '^\s*(copy|begin|commit|rollback|savepoint|listen|set|reset|security|import)\M' then
    return jsonb_build_object('error','statement not allowed (secrets, tokens, files or transaction control)');
  end if;
  -- secrets in config and raw HTTP calls (added 9 Nov 2026)
  if q ~* '\mnet\.http_' then
    return jsonb_build_object('error','direct HTTP calls are not allowed. To run a sync/refresh edge function use: select public.run_edge(''<function-name>'', ''<json body>''::jsonb)');
  end if;
  if q ~* '(sync_secret|_secret|webhook_key|dashboard_key|2fa_pin|verify_token|hook_secrets)' then
    return jsonb_build_object('error','statement not allowed (secrets)');
  end if;
  if q ~* '\mapp_config\M' then
    if q ~* '^\s*(select|with|values|table)\M' then
      q := regexp_replace(q, '(public\.)?\mapp_config\M', 'public.app_config_public', 'gi');
    elsif q ~* '\m(select|returning)\M' then
      return jsonb_build_object('error','app_config changes must be a plain UPDATE ... WHERE key = ''x'' or INSERT ... VALUES (no SELECT / RETURNING). Read it via app_config_public.');
    end if;
  end if;
  -- privacy by person (9 Nov 2026): in a chat run the worker passes the asker's Slack id. Anyone except Aakash and
  -- Sahil reads Slack, meetings, search and bot logs through views that only show what that person may see.
  perform set_config('ioc.asker', coalesce(p_asker, ''), true);
  restricted := not public.asker_unrestricted();
  if restricted then
    if q ~* '\m(ai_queue|bot_shadow_replies|dash_chat_log|wa_messages|wa_outbox)\M' and q ~* '^\s*(select|with|values|table)\M|\mselect\M|\mreturning\M' then
      return jsonb_build_object('error','privacy: bot run logs and WhatsApp/dashboard chat logs are only readable for Aakash and Sahil');
    end if;
    if q ~* '^\s*(select|with|values|table)\M' then
      foreach t in array array['slack_messages_ist:slack_messages_seen','slack_messages:slack_messages_raw_seen','memory_chunks:memory_chunks_seen',
          'meetings:meetings_seen','meeting_insights:meeting_insights_seen','meeting_task_replies:meeting_task_replies_seen','slack_outbox:slack_outbox_seen',
          'reply_traces:reply_traces_seen','eod_drafts:eod_drafts_seen','people_actions:people_actions_seen'] loop
        q := regexp_replace(q, '(public\.)?\m' || split_part(t,':',1) || '\M', 'public.' || split_part(t,':',2), 'gi');
      end loop;
    elsif q ~* '\mselect\M' and q ~* '\m(slack_messages_ist|slack_messages|memory_chunks|meetings|meeting_insights|meeting_task_replies|reply_traces|eod_drafts|people_actions)\M' then
      return jsonb_build_object('error','privacy: read those tables in a separate SELECT first (it is filtered to what this person may see), then write');
    end if;
    q := regexp_replace(q, '(public\.)?\mioc_search\s*\(', 'public.ioc_search_seen(', 'gi');
    q := regexp_replace(q, '(public\.)?\mslack_search\s*\(', 'public.slack_search_seen(', 'gi');
    q := regexp_replace(q, '(public\.)?\mmeeting_insight_get\s*\(', 'public.meeting_insight_get_seen(', 'gi');
    q := regexp_replace(q, '(public\.)?\mslack_api\s*\(', 'public.slack_api_seen(', 'gi');
  end if;
  is_risky := q ~* '^\s*(drop|truncate|alter|create|grant|revoke|comment|reindex|cluster|vacuum|lock|notify|do|call)\M'
              or q ~* '\mdelete\s+from\M' or q ~* '\mstorage\.';
  if is_risky and not p_risky then
    return jsonb_build_object('error','RISKY statement (delete / schema change) — needs the person''s YES first. Describe exactly what will change and ask them to reply YES; run it in the run that starts from their YES.');
  end if;
  set local statement_timeout = '30s';
  begin
    begin
      if q ~* '^\s*(insert|update|merge|delete)\M' then
        if q ~* '\mreturning\M' then
          execute format('with _r as (%s) select coalesce(jsonb_agg(to_jsonb(_r)), ''[]''::jsonb) from _r', q) into res;
        else
          execute q; get diagnostics n = row_count; res := jsonb_build_object('rows_affected', n);
        end if;
      elsif q ~* '^\s*(select|with|values|table)\M' then
        begin
          execute format('select coalesce(jsonb_agg(to_jsonb(_t)), ''[]''::jsonb) from (%s) _t', q) into res;
        exception when sqlstate '0A000' then
          execute q; get diagnostics n = row_count; res := jsonb_build_object('rows_affected', n);
        end;
      elsif is_risky then
        execute q; res := jsonb_build_object('ok', true, 'ran', left(q, 200));
      else
        return jsonb_build_object('error','only SELECT / WITH / INSERT / UPDATE statements are allowed');
      end if;
      if not p_commit then
        raise exception using errcode = 'P0001', message = 'ai_shadow_rollback';
      end if;
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'ai_shadow_rollback' then raise; end if;
      return jsonb_build_object('shadow_not_saved', true, 'result', res);
    end;
    return jsonb_build_object('result', res);
  exception when others then
    return jsonb_build_object('error', sqlerrm, 'sqlstate', sqlstate);
  end;
end $function$

;
