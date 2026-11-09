create table if not exists public.metric_definitions (
  key text primary key, name text not null, meaning text not null, source text not null,
  not_to_confuse text, sort int, confirmed_by text, confirmed_at timestamptz, updated_at timestamptz default now());

insert into public.metric_definitions(key,name,meaning,source,not_to_confuse,sort) values
('ad_spend','Ad spend','Meta ad spend in the range (IST days).','Ads tab: ads_summary().totals.spend',null,10),
('applications','Applications','Application forms submitted from ads in the range, qualified or not.','Ads tab: ads_summary().totals.applications','Not leads (all contacts) and not calls booked.',20),
('disqualified','Disqualified applications','Applications that landed in Disqualified App.','Ads tab: ads_summary().totals.disqualified',null,30),
('booked_from_ads','Calls booked from ads','Strategy calls booked that trace back to an ad.','Ads tab: ads_summary().totals.booked','Smaller than Calls booked (all sources), which includes organic, referrals and rebooks.',40),
('cost_per_booked_call','Cost per booked call from ads','Ad spend ÷ qualified calls booked from ads (CPQBC). Target ₹6,000.','Ads tab: ads_summary().totals.cpqbc',null,50),
('new_leads','New leads','Contacts created in GHL in the range (not imported).','Closers page: metrics_summary().leads.new_leads_created',null,60),
('calls_booked','Calls booked (all sources)','Strategy calls booked in the range, any source.','Closers page: metrics_summary().sales_team.booked','Bigger than Calls booked from ads.',70),
('calls_confirmed','Calls confirmed','Booked calls marked confirmed in the range.','Closers page: sales_team.confirmed',null,80),
('calls_showed','Calls showed','Calls the lead attended in the range.','Closers page: sales_team.showed','Depends on closers updating the card; low numbers can mean cards not updated.',90),
('no_shows','No-shows','Confirmed calls the lead missed.','Closers page: sales_team.no_show',null,100),
('cancelled','Calls cancelled','Booked calls cancelled in the range.','Closers page: sales_team.cancelled',null,110),
('sales_closed','Sales closed','Programme sales won in the range (GHL won + sales sheet).','Closers page: sales_team.closed','Not FCB ₹499/₹998 purchases. Not ad-attributed sales.',120),
('revenue_closed','Revenue closed','Deal value (incl. GST) of sales closed in the range, paid or not.','Closers page: sales_team.revenue','Not cash. A ₹3.54L sale paid in 2 parts adds ₹3.54L revenue but ₹1.77L cash.',130),
('cash_collected','Cash collected','Money actually received in the range, by payment date, from any sale (GHL succeeded payments + sales sheet). The headline cash number.','Closers page: sales_team.cash','Not counted by entry date: on 8 and 17 Oct old payments from Mar–Sep were entered in bulk. Pending/failed attempts are excluded.',140),
('cash_ops','Cash collected (Ops tab)','Cash the Ops tab counts against instalment plans.','Ops tab: payments.ops_cash_collected.ghl + manual','Can be lower than Cash collected when a payment has no instalment plan or came via the sales sheet.',150),
('instalments_due','Instalments due','Instalments whose due date falls in the range and how much of that is paid.','Ops tab: payments.collections',null,160),
('overdue_now','Overdue now','Instalments past due and unpaid, as of today (count and ₹).','Ops tab: payments.overdue_now','Only clients with an instalment plan in Ops; Asana pending amounts are typed by hand and can differ.',170),
('upcoming_30d','Due in the next 30 days','Instalments due in the next 30 days, as of today.','Ops tab: payments.upcoming_30d',null,180)
on conflict (key) do update set name=excluded.name, meaning=excluded.meaning, source=excluded.source, not_to_confuse=excluded.not_to_confuse, sort=excluded.sort, updated_at=now();

create table if not exists public.ioc_numbers (
  period text primary key, label text, from_d date, to_d date, data jsonb, computed_at timestamptz);

