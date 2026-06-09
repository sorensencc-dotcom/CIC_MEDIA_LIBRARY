# CIC — Cast Iron Charlie Documentary DAM Pipeline

> Digital Asset Management system for the Cast Iron Charlie film project about Charles Emil Sorensen. Runs automated ingest, archive research, entity graph building, and report generation on a 16-script PS1 pipeline orchestrated by Wayland-Core workflows.

## Overview

CIC automates documentary research + media curation via multi-stage pipelines:

- **Ingest**: Converts media (HEIC→JPEG), extracts EXIF, SHA256 hashing, deduplication, topic routing
- **Archive**: Queries 10 archive connectors (LOC, Smithsonian, NARA, FamilySearch, etc.), consolidates results
- **Entity Graph**: Builds person/place/org relationships from OCR + metadata
- **Reports**: Generates HTML/MD research summaries, curates marketing assets, surfaces gaps for interviews

Live data: `metadata/master_media_inventory.csv` (92+ docs), `entity_graph.json` (25 nodes), `archive_results_*.json`, `reconciliation_log.md`.

## Conventions

- PS1 scripts in `scripts/` unchanged — Wayland calls them via shell tool, parses JSON/CSV outputs
- Archive connectors (LOC, Smithsonian, etc.) return normalized JSON; queue in `metadata/archive_crawl_queue.json`
- Topic routing: documentary vs. genealogy domain; master index in `master_media_inventory.csv`
- Skill format: Markdown + YAML front matter (compatible with Claude Code ~/.claude/skills/)
- Workflows: RON files in `.wayland/workflows/` define pipeline stages + Slack notifications
- Metrics: Prometheus `wayland_tool_exec_*` + pipeline-specific counters exported to `localhost:9091/metrics`
- Error handling: any stage failure routes to Slack `#cic-alerts`

## Commands

- Ingest: `wayland run --workflow cic-daily-ingest`
- Archive: `wayland run --workflow cic-archive-query`
- Weekly ops: `wayland run --workflow cic-weekly-ops`
- Analysis: `wayland run --skill improvement-analysis`
- Status: `wayland run --skill cic-pipeline-status`
