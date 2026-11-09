create table if not exists public.embed_query_cache (h text primary key, v extensions.vector(384), at timestamptz default now());
alter table public.embed_query_cache enable row level security;
revoke all on public.embed_query_cache from anon, authenticated;
create or replace function public.mem_embed_query(p_text text)
 returns extensions.vector language plpgsql security definer set search_path to 'public' as $function$
declare k text; r extensions.http_response; j jsonb; h text := md5(left(coalesce(p_text,''), 1500)); v extensions.vector;
begin
  select c.v into v from embed_query_cache c where c.h = h;           -- same question again (retries, brief + search): no HTTP call
  if v is not null then return v; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'embed_key' limit 1;
  -- 9 Nov 2026: was 8000 ms, the same as the whole API call's limit, so a slow embedding killed the brief.
  -- Now 2.5 s; on timeout ioc_search falls back to keyword search.
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '2500');
  select * into r from extensions.http((
    'POST', 'https://ugiurxkbbuhtvbehpkvb.supabase.co/functions/v1/embed',
    array[extensions.http_header('x-embed-key', k)], 'application/json',
    jsonb_build_object('texts', jsonb_build_array(left(p_text, 1500)))::text)::extensions.http_request);
  if r.status <> 200 then raise exception 'embed failed: % %', r.status, left(r.content, 200); end if;
  j := r.content::jsonb;
  v := (j->'embeddings'->0)::text::extensions.vector;
  insert into embed_query_cache(h, v) values (h, v) on conflict (h) do nothing;
  return v;
end $function$;
revoke all on function public.mem_embed_query(text) from public, anon, authenticated;
grant execute on function public.mem_embed_query(text) to service_role;
