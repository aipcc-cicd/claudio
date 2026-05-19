# Memory Protocol — MemPalace

MemPalace is the sole memory store. Never write to Claude Code's native auto-memory (`.md` files).

## On Wake-Up

**MANDATORY: On the first user message of every new conversation, before responding to anything else, run steps 1–3 below. Do not wait to be asked. Do not send any text response until all steps are complete.**

⚠ MemPalace tools are deferred — their schemas are NOT loaded at startup.
Before calling any `mempalace_*` tool you MUST first run:

```
ToolSearch(query: "select:mcp__plugin_mempalace_mempalace__mempalace_status,mcp__plugin_mempalace_mempalace__mempalace_diary_read")
```

Then immediately call both tools **in parallel**:

1. `mempalace_status` — palace overview
2. `mempalace_diary_read` (agent_name: "session-hook", last_n: 5) — recent session checkpoints (auto-saved by plugin)
3. `mempalace_search` (query: "<topic>") — before answering about past work

## After Completing Work (MANDATORY)

After completing any of the following, call `mempalace_add_drawer` immediately — do not wait until end of session:

- Jira operations: cards created, updated, transitioned, or linked (save keys + summaries)
- Decisions made (architecture, approach, naming)
- Config or settings changes (CLAUDE.md, settings.json, hooks)
- Scripts or tools created or modified

Save the **outcome** (what was done, keys created, values set) — not the process. The stop hook saves the transcript; this saves the facts.

## Rules

- Search before answering about past work — never guess.
- **Before generating any artifact** (document, plan, summary, config, script) search MemPalace first. If a prior version exists, retrieve and present it — do not regenerate from inference.
- If a fact changes: `kg_invalidate` then `kg_add`.
- Checkpoints are raw message extracts written by the plugin automatically under `agent_name: "session-hook"`. They capture what was said but not curated findings.
