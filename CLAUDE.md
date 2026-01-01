# CLAUDE.md - Projekt-Kontext für jede Session

## Projekt: Idea-to-Cashflow Pipeline

### Architektur-Übersicht
```
/apps
  /web        → Next.js App Router (UI)
  /worker     → Node.js Services (Orchestrator, Ingestion, Calendar)
/packages
  /shared     → Zod Schemas, Types, Scoring-Logik
/supabase
  /migrations → SQL Migrations
  /seed       → Default Config + Prompts
```

### Kritische Konventionen

#### Datenbank
- ALLE Tabellen haben `workspace_id` (Multi-Tenancy)
- RLS ist PFLICHT auf allen public Tables
- Naming: snake_case für Tabellen und Spalten
- Enums: UPPERCASE mit Unterstrich (LIFECYCLE_STATUS, GATE_DECISION)
- Timestamps: `created_at`, `updated_at` mit DEFAULT NOW()

#### TypeScript
- Strikte Typisierung (no `any`)
- Zod-Schemas in `/packages/shared/src/schemas/`
- Export alle Types aus `/packages/shared/src/index.ts`

#### API Routes
- Pfad: `/apps/web/app/api/v1/[resource]/route.ts`
- Fehler: RFC7807 Problem+JSON Format
- Auth: Supabase Session prüfen, workspace_id aus JWT

#### Worker Services
- Pfad: `/apps/worker/src/services/[name]_service.ts`
- Outbox-Pattern für Calendar-Sync
- Idempotency-Keys für Gate-Runs

### Wichtige Dateien (immer prüfen)
- `/packages/shared/src/schemas/` - Alle Zod Schemas
- `/supabase/migrations/` - DB Schema ist Source of Truth
- `/apps/worker/src/services/gate_orchestrator_service.ts` - Kern-Logik

### Entscheidungen (NICHT ändern ohne Grund)
1. Supabase ist Source of Truth (nicht Drive, nicht Calendar)
2. Calendar ist write-only Mirror (manuelle Edits werden überschrieben)
3. Prompts sind versioniert + immutable
4. Evidence-Level bestimmt Confidence (deterministische Formel)

### Häufige Fehler vermeiden
- NIEMALS RLS vergessen bei neuen Tabellen
- NIEMALS workspace_id vergessen
- NIEMALS Zod-Schema und DB-Schema out-of-sync
- NIEMALS sensitive Daten (Tokens) unverschlüsselt speichern
