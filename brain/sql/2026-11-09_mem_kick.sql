CREATE OR REPLACE FUNCTION public.mem_kick()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text; n int; calls int; i int;
begin
  select count(*) into n from memory_chunks where embedding is null and embed_error is null and not gone;
  if n = 0 then return 'nothing pending'; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'embed_key' limit 1;
  calls := least(2, ceil(n / 6.0)::int);
  for i in 0..calls - 1 loop
    perform net.http_post(url := 'https://ugiurxkbbuhtvbehpkvb.supabase.co/functions/v1/embed',
      headers := jsonb_build_object('x-embed-key', k, 'Content-Type', 'application/json'),
      body := jsonb_build_object('process', true, 'limit', 6, 'offset', i * 6),
      timeout_milliseconds := 60000);
  end loop;
  return format('kicked %s calls, pending %s', calls, n);
end $function$

