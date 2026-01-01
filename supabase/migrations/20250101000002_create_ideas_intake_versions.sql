-- Migration: Create ideas and idea_intake_versions tables with RLS
-- Feature: F003
-- Description: Core idea tracking with versioned intake data

-- ============================================================================
-- IDEAS TABLE
-- ============================================================================

CREATE TABLE ideas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Identification
  title TEXT NOT NULL,
  slug TEXT NOT NULL,
  external_id TEXT,  -- Optional external reference (Drive file ID, etc.)

  -- Lifecycle & Gate Tracking
  lifecycle_status lifecycle_status NOT NULL DEFAULT 'CREATED',
  current_gate gate NOT NULL DEFAULT 'G0_INTAKE',
  latest_decision gate_decision,
  latest_kill_reason kill_reason,
  latest_kill_reason_custom TEXT,  -- For CUSTOM kill reason

  -- Scoring (0.0 - 1.0 range, calculated by decision engine)
  score_total NUMERIC(4, 3) CHECK (score_total IS NULL OR (score_total >= 0 AND score_total <= 1)),
  score_market NUMERIC(4, 3) CHECK (score_market IS NULL OR (score_market >= 0 AND score_market <= 1)),
  score_risk NUMERIC(4, 3) CHECK (score_risk IS NULL OR (score_risk >= 0 AND score_risk <= 1)),
  score_economics NUMERIC(4, 3) CHECK (score_economics IS NULL OR (score_economics >= 0 AND score_economics <= 1)),
  score_validation NUMERIC(4, 3) CHECK (score_validation IS NULL OR (score_validation >= 0 AND score_validation <= 1)),

  -- Evidence Level (0-5 scale, determines confidence caps)
  evidence_level evidence_level NOT NULL DEFAULT 'LEVEL_0',
  confidence INTEGER CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 100)),

  -- Priority for dashboard views
  priority task_priority DEFAULT 'P2',

  -- Generated outputs (populated at G5)
  human_handoff JSONB,
  build_pack JSONB,

  -- Approval tracking
  approval_granted_at TIMESTAMPTZ,
  approval_granted_by UUID REFERENCES auth.users(id),

  -- Flags
  needs_rerun BOOLEAN NOT NULL DEFAULT FALSE,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Unique constraint: slug per workspace
  CONSTRAINT unique_workspace_slug UNIQUE (workspace_id, slug)
);

-- Indexes for ideas
CREATE INDEX idx_ideas_workspace_id ON ideas(workspace_id);
CREATE INDEX idx_ideas_lifecycle_status ON ideas(lifecycle_status);
CREATE INDEX idx_ideas_current_gate ON ideas(current_gate);
CREATE INDEX idx_ideas_latest_decision ON ideas(latest_decision);
CREATE INDEX idx_ideas_score_total ON ideas(score_total DESC NULLS LAST);
CREATE INDEX idx_ideas_priority ON ideas(priority);
CREATE INDEX idx_ideas_created_at ON ideas(created_at DESC);
CREATE INDEX idx_ideas_updated_at ON ideas(updated_at DESC);
CREATE INDEX idx_ideas_needs_rerun ON ideas(needs_rerun) WHERE needs_rerun = TRUE;
CREATE INDEX idx_ideas_archived ON ideas(is_archived) WHERE is_archived = FALSE;
CREATE INDEX idx_ideas_external_id ON ideas(external_id) WHERE external_id IS NOT NULL;

-- Comments
COMMENT ON TABLE ideas IS 'Core idea entity tracking lifecycle through stage-gates';
COMMENT ON COLUMN ideas.slug IS 'URL-safe identifier, unique per workspace';
COMMENT ON COLUMN ideas.external_id IS 'External reference (e.g., Google Drive file ID)';
COMMENT ON COLUMN ideas.lifecycle_status IS 'Current position in stage-gate lifecycle';
COMMENT ON COLUMN ideas.current_gate IS 'Current or last completed gate';
COMMENT ON COLUMN ideas.latest_decision IS 'Most recent gate decision';
COMMENT ON COLUMN ideas.score_total IS 'Weighted total score (0.0-1.0)';
COMMENT ON COLUMN ideas.evidence_level IS 'Current evidence level (determines confidence cap)';
COMMENT ON COLUMN ideas.confidence IS 'Confidence percentage (capped by evidence level)';
COMMENT ON COLUMN ideas.human_handoff IS 'Human handoff JSON (populated at G5)';
COMMENT ON COLUMN ideas.build_pack IS 'Build pack JSON for builder assistant (populated at G5)';
COMMENT ON COLUMN ideas.needs_rerun IS 'Flag indicating gate needs re-evaluation after config change';

-- ============================================================================
-- IDEA_INTAKE_VERSIONS TABLE
-- ============================================================================

CREATE TABLE idea_intake_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idea_id UUID NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Version tracking
  version INTEGER NOT NULL DEFAULT 1,
  is_latest BOOLEAN NOT NULL DEFAULT TRUE,

  -- Intake data
  intake JSONB NOT NULL,  -- Validated against IdeaIntakeSchema

  -- Source tracking
  source_file_id TEXT,      -- Google Drive file ID
  source_file_name TEXT,    -- Original file name
  source_raw_content TEXT,  -- Raw file content before parsing

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Unique constraint: one version number per idea
  CONSTRAINT unique_idea_version UNIQUE (idea_id, version)
);

