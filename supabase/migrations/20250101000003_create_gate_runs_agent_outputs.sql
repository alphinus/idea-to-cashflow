-- Migration: Create gate_runs and agent_outputs tables with RLS
-- Feature: F004
-- Description: Gate run tracking with agent analysis outputs

-- ============================================================================
-- GATE_RUNS TABLE
-- ============================================================================

CREATE TABLE gate_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idea_id UUID NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Gate identification
  gate gate NOT NULL,
  run_number INTEGER NOT NULL DEFAULT 1,  -- Increments per gate per idea

  -- Idempotency (prevents duplicate runs)
  idempotency_key TEXT NOT NULL,

  -- Execution status
  status gate_run_status NOT NULL DEFAULT 'PENDING',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,  -- For FAILED_RETRY or FAILED_PERMANENT

  -- Decision output
  decision gate_decision,
  kill_reason kill_reason,
  kill_reason_custom TEXT,  -- For CUSTOM kill reason

  -- Scoring (0.0 - 1.0 range)
  score_total NUMERIC(4, 3) CHECK (score_total IS NULL OR (score_total >= 0 AND score_total <= 1)),
  score_market NUMERIC(4, 3) CHECK (score_market IS NULL OR (score_market >= 0 AND score_market <= 1)),
  score_risk NUMERIC(4, 3) CHECK (score_risk IS NULL OR (score_risk >= 0 AND score_risk <= 1)),
  score_economics NUMERIC(4, 3) CHECK (score_economics IS NULL OR (score_economics >= 0 AND score_economics <= 1)),
  score_validation NUMERIC(4, 3) CHECK (score_validation IS NULL OR (score_validation >= 0 AND score_validation <= 1)),

  -- Evidence level (determines confidence cap)
  evidence_level evidence_level,

  -- Confidence (0-100, capped by evidence level)
  confidence INTEGER CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 100)),

  -- Override tracking
  is_override BOOLEAN NOT NULL DEFAULT FALSE,
  override_by UUID REFERENCES auth.users(id),
  override_reason TEXT,
  override_at TIMESTAMPTZ,

  -- Config snapshot (reference to active config at run time)
  config_version_id UUID,  -- FK added when config_versions table is created

  -- Prompt bundle snapshot (reference to prompts used)
  prompt_bundle_id UUID,  -- FK added when prompt_bundles table is created

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Unique constraints
  CONSTRAINT unique_idempotency_key UNIQUE (idempotency_key),
  CONSTRAINT unique_idea_gate_run UNIQUE (idea_id, gate, run_number)
);

-- Indexes for gate_runs
CREATE INDEX idx_gate_runs_idea_id ON gate_runs(idea_id);
CREATE INDEX idx_gate_runs_workspace_id ON gate_runs(workspace_id);
CREATE INDEX idx_gate_runs_gate ON gate_runs(gate);
CREATE INDEX idx_gate_runs_status ON gate_runs(status);
CREATE INDEX idx_gate_runs_decision ON gate_runs(decision);
CREATE INDEX idx_gate_runs_created_at ON gate_runs(created_at DESC);
CREATE INDEX idx_gate_runs_completed_at ON gate_runs(completed_at DESC);
CREATE INDEX idx_gate_runs_idempotency ON gate_runs(idempotency_key);
CREATE INDEX idx_gate_runs_idea_gate ON gate_runs(idea_id, gate);
CREATE INDEX idx_gate_runs_pending ON gate_runs(status) WHERE status IN ('PENDING', 'RUNNING');
CREATE INDEX idx_gate_runs_overrides ON gate_runs(is_override) WHERE is_override = TRUE;

