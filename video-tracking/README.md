# Offer Breakdown video tracking (13 Nov 2026)

Shows in the pre-call notes how much of the Offer Breakdown video a lead watched.

## How it works

1. `page-script.html` goes in the footer of the GHL funnel step `/call-scheduled-dfy` (the page shown right after booking).
2. The video on that page is GHL's own player (~34 min, **autoplays muted**). The script counts only the seconds that
   play **with sound on, with the tab in front**. Skipping ahead doesn't count. Muted autoplay doesn't count.
3. Each time the lead passes another 5%, the script posts to the Supabase function `video-progress`
   (`video-progress/index.ts`, deployed with JWT off; it checks the video id and only raises the stored %).
4. The function finds the GHL contact (contact id → email → phone, using the email/phone GHL saved in the browser
   when they applied, `localStorage._ud`) and writes:
   - Supabase `video_watch` (one row per contact + video: `max_pct`, `watched_sec`, `duration_sec`, `first_at`, `last_at`)
     and `video_watch_events` (every ping, with the result, for debugging)
   - GHL contact field **Offer Video Watched %** (`kg0uyvqWv6f8ZVv2sWDk`)
   - GHL tags `offer-video-25`, `-50`, `-75`, `-100` (100 = 95%+), each added once
5. The pre-call note job (`ai_jobs.lead_notes`, rule 7, copy in `../routines/note1-lead-notes-prompt.txt`) reads `video_watch`.

## Limits

- It tracks only the browser the lead applied from. On another phone or browser the watch shows as "not tracked", never as "didn't watch".
- Note 1 is written when the call is booked, usually before the lead has watched. The % shows up in notes written later (for example on confirmation).
- The page also has a hidden Wistia copy of the video (`0quz6oc5jo`). The function accepts that id too, but the script tracks the visible GHL video.

## Check it

```sql
select * from video_watch order by last_at desc limit 20;
select at, contact_id, pct, matched_by, result from video_watch_events order by id desc limit 20;
```
A `contact not found` or `no ident` result means the browser had no saved email or phone.
