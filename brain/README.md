# IOC company brain

Goal (7 Nov 2026): IOCtopus and every AI job answer like someone who knows the whole company,
including things the asker did not think to ask. AI spend target: under $180 a month (target, not a hard stop;
the existing `ai_monthly_cap_usd` stays at 190).

Everything lives in the Supabase project `ugiurxkbbuhtvbehpkvb`. No new software.

## Plan

| Phase | What | Status |
|---|---|---|
| 1 | Give the bot what the company already knows at answer time | **Live 7 Nov** |
| 2 | Internal memory + learning: nightly fact learning restarted, team member cards, company snapshot | **Live 7 Nov** |
| 3 | Company model: deeper per-person / per-topic pages (snapshot + person cards are the first version) | |
| 4 | Reasoning: hard questions get Opus with thinking, research steps, self-check with sources | |
| 5 | Insight engine (internal): daily brain brief | **Live 7 Nov** |
| 6 | One brain everywhere (MCP server) + learning from draft-vs-sent edits + weekly scored test set | |

Scope decision (7 Nov): internal team and business first. Client WhatsApp groups and client-facing work come later.

## Phase 2 + 5, internal (live 7 Nov 2026)

- Fact learning had stopped: the old `nightly_review` scheduled task was retired around 8 Oct and the new
  `daily_review` ai_job only edits skills. New ai_job `brain_learn` (Sonnet, ~4 calls, ~$0.08/night, cron
  `ai-brain-learn` 12:40 AM IST) reads `brain_day_digest(day)` (internal meetings + insights, people's Slack in team
  channels, Aakash/Sahil DMs and WhatsApp to the bot, EODs; Slack IDs turned into names by `slack_names()`),
  checks proposals with `brain_fact_candidates()` and saves with `knowledge_save_batch()` (marks older facts
  superseded). Backfill of 8 Oct to 5 Nov runs one day every 4 min (`brain-backfill`, unschedules itself).
- `person_card()` now adds: open/overdue Team Tasks (with a note that the list is not fully maintained), what is
  due this week, open loops they owe, latest EOD, and what they own.
- `brain_snapshot` (rebuilt every 30 min, `brain-snapshot-30m`): ads funnel last 7 days vs previous 7, month to
  date, GHL cash vs same days last month, who is away, company calendar, recent decisions. Loaded into every reply.
- ai_job `brain_insights` (cron `ai-brain-insights`, 9:50 AM IST Mon-Sat, skips company off days): reads
  `brain_insight_inputs()` (snapshot, funnel by day, meeting promises with no task, open loops, over-nudged people,
  task load, recent facts, its own last briefs) and DMs a 3-5 point brief. Logged in `brain_insights_log`.

Issues found while building (for a human to decide):
- Team Tasks list is mostly stale (e.g. 154 of Suchita's 188 open tasks overdue, 121 of Aakash's 140).
- The bot contacted six people 6-11 times each on 6 Nov, above the 3-nudges-a-day rule. Fixed 7 Nov, see below.
- Tracker vs Asana disagree for some clients (e.g. Dolly: tracker 1 sale, Asana/weekly review 0).

## Answer quality fix (9 Nov 2026)

Problem (from real replies, not missing data): on 9 Nov Sahil asked five times how to give 499-bundle buyers course
access; the bot read "tg" as Telegram, said it could not search the web, gave "general guesses" with disclaimers, and
re-listed the same notes each time. Suchita's "Client Experience Report" / "Tuesday's Report & Asana - Test Phase"
requests were searched as literal file names. Causes: (1) the 7 Nov routing sent how-to and follow-up questions to
Haiku; (2) web search was off for IOCtopus; (3) the answer guide pushed "never invent" without "understand and help".

Changes:
- `ai_jobs.ioctopus.web = true` (web search + fetch).
- Screen: how-to / explain / research questions, follow-ups where the person repeats or corrects, and any question
  from Aakash or Sahil now go to Sonnet.
- New "HOW TO ANSWER WELL" block in `ioctopus_brief`: understand shorthand / typos / Hinglish / the team's own names
  for things; try every tool (incl. web) before "could not find"; tool how-tos are general knowledge, give steps;
  a repeat or correction means the last answer failed, change approach; no parroting, no repeating the thread;
  one-fact answers are one plain line.
- Shadow test on the same question (queue 1421): Sonnet, 2 web searches, HighLevel-sourced steps (Memberships > Offers,
  workflow with Course Grant Offer on a tag, per-buyer routine), $0.21. Nothing was posted.

