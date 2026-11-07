# IOC routines

Prompt text for the two IOC routines. Each file is pasted into its routine as-is.

| Routine | Prompt file | Schedule | Connectors |
|---|---|---|---|
| `IOC Lead Notes → GHL + Slack (booked + disqualified)` | `note1-lead-notes-prompt.txt` | `CRON_TZ=Asia/Kolkata 0 9,12,15,18,21 * * *` | GHL, Slack, Meta (+ web search/fetch) |
| `IOC Post-Call Note 2 → GHL` | `note2-post-call-prompt.txt` | `0 8,10,12,14,16 * * *` (UTC = 1:30–9:30 PM IST) | GHL, Supabase (read only), Fathom |

Both run with automatic approval. Routine 1 also has an API trigger so a GHL calendar workflow can fire it (EVENT MODE).

## Live source of truth (since 11 Oct 2026)
The scheduled tasks above are paused. Note 1 is written by Supabase `ai_jobs.lead_notes` (instructions column), so a change to `note1-lead-notes-prompt.txt` does NOTHING until it is applied there. The 5 Nov Note 1 format (Closer Playbook triage script) is applied by `supabase/lead_notes_note1_format_20261107.sql`. `ai_job_parts` for `lead_notes` is an older copy; never run `ai_job_assemble('lead_notes')`.
