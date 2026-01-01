-- Migration: Create calendar_event_bindings table with RLS
-- Feature: F012
-- Description: Binds Google Calendar events to source entities (tasks, milestones, gate_runs)

-- ============================================================================
-- CALENDAR_EVENT_BINDINGS TABLE
-- ============================================================================

CREATE TABLE calendar_event_bindings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Google Calendar event reference
  google_event_id TEXT NOT NULL,
  calendar_id TEXT NOT NULL,  -- Which calendar this event lives in

  -- Source entity reference (polymorphic)
  source_type TEXT NOT NULL,  -- 'task', 'milestone', 'gate_run', 'project_review'
  source_id UUID NOT NULL,    -- ID of the source entity

  -- Event metadata (for quick reference without API call)
  event_type calendar_event_type NOT NULL,
  event_title TEXT,
  event_start TIMESTAMPTZ,
  event_end TIMESTAMPTZ,

  -- Sync tracking
  last_synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sync_version INTEGER NOT NULL DEFAULT 1,  -- Increment on each update

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Unique constraint: one binding per source entity
  CONSTRAINT unique_source_binding UNIQUE (workspace_id, source_type, source_id)
);

-- Indexes for calendar_event_bindings
CREATE INDEX idx_calendar_bindings_workspace_id ON calendar_event_bindings(workspace_id);
CREATE INDEX idx_calendar_bindings_google_event ON calendar_event_bindings(google_event_id);
CREATE INDEX idx_calendar_bindings_source ON calendar_event_bindings(source_type, source_id);
CREATE INDEX idx_calendar_bindings_event_type ON calendar_event_bindings(event_type);
CREATE INDEX idx_calendar_bindings_calendar_id ON calendar_event_bindings(calendar_id);
CREATE INDEX idx_calendar_bindings_last_synced ON calendar_event_bindings(last_synced_at);

-- Comments
COMMENT ON TABLE calendar_event_bindings IS 'Binds Google Calendar events to source entities for idempotent sync';
COMMENT ON COLUMN calendar_event_bindings.google_event_id IS 'Google Calendar event ID (unique identifier from Google)';
COMMENT ON COLUMN calendar_event_bindings.calendar_id IS 'Google Calendar ID where event exists';
COMMENT ON COLUMN calendar_event_bindings.source_type IS 'Type of source entity (task, milestone, gate_run, project_review)';
COMMENT ON COLUMN calendar_event_bindings.source_id IS 'UUID of the source entity';
COMMENT ON COLUMN calendar_event_bindings.event_type IS 'Calendar event type (determines rendering logic)';
COMMENT ON COLUMN calendar_event_bindings.last_synced_at IS 'Timestamp of last successful sync to Google Calendar';
COMMENT ON COLUMN calendar_event_bindings.sync_version IS 'Version counter for optimistic locking during sync';

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Apply updated_at trigger to calendar_event_bindings
CREATE TRIGGER tr_calendar_bindings_updated_at
  BEFORE UPDATE ON calendar_event_bindings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Auto-increment sync_version on update
CREATE OR REPLACE FUNCTION increment_sync_version()
RETURNS TRIGGER AS $$
BEGIN
  NEW.sync_version = OLD.sync_version + 1;
  NEW.last_synced_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_calendar_bindings_increment_version
  BEFORE UPDATE ON calendar_event_bindings
  FOR EACH ROW
  EXECUTE FUNCTION increment_sync_version();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE calendar_event_bindings ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view bindings in their workspaces
CREATE POLICY calendar_bindings_select_policy ON calendar_event_bindings
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Editors and admins can create bindings (via worker or API)
CREATE POLICY calendar_bindings_insert_policy ON calendar_event_bindings
  FOR INSERT
  WITH CHECK (is_workspace_editor(workspace_id));

-- UPDATE: Editors and admins can update bindings
CREATE POLICY calendar_bindings_update_policy ON calendar_event_bindings
  FOR UPDATE
  USING (is_workspace_editor(workspace_id))
  WITH CHECK (is_workspace_editor(workspace_id));

-- DELETE: Admins can delete bindings
CREATE POLICY calendar_bindings_delete_policy ON calendar_event_bindings
  FOR DELETE
  USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- POLICY COMMENTS
-- ============================================================================

COMMENT ON POLICY calendar_bindings_select_policy ON calendar_event_bindings IS 'Members can view calendar bindings in their workspace';
COMMENT ON POLICY calendar_bindings_insert_policy ON calendar_event_bindings IS 'Editors and admins can create calendar bindings';
COMMENT ON POLICY calendar_bindings_update_policy ON calendar_event_bindings IS 'Editors and admins can update calendar bindings';
COMMENT ON POLICY calendar_bindings_delete_policy ON calendar_event_bindings IS 'Only admins can delete calendar bindings';
