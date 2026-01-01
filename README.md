# Idea to Cashflow Pipeline

An AI-powered pipeline for transforming ideas into validated business opportunities.

## Architecture

```
/apps
  /web        → Next.js App Router (UI)
  /worker     → Node.js Services (Orchestrator, Ingestion, Calendar)
/packages
  /shared     → Zod Schemas, Types, Scoring Logic
/supabase
  /migrations → SQL Migrations
  /seed       → Default Config + Prompts
```

## Getting Started

1. Clone the repository
2. Run `./init.sh` to set up the environment
3. Follow instructions in `CLAUDE.md` for development

## Features

See `feature_list.json` for the current feature roadmap and progress.

## Development

This project uses the Harness system for AI-assisted development. See `CLAUDE.md` for project conventions and context.

---

Built with Claude AI
