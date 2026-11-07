# IOC company brain

Goal (Sahil, 7 Nov 2026): IOCtopus and every AI job answer like someone who knows the whole company,
including things the asker did not think to ask. AI spend target: under $180 a month (target, not a hard stop;
the existing `ai_monthly_cap_usd` stays at 190).

Everything lives in the Supabase project `ugiurxkbbuhtvbehpkvb`. No new software.

## Plan

| Phase | What | Status |
|---|---|---|
| 1 | Give the bot what the company already knows at answer time | **Live 7 Nov** |
| 2 | Complete memory: client WhatsApp groups, team WhatsApp, Asana, Note 1/2, GHL notes, Drive SOPs; restart fact extraction (stalled since ~12 Oct) | Next |
| 3 | Company model: weekly company profile + nightly page per client and per person | |
| 4 | Reasoning: hard questions get Opus with thinking, research steps, self-check with sources | |
| 5 | Insight engine: daily/weekly scans across sources for risks, contradictions, missed promises | |
| 6 | One brain everywhere (MCP server) + learning from draft-vs-sent edits + weekly scored test set | |

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
