-- Migration: Create config_versions table with versioning
-- Feature: F008
-- Description: Configuration versioning for decision engine (weights, thresholds, kill rules)

-- ============================================================================
-- CONFIG_VERSIONS TABLE
-- ============================================================================

CREATE TABLE config_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Version metadata
  version INTEGER NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT false,

  -- Scoring weights (all JSONB for flexibility)
  -- G1 Triage weights
  weights_g1 JSONB NOT NULL DEFAULT '{
    "market_opportunity": 0.25,
    "competitive_moat": 0.15,
    "execution_feasibility": 0.20,
    "risk_penalty_max": 0.40
  }',

  -- G2 Market Fit weights
  weights_g2 JSONB NOT NULL DEFAULT '{
    "market_size": 0.30,
    "product_market_fit": 0.25,
    "competitive_position": 0.20,
    "customer_access": 0.15,
    "evidence_bonus": 0.10
  }',

  -- G3 Economics weights
  weights_g3 JSONB NOT NULL DEFAULT '{
    "unit_economics": 0.35,
    "margin_quality": 0.25,
    "cac_efficiency": 0.20,
    "time_to_cashflow": 0.20
  }',

  -- G4 Validation Plan weights
  weights_g4 JSONB NOT NULL DEFAULT '{
    "experiment_quality": 0.30,
    "validation_rigor": 0.25,
    "mvp_scope_clarity": 0.25,
    "risk_coverage": 0.20
  }',

  -- G5 Handoff weights
  weights_g5 JSONB NOT NULL DEFAULT '{
    "build_clarity": 0.30,
    "resource_availability": 0.25,
    "technical_feasibility": 0.25,
    "approval_readiness": 0.20
  }',

  -- Decision thresholds per gate (0-100 scale)
  thresholds JSONB NOT NULL DEFAULT '{
    "g1": {"go": 60, "revise": 40, "kill": 0},
    "g2": {"go": 65, "revise": 45, "kill": 0},
    "g3": {"go": 70, "revise": 50, "kill": 0},
    "g4": {"go": 75, "revise": 55, "kill": 0},
    "g5": {"go": 80, "revise": 60, "kill": 0}
  }',

  -- Hard kill rules (array of kill_reason enums that trigger automatic KILL)
  kill_rules JSONB NOT NULL DEFAULT '["LEGAL_RED_FLAG", "NO_MONETIZATION", "NO_DISTRIBUTION_PATH"]',

  -- Evidence level requirements per gate
  evidence_requirements JSONB NOT NULL DEFAULT '{
    "g1": 0,
    "g2": 1,
    "g3": 2,
    "g4": 3,
    "g5": 3
  }',

  -- Confidence coupling (evidence_level -> confidence_multiplier)
  confidence_coupling JSONB NOT NULL DEFAULT '{
    "0": 0.5,
    "1": 0.7,
    "2": 0.85,
    "3": 0.95,
    "4": 1.0,
    "5": 1.0
  }',

  -- Risk penalty configuration
  risk_config JSONB NOT NULL DEFAULT '{
    "max_penalty": 40,
    "impact_weights": {"LOW": 0.2, "MEDIUM": 0.5, "HIGH": 0.8, "CRITICAL": 1.0},
    "likelihood_weights": {"LOW": 0.2, "MEDIUM": 0.5, "HIGH": 0.8, "VERY_HIGH": 1.0}
  }',

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),

  -- Unique constraint: one version number per workspace
  CONSTRAINT unique_workspace_version UNIQUE (workspace_id, version)
);

-- Indexes for config_versions
CREATE INDEX idx_config_versions_workspace_id ON config_versions(workspace_id);
CREATE INDEX idx_config_versions_is_active ON config_versions(is_active) WHERE is_active = true;
CREATE INDEX idx_config_versions_version ON config_versions(version);
CREATE INDEX idx_config_versions_created_at ON config_versions(created_at DESC);

-- Comments
COMMENT ON TABLE config_versions IS 'Versioned configuration for decision engine weights, thresholds, and kill rules';
COMMENT ON COLUMN config_versions.version IS 'Integer version number (auto-increment per workspace)';
COMMENT ON COLUMN config_versions.description IS 'Human-readable description of what changed in this version';
COMMENT ON COLUMN config_versions.is_active IS 'Flag indicating the currently active config (only one per workspace)';
COMMENT ON COLUMN config_versions.weights_g1 IS 'Scoring weights for G1 Triage gate';
COMMENT ON COLUMN config_versions.weights_g2 IS 'Scoring weights for G2 Market Fit gate';
COMMENT ON COLUMN config_versions.weights_g3 IS 'Scoring weights for G3 Economics gate';
COMMENT ON COLUMN config_versions.weights_g4 IS 'Scoring weights for G4 Validation Plan gate';
COMMENT ON COLUMN config_versions.weights_g5 IS 'Scoring weights for G5 Handoff gate';
COMMENT ON COLUMN config_versions.thresholds IS 'Decision thresholds (GO/REVISE/KILL) per gate on 0-100 scale';
COMMENT ON COLUMN config_versions.kill_rules IS 'Array of kill_reason enums that trigger automatic KILL decision';
COMMENT ON COLUMN config_versions.evidence_requirements IS 'Minimum evidence_level required per gate (0-5)';
COMMENT ON COLUMN config_versions.confidence_coupling IS 'Confidence multiplier by evidence_level (deterministic coupling)';
COMMENT ON COLUMN config_versions.risk_config IS 'Risk penalty configuration (max penalty, impact/likelihood weights)';
COMMENT ON COLUMN config_versions.created_by IS 'User who created this config version';