-- Comments
COMMENT ON TABLE gate_runs IS 'Execution records for stage-gate runs with decisions and scores';
COMMENT ON COLUMN gate_runs.run_number IS 'Run number for this gate on this idea (increments on re-run)';
COMMENT ON COLUMN gate_runs.idempotency_key IS 'Unique key preventing duplicate runs (idea_id:gate:timestamp or custom)';
COMMENT ON COLUMN gate_runs.status IS 'Execution status (PENDING/RUNNING/COMPLETED/FAILED_*)';
COMMENT ON COLUMN gate_runs.decision IS 'Gate decision (GO/REVISE/KILL or OVERRIDE_*)';
COMMENT ON COLUMN gate_runs.score_total IS 'Weighted total score (0.0-1.0)';
COMMENT ON COLUMN gate_runs.evidence_level IS 'Evidence level at time of run (determines confidence cap)';
COMMENT ON COLUMN gate_runs.confidence IS 'Confidence percentage (capped by evidence level)';
COMMENT ON COLUMN gate_runs.is_override IS 'Whether this decision was a human override';
COMMENT ON COLUMN gate_runs.override_reason IS 'Mandatory reason for override decisions';
COMMENT ON COLUMN gate_runs.config_version_id IS 'Reference to config version used (FK added later)';
COMMENT ON COLUMN gate_runs.prompt_bundle_id IS 'Reference to prompt bundle used (FK added later)';

-- ============================================================================
-- AGENT_OUTPUTS TABLE
-- ============================================================================

CREATE TABLE agent_outputs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gate_run_id UUID NOT NULL REFERENCES gate_runs(id) ON DELETE CASCADE,
  idea_id UUID NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Agent identification
  agent_type agent_type NOT NULL,
  agent_version TEXT,  -- Version of the agent/prompt used

  -- Execution status
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,  -- For failed agent runs
  is_success BOOLEAN NOT NULL DEFAULT FALSE,

  -- Agent findings (structured output from LLM)
  findings JSONB,  -- Main analysis findings
  metrics JSONB,   -- Calculated metrics (all 0.0-1.0 range)
  recommendations JSONB,  -- Agent recommendations

  -- Raw response (for debugging/audit)
  raw_response TEXT,  -- Raw LLM response before parsing
  prompt_used TEXT,   -- Actual prompt sent to LLM

  -- Token usage for budget tracking
  tokens_input INTEGER,
  tokens_output INTEGER,
  model_used TEXT,  -- e.g., 'claude-3-opus', 'gpt-4'

  -- Confidence and evidence
  confidence INTEGER CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 100)),
  evidence_level evidence_level,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One agent output per type per gate run
  CONSTRAINT unique_agent_per_run UNIQUE (gate_run_id, agent_type)
);

-- Indexes for agent_outputs
CREATE INDEX idx_agent_outputs_gate_run_id ON agent_outputs(gate_run_id);
CREATE INDEX idx_agent_outputs_idea_id ON agent_outputs(idea_id);
CREATE INDEX idx_agent_outputs_workspace_id ON agent_outputs(workspace_id);
CREATE INDEX idx_agent_outputs_agent_type ON agent_outputs(agent_type);
CREATE INDEX idx_agent_outputs_is_success ON agent_outputs(is_success);
CREATE INDEX idx_agent_outputs_created_at ON agent_outputs(created_at DESC);
CREATE INDEX idx_agent_outputs_model_used ON agent_outputs(model_used) WHERE model_used IS NOT NULL;

-- Comments
COMMENT ON TABLE agent_outputs IS 'Output from individual agents during gate runs';
COMMENT ON COLUMN agent_outputs.agent_type IS 'Type of agent (MARKET_LIGHT, RISK, etc.)';
COMMENT ON COLUMN agent_outputs.agent_version IS 'Version identifier for the agent/prompt';
COMMENT ON COLUMN agent_outputs.findings IS 'Structured analysis findings (JSON)';
COMMENT ON COLUMN agent_outputs.metrics IS 'Calculated metrics, all in 0.0-1.0 range (JSON)';
COMMENT ON COLUMN agent_outputs.recommendations IS 'Agent recommendations (JSON)';
COMMENT ON COLUMN agent_outputs.raw_response IS 'Raw LLM response before JSON parsing (for debugging)';
COMMENT ON COLUMN agent_outputs.tokens_input IS 'Input tokens consumed';
COMMENT ON COLUMN agent_outputs.tokens_output IS 'Output tokens generated';
COMMENT ON COLUMN agent_outputs.model_used IS 'LLM model identifier (e.g., claude-3-opus)';
COMMENT ON COLUMN agent_outputs.confidence IS 'Agent confidence in findings (0-100)';
COMMENT ON COLUMN agent_outputs.evidence_level IS 'Evidence level assessed by agent';

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Apply updated_at trigger to gate_runs
CREATE TRIGGER tr_gate_runs_updated_at
  BEFORE UPDATE ON gate_runs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Apply updated_at trigger to agent_outputs
