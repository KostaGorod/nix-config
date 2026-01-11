# Memvid Integration Plan

## Goal
Provide a repo-agnostic, local-only semantic search + RAG CLI integration using Memvid. Artifacts are repo-local but **never committed**. Multiple subagents share the same index safely.

## User Constraints
- Repo-local artifact, not committed.
- Shared index for all subagents (per repo/per user is OK).
- CLI-first UX.

## Assumptions (from Memvid docs)
- `.mv2` supports **multiple concurrent readers** and **single writer**; writers take exclusive locks; readers should open in read-only mode.
- CLI supports lock handling (`--lock-timeout`, `--force`, `memvid who`, `memvid nudge`).
- Memvid can work **without vectors** (lexical/BM25 + other local indices), and can do **local reasoning** via Ollama for `ask`.

## Standard Repo Layout (portable)
- `.memvid/` (git-ignored).
- Shared per-user index: `.memvid/index.mv2`.
- Incremental state: `.memvid/state.json`.
- Optional later (realtime overlay): `.memvid/rt.mv2`.

## CLI Contract (wrapper tool: `repo-mem`)
One stable wrapper CLI usable from any repo:
- `repo-mem init`
  - Ensures `.memvid/` exists.
  - Ensures `.memvid/` is in `.gitignore`.
  - Creates `.memvid/index.mv2` with chosen modes (default lex-only).
- `repo-mem index [--scope <path>...] [--tracked-only|--include-untracked] [--force]`
  - Incremental update; single-writer behavior.
- `repo-mem ensure`
  - Fast no-op if already indexed at current `git HEAD`.
  - If locked, exits successfully with “index busy; using existing index”.
- `repo-mem search <query> [--mode lex|auto|sem] [--top-k N] [--json|--jsonl]`
  - Read-only search.
- `repo-mem ask <question> [--model ollama:<name>] [--json]`
  - Retrieval + synthesis using local model by default.
- `repo-mem visualize [--format mermaid|dot|json] [--level repo|module|function]`
  - Generates repo map, module inventory, dependency/import graph.
  - Stores these as searchable artifacts in the same `.mv2`.
- `repo-mem show <artifact-id> [--format mermaid|dot|json]`
  - Retrieves and displays stored visualization artifacts.
- `repo-mem status`
  - Last indexed commit, counts, size, timestamp.
- `repo-mem clean`
  - Deletes `.memvid/index.mv2` + `.memvid/state.json`.

## Concurrency Strategy (for subagents)
- Unlimited concurrent `search/ask` (read-only opens).
- `index/ensure/visualize` are single-writer; on lock conflict:
  - `ensure/visualize`: short timeout and graceful fallback.
  - `index`: longer timeout; otherwise instruct user to use `memvid who/nudge`.
- Never auto-use `--force`; only on explicit user request.

## Local-only Defaults
- Default is lex-only (no vectors, no embedding API keys).
- `ask` uses local Ollama (`ollama:qwen2.5:1.5b` default).
- Optional later toggle to add vectors/embeddings with local models.

## File Discovery Rules (deterministic)
- Canonical file list: `git ls-files`.
- Optional include untracked-but-not-ignored: `git ls-files -o --exclude-standard`.
- Hard excludes layered on top: `node_modules/`, `dist/`, `target/`, `.direnv/`, `.venv/`, `.git/`, binaries.

## Implementation Roadmap
1. **Prerequisite**: Ensure `memvid` is available (e.g., via `nix-shell` or `npx`).
2. **Wrapper**: Implement `repo-mem` bash/python script.
3. **Integration**: Add `.memvid/` to repo's `.gitignore`.
4. **Validation**: Test concurrent search while indexing.
