-- Applied 6 Nov 2026 with Aakash's approval. Makes where_is() the first step for every surface.
-- Rollback: core -> select public.skill_undo('core', null, null, 'U07Q5BDGA87');
--           ai_tool_guide -> update app_config set value = (select value from app_config where key='ai_tool_guide_backup_20261106') where key='ai_tool_guide';

-- 1. core skill (preloaded on every IOCtopus message), saved as core v6 through skill_write (all must_keep tests pass).
--    Section inserted directly above "## Hard limits (always)":
/*
## Channel map: where_is() first (Aakash, 6 Nov 2026)
Before answering from any table or connector, and before doing any task, run: select * from public.where_is('<topic in a few words>'); and use the source it names. A data_point row gives the table, view or function and the query pattern. A connection row gives how to reach that system, its identifiers and the ONLY allowed write path. If nothing scores above 1, use the knowledge-lookup skill. If you had to find the answer without a matching row, add one so the next answer is instant: insert into data_points(key, question, connection_id, source, how, live_alternative, caveats) values (…). If a connection row is wrong (owner, number, account), write a bot_note instead of editing it. Before quoting a Supabase copy as current, check select * from public.freshness;
*/

-- 2. app_config.ai_tool_guide (read by every ai_jobs run). Backup saved as ai_tool_guide_backup_20261106. Appended:
/*
CHANNEL MAP (Aakash, 6 Nov 2026): before your first read or write, run select * from public.where_is('<topic of this step>'); with the sql tool. It returns the connection (identifiers, how to reach it, the only allowed write path) and the data point (table, view or function and the query pattern) for that topic. Use the source it names. If it returns nothing useful, use the tables named in your instructions and say so in the run log. Before quoting a Supabase copy as current, check select * from public.freshness; and say its sync time.
*/