CREATE TRIGGER tr_agent_outputs_updated_at
  BEFORE UPDATE ON agent_outputs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Trigger to auto-increment run_number for gate_runs
CREATE OR REPLACE FUNCTION set_gate_run_number()
RETURNS TRIGGER AS $$
BEGIN
  -- Get the next run number for this idea and gate
  SELECT COALESCE(MAX(run_number), 0) + 1
  INTO NEW.run_number
  FROM gate_runs
  WHERE idea_id = NEW.idea_id
    AND gate = NEW.gate;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_gate_runs_set_run_number
  BEFORE INSERT ON gate_runs
  FOR EACH ROW
  EXECUTE FUNCTION set_gate_run_number();

-- ============================================================================
-- ROW LEVEL SECURITY - GATE_RUNS
-- ============================================================================

ALTER TABLE gate_runs ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view gate runs in their workspaces
CREATE POLICY gate_runs_select_policy ON gate_runs
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Editors and admins can create gate runs
CREATE POLICY gate_runs_insert_policy ON gate_runs
  FOR INSERT
  WITH CHECK (is_workspace_editor(workspace_id));

-- UPDATE: Editors and admins can update gate runs (for status updates, overrides)
CREATE POLICY gate_runs_update_policy ON gate_runs
  FOR UPDATE
  USING (is_workspace_editor(workspace_id))
  WITH CHECK (is_workspace_editor(workspace_id));

-- DELETE: Only admins can delete gate runs
CREATE POLICY gate_runs_delete_policy ON gate_runs
  FOR DELETE
  USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- ROW LEVEL SECURITY - AGENT_OUTPUTS
-- ============================================================================

ALTER TABLE agent_outputs ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view agent outputs in their workspaces
CREATE POLICY agent_outputs_select_policy ON agent_outputs
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Editors and admins can create agent outputs
CREATE POLICY agent_outputs_insert_policy ON agent_outputs
  FOR INSERT
  WITH CHECK (is_workspace_editor(workspace_id));

-- UPDATE: Editors and admins can update agent outputs (for completion status)
CREATE POLICY agent_outputs_update_policy ON agent_outputs
  FOR UPDATE
  USING (is_workspace_editor(workspace_id))
  WITH CHECK (is_workspace_editor(workspace_id));

-- DELETE: Only admins can delete agent outputs
CREATE POLICY agent_outputs_delete_policy ON agent_outputs
  FOR DELETE
  USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- POLICY COMMENTS
-- ============================================================================

COMMENT ON POLICY gate_runs_select_policy ON gate_runs IS 'Members can view gate runs in their workspace';
COMMENT ON POLICY gate_runs_insert_policy ON gate_runs IS 'Editors and admins can create gate runs';
COMMENT ON POLICY gate_runs_update_policy ON gate_runs IS 'Editors and admins can update gate runs';
COMMENT ON POLICY gate_runs_delete_policy ON gate_runs IS 'Only admins can delete gate runs';

COMMENT ON POLICY agent_outputs_select_policy ON agent_outputs IS 'Members can view agent outputs';
COMMENT ON POLICY agent_outputs_insert_policy ON agent_outputs IS 'Editors and admins can create agent outputs';
COMMENT ON POLICY agent_outputs_update_policy ON agent_outputs IS 'Editors and admins can update agent outputs';
COMMENT ON POLICY agent_outputs_delete_policy ON agent_outputs IS 'Only admins can delete agent outputs';