## Stuck situations detector (8 Nov 2026)

Goal: spot things like Hetal's case without being told: money overdue, a decision made but not carried out,
systems that disagree, the same item carried over in EODs, nobody reviewing.

- `brain_stuck_cases(min_score)` scores every signed, not-offboarded client from Asana card status and pending
  payment, GHL invoices still owing, open Asana tasks while paused, EOD "Overdue" carry-overs (21 days), last weekly
  review, the latest pause/discontinue/extension/refund fact with nothing learned since (60 days), and meeting
  mentions (14 days). Names match on the full name, or the first name when unique and not a team member's.
  Contracts that ended 60+ days ago are capped at score 2 (one-time clean-up, not daily news).
- Cached in `brain_stuck` by `brain_stuck_refresh()` every 2 h (cron `brain-stuck-2h`; ~18 s; old rows are marked
  `active = false`, never deleted).
- Used by: `client_card` (a "⚠ STUCK" line for score 4+, so IOCtopus raises it whenever the client comes up), the
  daily brief inputs (top 8, with instructions: what was decided, what is not done, who must act, recommended next
  step) and the Sunday deep pass inputs.
- Asana status now drives the client list: trigger `asana_client_to_index` copies Paused/Parked → paused and
  Off Boarded/Terminated/Refunded → offboarded (and back to active when a phase resumes); 10 mismatches fixed on
  8 Nov (Hetal, Sai Ram, Nitish were paused in Asana but active in `clients`).
- Ops: `ops_month_plan` puts instalments of paused / terminated / parked clients, or 3+ weeks late, in `in.at_risk`
  instead of `in.sure` (usable cash). Page change in ioc-dashboards `site/ops.html` (branch commit 18b794b).
- Asana keeps status in several places, and they mean different things: the card's Status field (service: phase /
  Paused / Due Payment / Parked / Re Offer / Refunded / Terminated / Off Boarded), the weekly review comment on the card
  ("campaign paused" = ads stopped, not the service), the NOTES field (e.g. extensions), and the client project
  (open delivery tasks; project status is not used). Ops at-risk now covers every Status that means "don't count
  this money"; the stuck detector adds "ads stopped per latest weekly review" (only the latest review counts) and
  scores it higher when the card still says an active phase.
- First run (8 Nov): Hetal Panchal 11, Chaitali Khamar 6, Sai Ram 6, then Gopal Verma, Roshan, Neehan, Manjinder,
  Sagar, Nitish (4). Gap found: Hetal's WhatsApp group is not connected to the group reader.

## Scheduled Claude tasks instead of API for batch brain work (7-8 Nov 2026)

Batch jobs that nobody waits on run as scheduled Claude Code tasks (account usage, no API bill). The API jobs
stay as automatic fallbacks two hours later, and only run when `brain_runs` has no row for that job and day.

| Scheduled task (IST) | Does | API fallback |
|---|---|---|
| IOC brain: nightly learning, 1:10 AM daily | follows `ai_jobs.brain_learn` instructions for yesterday | `ai-brain-learn` 3:10 AM |
| IOC brain: daily brief, 9:20 AM Mon-Sat (skips off days) | follows `ai_jobs.brain_insights` instructions | `ai-brain-insights` 11:20 AM |
| IOC brain: weekly deep pass, Sunday 11:15 AM | rewrites `brain_pages` (company profile + one page per team member), fixes contradicting facts, DMs Sahil a summary | none |

