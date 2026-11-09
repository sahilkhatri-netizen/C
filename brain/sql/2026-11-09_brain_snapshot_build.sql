CREATE OR REPLACE FUNCTION public.brain_snapshot_build()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare today date := (now() at time zone 'Asia/Kolkata')::date; out text; f record; p record; m record; cash_mtd numeric; cash_prev numeric; away text; dec text; hol text;
begin
  drop table if exists _fd;
  create temp table _fd on commit drop as
    select date, sum(spend) spend, sum(applications) applications, sum(booked) booked, sum(calls_done) calls_done, sum(sales) sales, sum(cash) cash, sum(disqualified) disqualified, sum(noshows) noshows
    from ad_daily_funnel where date >= least(date_trunc('month', today)::date, today - 14) and date < today group by date;
  select coalesce(sum(spend),0) spend, coalesce(sum(applications),0) apps, coalesce(sum(booked),0) booked, coalesce(sum(calls_done),0) calls,
         coalesce(sum(sales),0) sales, coalesce(sum(cash),0) cash, coalesce(sum(disqualified),0) dq, coalesce(sum(noshows),0) noshow
    into f from _fd where date between today - 7 and today - 1;
  select coalesce(sum(spend),0) spend, coalesce(sum(applications),0) apps, coalesce(sum(booked),0) booked, coalesce(sum(calls_done),0) calls,
         coalesce(sum(sales),0) sales, coalesce(sum(cash),0) cash
    into p from _fd where date between today - 14 and today - 8;
  select coalesce(sum(spend),0) spend, coalesce(sum(sales),0) sales, coalesce(sum(applications),0) apps, coalesce(sum(booked),0) booked
    into m from _fd where date >= date_trunc('month', today)::date and date < today;
  select coalesce(sum(amount),0) into cash_mtd from ghl_transactions_real where (created_at at time zone 'Asia/Kolkata')::date >= date_trunc('month', today)::date;
  select coalesce(sum(amount),0) into cash_prev from ghl_transactions_real
    where (created_at at time zone 'Asia/Kolkata')::date >= (date_trunc('month', today) - interval '1 month')::date
      and (created_at at time zone 'Asia/Kolkata')::date < (date_trunc('month', today) - interval '1 month')::date + (today - date_trunc('month', today)::date);
  select string_agg(format('%s %s (%s–%s)', split_part(tm.name,' ',1), replace(a.kind,'_','-'), to_char(a.starts,'DD Mon'), to_char(a.ends,'DD Mon')), ', ' order by a.starts)
    into away from people_availability a join team_members tm on tm.slack_id = a.slack_id
    where a.status = 'active' and a.ends >= today and a.starts <= today + 7;
  select string_agg(format('• %s (%s): %s', k.subject, to_char(k.meeting_date at time zone 'Asia/Kolkata','DD Mon'), left(k.fact, 220)), chr(10) order by k.meeting_date desc)
    into dec from (select * from knowledge where not superseded and kind in ('decision','rule','process') and meeting_date > now() - interval '14 days' order by meeting_date desc limit 10) k;

  select string_agg(format('%s %s (%s)', to_char(day,'Dy DD Mon'), name, kind), '; ' order by day) into hol
    from ioc_holidays where day between today and today + 14;
  out := format('As of %s IST.', to_char(now() at time zone 'Asia/Kolkata','DD Mon HH12:MI AM'))
    || chr(10) || 'KEY NUMBERS (one source: the dashboards, refreshed every 30 min; names are defined in metric_definitions, use these names and say which one you quote):'
    || coalesce(chr(10) || '• ' || public.ioc_numbers_line('this_month'), '')
    || coalesce(chr(10) || '• ' || public.ioc_numbers_line('same_days_last_month'), '')
    || coalesce(chr(10) || '• ' || public.ioc_numbers_line('last_7_days'), '')
    || coalesce(chr(10) || '• ' || public.ioc_numbers_line('prev_7_days'), '')
    || coalesce(chr(10) || '• ' || public.ioc_numbers_line('last_month'), '')
    || coalesce(chr(10) || format('• Overdue instalments now: %s clients, ₹%s · due in next 30 days: ₹%s (Ops tab)',
         (select data->'overdue_now'->>'n' from ioc_numbers where period='this_month'),
         (select to_char((data->'overdue_now'->>'amount')::numeric,'FM99,99,99,999') from ioc_numbers where period='this_month'),
         (select to_char((data->'upcoming_30d'->>'amount')::numeric,'FM99,99,99,999') from ioc_numbers where period='this_month')), '')
    || chr(10) || 'Cash collected = money received by payment date (Closers page). Revenue closed = deal value, not cash. Do not count GHL payments by entry date: old payments were bulk-entered on 8 and 17 Oct. Calls booked from ads < calls booked (all sources). Showed/no-show depend on closers updating cards. For any other range: select public.ioc_numbers_compute(from, to); definitions: select * from metric_definitions.'
    || coalesce(chr(10) || 'Away now / next 7 days: ' || away, chr(10) || 'Away: nobody logged.')
    || coalesce(chr(10) || 'Company calendar, next 14 days: ' || hol, '')
    || coalesce(chr(10) || 'Company profile (weekly, first part; full text in brain_pages company/profile): ' || (select left(regexp_replace(body,'\s+',' ','g'), 1500) from brain_pages where kind='company' and key='profile'), '')
    || coalesce(chr(10) || 'Recent decisions and rules (last 14 days, from the brain):' || chr(10) || dec, '');
  insert into brain_snapshot(id, body, built_at, funnel_days)
  values (1, out, now(), (select string_agg(format('%s: spend ₹%s · apps %s · booked %s · calls %s · sales %s · cash ₹%s', to_char(date,'Dy DD Mon'), round(spend), applications, booked, calls_done, sales, round(cash)), chr(10) order by date) from _fd where date >= today - 14))
  on conflict (id) do update set body = excluded.body, built_at = excluded.built_at, funnel_days = excluded.funnel_days;
  return out;
end $function$

