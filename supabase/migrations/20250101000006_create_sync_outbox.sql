-- Migration: Create sync_outbox table for reliable calendar sync
-- Feature: F013
-- Description: Outbox pattern for reliable side effects with retry logic

-- ============================================================================
-- SYNC_OUTBOX TABLE
-- ============================================================================

CREATE TABLE sync_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Operation details
  operation outbox_operation NOT NULL,  -- UPSERT_EVENT, CANCEL_EVENT, REBUILD_ALL

  -- Payload for the operation (polymorphic JSON)
  payload JSONB NOT NULL,

  -- Processing status
  status outbox_status NOT NULL DEFAULT 'PENDING',

  -- Retry logic
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_error TEXT,

  -- Advisory lock support (use workspace_id + id for unique lock)
  -- Advisory lock key will be: hashtext(workspace_id::text || id::text)

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,  -- When successfully completed

  -- Constraints
  CONSTRAINT valid_attempts CHECK (attempts >= 0 AND attempts <= max_attempts)
);

-- Indexes for sync_outbox
CREATE INDEX idx_sync_outbox_workspace_id ON sync_outbox(workspace_id);
CREATE INDEX idx_sync_outbox_status ON sync_outbox(status);
CREATE INDEX idx_sync_outbox_next_attempt ON sync_outbox(next_attempt_at)
  WHERE status IN ('PENDING', 'FAILED');  -- Partial index for efficiency
CREATE INDEX idx_sync_outbox_operation ON sync_outbox(operation);
CREATE INDEX idx_sync_outbox_created_at ON sync_outbox(created_at);

-- Composite index for worker polling
CREATE INDEX idx_sync_outbox_worker_poll ON sync_outbox(status, next_attempt_at)
  WHERE status IN ('PENDING', 'FAILED');

-- Comments
COMMENT ON TABLE sync_outbox IS 'Outbox pattern for reliable calendar sync with retry logic';
COMMENT ON COLUMN sync_outbox.operation IS 'Type of calendar operation to perform';
COMMENT ON COLUMN sync_outbox.payload IS 'JSON payload for the operation (event data, source binding, etc.)';
COMMENT ON COLUMN sync_outbox.status IS 'Processing status (PENDING/PROCESSING/COMPLETED/FAILED/DEAD_LETTER)';
COMMENT ON COLUMN sync_outbox.attempts IS 'Number of processing attempts made';
COMMENT ON COLUMN sync_outbox.max_attempts IS 'Maximum retry attempts before dead letter';
COMMENT ON COLUMN sync_outbox.next_attempt_at IS 'Timestamp when next retry attempt should be made';
COMMENT ON COLUMN sync_outbox.last_error IS 'Last error message from failed attempt';

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Apply updated_at trigger to sync_outbox
CREATE TRIGGER tr_sync_outbox_updated_at
  BEFORE UPDATE ON sync_outbox
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- HELPER FUNCTIONS FOR ADVISORY LOCKS
-- ============================================================================

-- Function to acquire advisory lock for outbox item
-- Returns true if lock acquired, false otherwise
CREATE OR REPLACE FUNCTION try_lock_outbox_item(outbox_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  lock_key BIGINT;
BEGIN
  -- Generate lock key from outbox_id (convert UUID to bigint)
  -- Using hashtext to get a consistent bigint from UUID
  lock_key := hashtext(outbox_id::text);

  -- Try to acquire advisory lock (non-blocking)
  RETURN pg_try_advisory_lock(lock_key);
END;
$$ LANGUAGE plpgsql;

-- Function to release advisory lock for outbox item
CREATE OR REPLACE FUNCTION unlock_outbox_item(outbox_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  lock_key BIGINT;
BEGIN
  lock_key := hashtext(outbox_id::text);
  RETURN pg_advisory_unlock(lock_key);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION try_lock_outbox_item IS 'Try to acquire advisory lock for outbox item (non-blocking)';
COMMENT ON FUNCTION unlock_outbox_item IS 'Release advisory lock for outbox item';

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE sync_outbox ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view outbox items in their workspaces
CREATE POLICY sync_outbox_select_policy ON sync_outbox
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Editors and admins can create outbox items (via API or triggers)
CREATE POLICY sync_outbox_insert_policy ON sync_outbox
  FOR INSERT
  WITH CHECK (is_workspace_editor(workspace_id));

-- UPDATE: System (service role) can update outbox items
-- Workers need service role to update status
CREATE POLICY sync_outbox_update_policy ON sync_outbox
  FOR UPDATE
  USING (is_workspace_editor(workspace_id))
  WITH CHECK (is_workspace_editor(workspace_id));

-- DELETE: Admins can delete outbox items (for cleanup)
CREATE POLICY sync_outbox_delete_policy ON sync_outbox
  FOR DELETE
  USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- POLICY COMMENTS
-- ============================================================================

COMMENT ON POLICY sync_outbox_select_policy ON sync_outbox IS 'Members can view outbox items in their workspace';
COMMENT ON POLICY sync_outbox_insert_policy ON sync_outbox IS 'Editors and admins can create outbox items';
COMMENT ON POLICY sync_outbox_update_policy ON sync_outbox IS 'Editors and admins can update outbox items (workers use service role)';
COMMENT ON POLICY sync_outbox_delete_policy ON sync_outbox IS 'Only admins can delete outbox items';

-- ============================================================================
-- CLEANUP FUNCTION
-- ============================================================================

-- Function to clean up old completed/dead letter items (run periodically)
CREATE OR REPLACE FUNCTION cleanup_old_outbox_items(older_than_days INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM sync_outbox
  WHERE status IN ('COMPLETED', 'DEAD_LETTER')
    AND updated_at < NOW() - INTERVAL '1 day' * older_than_days;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_outbox_items IS 'Clean up old completed/dead letter outbox items older than specified days';
