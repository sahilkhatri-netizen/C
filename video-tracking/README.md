# Funnel video tracking (13 Nov 2026)

Pre-call notes and the closer's booking thread show how much of the two funnel videos a lead watched:

| id | Video | Page | When | Length |
|---|---|---|---|---|
| `power-funnel` | Power Funnel video | `dfy.independentonlinecoach.com/` | before applying | ~29 min |
| `offer-breakdown` | Offer Breakdown video | `/call-scheduled-dfy` | after booking | ~34 min |

Both are GHL's own video player and both **autoplay muted**. Only seconds played **with sound on, with the tab in front** count. Skipping ahead doesn't count.

## Pieces

1. **`page-script.html`**: paste once into the DFY funnel's funnel-wide **Footer** tracking code, so it runs on every step.
   On the home page the lead usually isn't known yet. Progress is kept in the browser and sent as soon as they are
   (after the application, GHL stores their email/phone in `localStorage._ud`).
2. **Supabase function `video-progress`** (`video-progress/index.ts`, JWT off, checks video ids, only ever raises the %).
   It finds the GHL contact (id → email → phone) and writes:
   - `video_watch`: one row per contact + video (`max_pct`, `watched_sec`, `duration_sec`, `first_at`, `last_at`)
   - `video_watch_events`: every ping with its result (for debugging)
   - GHL fields **Offer Video Watched %** (`kg0uyvqWv6f8ZVv2sWDk`) and **Power Funnel Video Watched %** (`gFhpd2M26IkaKdUmgEYk`)
   - GHL tags `offer-video-25/50/75/100` and `power-funnel-video-25/50/75/100` (100 = 95%+)
3. **45-minute Slack update**: `public.video_hour_check()`, run by cron `video-hour-check-5min`. 45 minutes after a booking it
   replies in that booking's Slack thread, tagging the closer, with the **Offer Breakdown** % and a next step
   (":tv: Offer video check"). The Power Funnel % is in the pre-call note itself, because it's watched before applying. One post per
   appointment (`video_hour_posts`). It skips cancelled bookings and calls that have already started. It starts by itself
   with the first real (non internal-test) tracking ping, so nothing posts before the page script is live.
4. **Pre-call notes**: rule 7 in `ai_jobs.lead_notes` (copy in `../routines/note1-lead-notes-prompt.txt`) reads `video_watch`.

## Limits

- Only the phone/browser they applied from is tracked. Watching elsewhere shows as "not tracked", never "didn't watch".
- Note 1 is written at booking, before most people watch the Offer video. The 1-hour update and later notes carry the numbers.

## Check it

```sql
select * from video_watch order by last_at desc limit 20;
select at, contact_id, media_id, pct, matched_by, result from video_watch_events order by id desc limit 20;
select * from video_hour_posts order by posted_at desc limit 20;
select public.video_hour_check();  -- run the 1-hour check now
```