-- Indexes for idea_intake_versions
CREATE INDEX idx_intake_versions_idea_id ON idea_intake_versions(idea_id);
CREATE INDEX idx_intake_versions_workspace_id ON idea_intake_versions(workspace_id);
CREATE INDEX idx_intake_versions_is_latest ON idea_intake_versions(is_latest) WHERE is_latest = TRUE;
CREATE INDEX idx_intake_versions_created_at ON idea_intake_versions(created_at DESC);
CREATE INDEX idx_intake_versions_source_file ON idea_intake_versions(source_file_id) WHERE source_file_id IS NOT NULL;

-- Comments
COMMENT ON TABLE idea_intake_versions IS 'Versioned intake data for ideas (immutable history)';
COMMENT ON COLUMN idea_intake_versions.version IS 'Version number, increments on each update';
COMMENT ON COLUMN idea_intake_versions.is_latest IS 'Flag indicating this is the current active version';
COMMENT ON COLUMN idea_intake_versions.intake IS 'Validated intake JSON (IdeaIntakeSchema)';
COMMENT ON COLUMN idea_intake_versions.source_file_id IS 'Google Drive file ID if ingested from Drive';
COMMENT ON COLUMN idea_intake_versions.source_raw_content IS 'Raw content before validation (for debugging)';

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Apply updated_at trigger to ideas
CREATE TRIGGER tr_ideas_updated_at
  BEFORE UPDATE ON ideas
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Trigger to set is_latest = FALSE on older versions when new version is inserted
CREATE OR REPLACE FUNCTION set_previous_versions_not_latest()
RETURNS TRIGGER AS $$
BEGIN
  -- Set all previous versions for this idea to is_latest = FALSE
  UPDATE idea_intake_versions
  SET is_latest = FALSE
  WHERE idea_id = NEW.idea_id
    AND id != NEW.id
    AND is_latest = TRUE;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_intake_versions_set_latest
  AFTER INSERT ON idea_intake_versions
  FOR EACH ROW
  EXECUTE FUNCTION set_previous_versions_not_latest();

-- Trigger to auto-increment version number
CREATE OR REPLACE FUNCTION set_intake_version_number()
RETURNS TRIGGER AS $$
BEGIN
  -- Get the next version number for this idea
  SELECT COALESCE(MAX(version), 0) + 1
  INTO NEW.version
  FROM idea_intake_versions
  WHERE idea_id = NEW.idea_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_intake_versions_set_version
  BEFORE INSERT ON idea_intake_versions
  FOR EACH ROW
  EXECUTE FUNCTION set_intake_version_number();

-- ============================================================================
-- ROW LEVEL SECURITY - IDEAS
-- ============================================================================

ALTER TABLE ideas ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view ideas in their workspaces
CREATE POLICY ideas_select_policy ON ideas
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Editors and admins can create ideas
CREATE POLICY ideas_insert_policy ON ideas
  FOR INSERT
  WITH CHECK (is_workspace_editor(workspace_id));

-- UPDATE: Editors and admins can update ideas
CREATE POLICY ideas_update_policy ON ideas
  FOR UPDATE
  USING (is_workspace_editor(workspace_id))
  WITH CHECK (is_workspace_editor(workspace_id));

-- DELETE: Only admins can delete ideas
CREATE POLICY ideas_delete_policy ON ideas
  FOR DELETE
  USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- ROW LEVEL SECURITY - IDEA_INTAKE_VERSIONS
-- ============================================================================

ALTER TABLE idea_intake_versions ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view intake versions in their workspaces
CREATE POLICY intake_versions_select_policy ON idea_intake_versions
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Editors and admins can create intake versions
CREATE POLICY intake_versions_insert_policy ON idea_intake_versions
  FOR INSERT
  WITH CHECK (is_workspace_editor(workspace_id));

-- UPDATE: Not allowed - intake versions are immutable
-- (No update policy = no updates allowed)

-- DELETE: Only admins can delete intake versions
CREATE POLICY intake_versions_delete_policy ON idea_intake_versions
  FOR DELETE
  USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- POLICY COMMENTS
-- ============================================================================

COMMENT ON POLICY ideas_select_policy ON ideas IS 'Members can view ideas in their workspace';
COMMENT ON POLICY ideas_insert_policy ON ideas IS 'Editors and admins can create ideas';
COMMENT ON POLICY ideas_update_policy ON ideas IS 'Editors and admins can update ideas';
COMMENT ON POLICY ideas_delete_policy ON ideas IS 'Only admins can delete ideas';

COMMENT ON POLICY intake_versions_select_policy ON idea_intake_versions IS 'Members can view intake versions';
COMMENT ON POLICY intake_versions_insert_policy ON idea_intake_versions IS 'Editors and admins can create intake versions';
COMMENT ON POLICY intake_versions_delete_policy ON idea_intake_versions IS 'Only admins can delete intake versions (versions are immutable)';
