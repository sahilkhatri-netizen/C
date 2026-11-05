# IOC routines

Prompt text for the two IOC routines. Each file is pasted into its routine as-is.

| Routine | Prompt file | Schedule | Connectors |
|---|---|---|---|
| `IOC Lead Notes → GHL + Slack (booked + disqualified)` | `note1-lead-notes-prompt.txt` | `CRON_TZ=Asia/Kolkata 0 9,12,15,18,21 * * *` | GHL, Slack, Meta (+ web search/fetch) |
| `IOC Post-Call Note 2 → GHL` | `note2-post-call-prompt.txt` | `0 8,10,12,14,16 * * *` (UTC = 1:30–9:30 PM IST) | GHL, Supabase (read only), Fathom |

Both run with automatic approval. Routine 1 also has an API trigger so a GHL calendar workflow can fire it (EVENT MODE).

## Where these run now (checked 5 Nov 2026)

`ai_jobs` in Supabase lists `lead_notes` ("Replaces trig_014Tnqs86MGkRGayN83a9Bi8") and `note2` ("Replaces IOC Post-Call Note 2 → GHL, trig_01ENbdsyoJq9J9ZAyaTJw2jy"). Those jobs run inside Supabase with the shared preamble in `app_config.ai_tool_guide`. Check `select slug, name, enabled, trigger_kind from ai_jobs;` before editing the prompts here, and change `ai_jobs.instructions` if that is where the live copy is.

## Preamble for every routine

Paste the one paragraph in `preamble.txt` as the first line of any Claude scheduled task that touches Supabase. It makes the task load the channel map and the knowledge-lookup skill before doing anything else, so the right table or connector is chosen without being spelled out in the prompt.