create or replace function public.ioc_numbers_compute(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare m jsonb; a jsonb; st jsonb; t jsonb; pay jsonb;
begin
  m := public.metrics_summary(p_from, p_to);
  a := public.ads_summary(p_from, p_to);
  st := coalesce(m->'sales_team','{}'); t := coalesce(a->'totals','{}'); pay := coalesce(m->'payments','{}');
  return jsonb_build_object(
    'ad_spend', t->'spend', 'applications', t->'applications', 'disqualified', t->'disqualified',
    'booked_from_ads', t->'booked', 'cost_per_booked_call', t->'cpqbc',
    'new_leads', m->'leads'->'new_leads_created',
    'calls_booked', st->'booked', 'calls_confirmed', st->'confirmed', 'calls_showed', st->'showed',
    'no_shows', st->'no_show', 'cancelled', st->'cancelled',
    'sales_closed', st->'closed', 'revenue_closed', st->'revenue', 'cash_collected', st->'cash',
    'cash_ops', coalesce((pay->'ops_cash_collected'->>'ghl')::numeric,0) + coalesce((pay->'ops_cash_collected'->>'manual')::numeric,0),
    'instalments_due', pay->'collections',
    'overdue_now', jsonb_build_object('n', pay->'overdue_now'->'n', 'amount', pay->'overdue_now'->'amount'),
    'upcoming_30d', jsonb_build_object('n', pay->'upcoming_30d'->'n', 'amount', pay->'upcoming_30d'->'amount'));
end $$;

create or replace function public.ioc_numbers_refresh()
returns text language plpgsql security definer set search_path to 'public' as $$
declare d date := (now() at time zone 'Asia/Kolkata')::date; r record; n int := 0;
  ms date := date_trunc('month', d)::date; lms date := (date_trunc('month', d) - interval '1 month')::date;
begin
  for r in select * from (values
      ('this_month', 'Month to date', ms, d),
      ('same_days_last_month', 'Same days last month', lms, least(lms + (d - ms), (ms - 1))),
      ('last_month', 'Last month (full)', lms, ms - 1),
      ('last_7_days', 'Last 7 days (to yesterday)', d - 7, d - 1),
      ('prev_7_days', 'The 7 days before that', d - 14, d - 8)) v(p, l, f, t) loop
    begin
      insert into public.ioc_numbers(period, label, from_d, to_d, data, computed_at)
      values (r.p, r.l, r.f, r.t, public.ioc_numbers_compute(r.f, r.t), now())
      on conflict (period) do update set label=excluded.label, from_d=excluded.from_d, to_d=excluded.to_d, data=excluded.data, computed_at=now();
      n := n + 1;
    exception when others then raise warning 'ioc_numbers % failed: %', r.p, sqlerrm;
    end;
  end loop;
  return format('%s periods refreshed', n);
end $$;

-- one line per period, readable, with the canonical names
create or replace function public.ioc_numbers_line(p_period text)
returns text language sql stable security definer set search_path to 'public' as $$
  select format('%s (%s–%s): cash collected ₹%s · sales closed %s (revenue ₹%s) · ad spend ₹%s · applications %s (%s disqualified) · calls booked from ads %s, all sources %s · showed %s · no-shows %s · cost per booked call from ads %s',
    label, to_char(from_d,'DD Mon'), to_char(to_d,'DD Mon'),
    to_char(coalesce((data->>'cash_collected')::numeric,0),'FM99,99,99,999'), data->>'sales_closed',
    to_char(coalesce((data->>'revenue_closed')::numeric,0),'FM99,99,99,999'),
    to_char(coalesce((data->>'ad_spend')::numeric,0),'FM99,99,999'), data->>'applications', data->>'disqualified',
    data->>'booked_from_ads', data->>'calls_booked', data->>'calls_showed', data->>'no_shows',
    coalesce('₹'||to_char((data->>'cost_per_booked_call')::numeric,'FM99,99,999'),'n/a'))
  from public.ioc_numbers where period = p_period
$$;