-- ============================================================================
-- TRIGGER: Ensure only one active config per workspace
-- ============================================================================

CREATE OR REPLACE FUNCTION ensure_single_active_config()
RETURNS TRIGGER AS $$
BEGIN
  -- If setting this config to active, deactivate all others in the workspace
  IF NEW.is_active = true THEN
    UPDATE config_versions
    SET is_active = false
    WHERE workspace_id = NEW.workspace_id
      AND id != NEW.id
      AND is_active = true;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_config_versions_single_active
  BEFORE INSERT OR UPDATE ON config_versions
  FOR EACH ROW
  WHEN (NEW.is_active = true)
  EXECUTE FUNCTION ensure_single_active_config();

COMMENT ON FUNCTION ensure_single_active_config() IS 'Ensures only one config version is active per workspace';

-- ============================================================================
-- FUNCTION: Get next version number for workspace
-- ============================================================================

CREATE OR REPLACE FUNCTION get_next_config_version(ws_id UUID)
RETURNS INTEGER AS $$
  SELECT COALESCE(MAX(version), 0) + 1
  FROM config_versions
  WHERE workspace_id = ws_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION get_next_config_version(UUID) IS 'Returns the next available version number for a workspace';

-- ============================================================================
-- FUNCTION: Get active config for workspace
-- ============================================================================

CREATE OR REPLACE FUNCTION get_active_config(ws_id UUID)
RETURNS UUID AS $$
  SELECT id
  FROM config_versions
  WHERE workspace_id = ws_id
    AND is_active = true
  LIMIT 1;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION get_active_config(UUID) IS 'Returns the ID of the active config version for a workspace';

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE config_versions ENABLE ROW LEVEL SECURITY;

-- SELECT: All workspace members can view config versions
CREATE POLICY config_versions_select_policy ON config_versions
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Only admins can create new config versions
CREATE POLICY config_versions_insert_policy ON config_versions
  FOR INSERT
  WITH CHECK (is_workspace_admin(workspace_id));

-- UPDATE: Only admins can update config versions (e.g., activate/deactivate)
CREATE POLICY config_versions_update_policy ON config_versions
  FOR UPDATE
  USING (is_workspace_admin(workspace_id))
  WITH CHECK (is_workspace_admin(workspace_id));

-- DELETE: Only admins can delete config versions (but not active ones)
CREATE POLICY config_versions_delete_policy ON config_versions
  FOR DELETE
  USING (
    is_workspace_admin(workspace_id)
    AND is_active = false
  );

COMMENT ON POLICY config_versions_select_policy ON config_versions IS 'All workspace members can view config versions';
COMMENT ON POLICY config_versions_insert_policy ON config_versions IS 'Only admins can create new config versions';
COMMENT ON POLICY config_versions_update_policy ON config_versions IS 'Only admins can update config versions';
COMMENT ON POLICY config_versions_delete_policy ON config_versions IS 'Admins can delete inactive config versions only';

-- ============================================================================
-- VALIDATION CONSTRAINTS
-- ============================================================================

-- Add check constraint to ensure weights sum to approximately 1.0 (allowing small floating point variance)
-- This is enforced at application level, but we add comments for documentation
COMMENT ON COLUMN config_versions.weights_g1 IS 'Weights should sum to ~1.0. Example: {"market_opportunity": 0.25, "competitive_moat": 0.15, "execution_feasibility": 0.20, "risk_penalty_max": 0.40}';
COMMENT ON COLUMN config_versions.weights_g2 IS 'Weights should sum to ~1.0. Example: {"market_size": 0.30, "product_market_fit": 0.25, "competitive_position": 0.20, "customer_access": 0.15, "evidence_bonus": 0.10}';
COMMENT ON COLUMN config_versions.weights_g3 IS 'Weights should sum to ~1.0. Example: {"unit_economics": 0.35, "margin_quality": 0.25, "cac_efficiency": 0.20, "time_to_cashflow": 0.20}';
COMMENT ON COLUMN config_versions.weights_g4 IS 'Weights should sum to ~1.0. Example: {"experiment_quality": 0.30, "validation_rigor": 0.25, "mvp_scope_clarity": 0.25, "risk_coverage": 0.20}';
COMMENT ON COLUMN config_versions.weights_g5 IS 'Weights should sum to ~1.0. Example: {"build_clarity": 0.30, "resource_availability": 0.25, "technical_feasibility": 0.25, "approval_readiness": 0.20}';