- Sessions have no connector tools (not available for this organization's scheduled tasks), so they run SQL through
  the Supabase Management API (`api.supabase.com`, credential injected by the environment proxy).
- `brain_run_done(job, day, source)` marks completion; `brain_week_inputs()` feeds the weekly pass.
- The company profile's first part is in the company snapshot (every reply); each person page's first part is in
  their person card.
- Limits: about 2 scheduled runs a day, nothing real-time or event-driven. IOCtopus replies, lead notes, Note 2,
  funnel alerts and EOD drafts stay on the API.

## Cost: target $2/day (7 Nov 2026)

Findings (last 14 days, repriced): real spend ~$6.94/day, of which Sonnet 5.5 was $6.77. Everything on Haiku 5.5
cost $0.16/day in total. Haiku 5.5 is $0.10 / $0.50 per 1M tokens vs Sonnet 5.5 $2 / $10 (about 20x).
The ai-worker's price table logged Haiku at 10x its real price and Sonnet cache reads at half.

Changes (no ai-worker redeploy):
- `ai_model_prices` + trigger `ai_usage_price` reprice every `ai_usage` row (worker estimate kept in
  `cost_usd_worker`); current cycle repriced, so the spend cap and reports use real numbers.
- Moved to Haiku 5.5: `ad_report`, `pipeline_sync`, `weekly_review`, `perf_update` (agendas, eod_drafts,
  daily_review, funnel_alert, pipeline_sync_lite were already Haiku).
- `ioctopus` screen flipped to LITE (Haiku) by default; FULL (Sonnet) only for risky confirmations, money/record
  changes, bot training, deep analysis/strategy, long multi-part asks. Meeting drafts, scans, SOD now LITE.
- `lead_notes` screen: Sonnet for new bookings without Note 1, reschedules, unclear cases, FCB buyers with no
  earlier note, and clinician / strong-signal disqualified leads; ordinary disqualified stay on Haiku. (A side-by-side
  check showed Sonnet catches subtler issues, e.g. income maths that doesn't add up, so sales-relevant notes keep it.)
- Kept on Sonnet: `note2`, `brain_learn`, `brain_insights` (~$0.25/day).
- `ai_cost_check()` (cron `ai-cost-check`, 9:30 AM IST): DMs Sahil a per-job breakdown when yesterday was over
  `app_config.ai_daily_target_usd` (2.0). Yesterday's cost is also in the brain brief inputs.

Expected: roughly $1.5-2/day at current volume; to be confirmed on real working days after Diwali.

## Nudge clean-up (7 Nov 2026)

What was actually happening (last 7 days):
- Counts were inflated: `outbox_log_people` logged a DM twice when it also @-mentioned the recipient (every
  10:30 PM EOD reminder showed up twice), and logged everyone named in a nudge as "nudged" (e.g. "@Akhtar,
  @Suchita asked you…" counted against Suchita).
- Real repetition came from the 10:07 / 4:07 scan: the 20 h rule meant every open item was re-nudged every day,
  several separate messages could hit one person in the same scan, and there was no per-person limit.
- Saturday tracker reminders to Suhel (7 DMs) are jobs he created himself; left as they are.

Changes:
- `outbox_log_people`: one row per person per message; only the DM recipient or the @-mentions at the start
  count as asked, everyone else is logged as `mentioned`.
- `loop_nudge`: max 3 items per person per IST day (`HOLD` beyond that, comes back next scan); skips people who are
  away and company off days; escalation to Aakash waits 44 h after the 2nd nudge.
- `ai-employee-scan` skill v11: one message per person per scan (bullets), quality over volume.
- `brain_insight_inputs`: "over-nudged" counts only unprompted nudges.

## Phase 1 (live 7 Nov 2026)

What was wrong: every reply loaded ~49k characters of rules but almost no company knowledge. The related-memory
search only allowed public channels; 43 of 61 channels are private and meetings/EODs never passed, so 80% of
replies got nothing. The 2,853 facts in `knowledge` were never loaded. New top-level mentions got no context.
A chat reply averaged 8.4 model calls because the bot had to look everything up itself.

What changed:

- `slack_channel_members` + edge function `slack-members` (cron `slack-members-6h`): who is in each channel.
- `brain_can_see(asker, source_id, channel)`: privacy rule. Aakash + Sahil see everything. Others: channels
  they are in, public channels, company facts, EODs, team meetings (3+ speakers) and meetings they were in.
  Never other people's DMs. Salaries etc. stay blocked by the core skill.
- `knowledge` facts are now in `memory_chunks` (`source_type = 'fact'`, trigger `knowledge_to_memory`), so
  `ioc_search` finds them. Embeddings use Supabase's free built-in gte-small model.
- `brain_related(query, asker, channel, skip_thread, k)`: facts first, then Slack/meetings/EODs, filtered.
- `clients_in_text(text)` + `client_card(name)`: when a client is named, the bot gets the Asana card, latest
  weekly review, tracker week, open/overdue tasks, last client WhatsApp group messages, last Tuesday report.
- New Asana clients now flow into `clients` automatically (trigger `asana_client_to_index`); Vishnu Mate and
  Prateek Kumar were missing.
- `ioctopus_brief`: uses all of the above; new top-level mentions get the last 12 channel messages; short
  replies ("Done") search with the thread starter; a "how to answer well" block (answer from context first,
  add one line on a risk/contradiction the asker would want, never invent, cite).
- `team-lists` skill loads only for task-related messages (31% of messages instead of 100%).

Rollback: `ioctopus_brief_backup_20261107` is the previous brief. To restore, recreate `ioctopus_brief` from its
definition (rename back, including its one recursive call).
