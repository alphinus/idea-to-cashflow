-- Migration: Create all enum types for Stage-Gate system
-- Feature: F001
-- Description: Defines all enumeration types used throughout the system

-- ============================================================================
-- WORKSPACE & MEMBERSHIP ENUMS
-- ============================================================================

-- User roles within a workspace
CREATE TYPE workspace_role AS ENUM (
  'ADMIN',      -- Full access: manage members, override decisions, change config
  'EDITOR',     -- Can create/edit ideas, run gates, add evidence
  'VIEWER'      -- Read-only access
);

-- ============================================================================
-- IDEA LIFECYCLE ENUMS
-- ============================================================================

-- Lifecycle status of an idea (tracks progression through system)
CREATE TYPE lifecycle_status AS ENUM (
  'CREATED',                -- Initial intake complete
  'IN_TRIAGE',             -- G1 running
  'KILLED_AT_TRIAGE',      -- Hard kill at G1
  'IN_MARKET_FIT',         -- G2 running
  'KILLED_AT_MARKET_FIT',  -- Killed at G2
  'IN_ECONOMICS',          -- G3 running
  'KILLED_AT_ECONOMICS',   -- Killed at G3
  'IN_VALIDATION',         -- G4 running
  'KILLED_AT_VALIDATION',  -- Killed at G4
  'PENDING_HANDOFF',       -- G4 passed, generating handoff
  'AWAITING_APPROVAL',     -- Human handoff ready, awaiting approval
  'APPROVED_FOR_BUILD',    -- Human approved, ready for builder
  'IN_BUILD',              -- Builder assistant started
  'ARCHIVED'               -- Manually archived
);

-- ============================================================================
-- GATE ENUMS
-- ============================================================================

-- Stage-Gate definitions (G0-G5)
CREATE TYPE gate AS ENUM (
  'G0_INTAKE',      -- Initial ingestion from Drive
  'G1_TRIAGE',      -- Hard kills + quick score
  'G2_MARKET_FIT',  -- Market validation
  'G3_ECONOMICS',   -- Unit economics
  'G4_VALIDATION',  -- Validation plan + MVP scope
  'G5_HANDOFF'      -- Generate handoffs + build decision
);

-- Gate decision outcomes
CREATE TYPE gate_decision AS ENUM (
  'GO',              -- Pass: proceed to next gate
  'REVISE',          -- Conditional: needs more work/evidence
  'KILL',            -- Terminate idea
  'OVERRIDE_GO',     -- Human override: force GO
  'OVERRIDE_KILL'    -- Human override: force KILL
);

-- Hard kill reasons (G1 triage)
CREATE TYPE kill_reason AS ENUM (
  'LEGAL_RED_FLAG',           -- Legal/regulatory blocker
  'NO_MONETIZATION',          -- No viable revenue model
  'NO_DISTRIBUTION_PATH',     -- No way to reach customers
  'MARGIN_BELOW_MIN',         -- Unit economics impossible
  'TIME_TO_CASHFLOW_TOO_LONG', -- Payback period exceeds limits
  'CUSTOM'                    -- Custom reason (store in text field)
);

-- Gate run status
CREATE TYPE gate_run_status AS ENUM (
  'PENDING',          -- Queued for execution
  'RUNNING',          -- Currently executing
  'COMPLETED',        -- Finished successfully
  'FAILED_RETRY',     -- Failed, will retry
  'FAILED_PERMANENT'  -- Failed permanently (needs human intervention)
);

-- ============================================================================
-- AGENT & ANALYSIS ENUMS
-- ============================================================================

-- Agent types for multi-agent analysis
CREATE TYPE agent_type AS ENUM (
  'MARKET_LIGHT',    -- Quick market sizing (G1)
  'RISK',            -- Risk assessment (G1)
  'MARKET_DEEP',     -- Deep market analysis (G2)
  'COMPETITOR',      -- Competitor scan (G2)
  'ECONOMICS',       -- Unit economics model (G3)
  'PRICING',         -- Pricing analysis (G3)
  'EXPERIMENT',      -- Experiment design (G4)
  'MVP_SCOPE',       -- MVP scoping (G4)
  'BUILD_DECISION',  -- Build vs buy vs partner (G5)
  'ORCHESTRATOR'     -- Orchestrator decision synthesis
);

-- Evidence types for validation
CREATE TYPE evidence_type AS ENUM (
  'DESK_RESEARCH',        -- Level 1: Secondary research
  'COMPETITOR_SCAN',      -- Level 1: Competitive analysis
  'UNIT_ECON_MODEL',      -- Level 1: Financial model
  'PRICING_HYPOTHESIS',   -- Level 1: Pricing research
  'EXPERT_INTERVIEW',     -- Level 2: Expert interviews
  'USER_INTERVIEW',       -- Level 2: User interviews
  'SURVEY',               -- Level 2: Survey data
  'LANDING_PAGE_TEST',    -- Level 3: Landing page signups
  'WAITLIST',             -- Level 3: Waitlist signups
  'EXPERIMENT_PLAN',      -- Level 3: Validation experiment design
  'MVP_SCOPE',            -- Level 3: MVP definition
  'AD_CLICK',             -- Level 3: Paid ad engagement
  'PREORDER',             -- Level 4: Pre-purchase commitment
  'PAID_PILOT',           -- Level 4: Paid test transaction
  'REVENUE',              -- Level 5: Actual revenue
  'RETENTION_DATA'        -- Level 5: Repeat purchase/usage
);

-- Evidence level (0-5 scale)
CREATE TYPE evidence_level AS ENUM (
  'LEVEL_0',  -- None
  'LEVEL_1',  -- Desk research
  'LEVEL_2',  -- Interviews
  'LEVEL_3',  -- Behavioral signals
  'LEVEL_4',  -- Paid signal
  'LEVEL_5'   -- Repeatable revenue/retention
);

-- ============================================================================
-- TASK & MILESTONE ENUMS
-- ============================================================================

-- Task priority
CREATE TYPE task_priority AS ENUM (
  'P0',  -- Critical blocker
  'P1',  -- High priority
  'P2',  -- Medium priority
  'P3'   -- Low priority
);

-- Task status
CREATE TYPE task_status AS ENUM (
  'TODO',         -- Not started
  'IN_PROGRESS',  -- Currently being worked on
  'BLOCKED',      -- Blocked by dependency
  'DONE',         -- Completed
  'CANCELLED'     -- Cancelled/no longer needed
);

-- Milestone status
CREATE TYPE milestone_status AS ENUM (
  'PLANNED',     -- Future milestone
  'IN_PROGRESS', -- Currently working toward
  'COMPLETED',   -- Achieved
  'MISSED',      -- Deadline passed without completion
  'CANCELLED'    -- No longer relevant
);

-- ============================================================================
-- SYNC & INTEGRATION ENUMS
-- ============================================================================

-- Outbox operation types for calendar sync
CREATE TYPE outbox_operation AS ENUM (
  'UPSERT_EVENT',   -- Create or update calendar event
  'CANCEL_EVENT',   -- Cancel/delete calendar event
  'REBUILD_ALL'     -- Full rebuild for workspace
);

-- Outbox processing status
CREATE TYPE outbox_status AS ENUM (
  'PENDING',     -- Waiting to be processed
  'PROCESSING',  -- Currently being processed
  'COMPLETED',   -- Successfully processed
  'FAILED',      -- Failed, will retry
  'DEAD_LETTER'  -- Failed permanently after max retries
);

-- Calendar event types
CREATE TYPE calendar_event_type AS ENUM (
  'GATE_REVIEW',       -- Gate review reminder (+24h)
  'BLOCKER_DEADLINE',  -- P1 blocking task deadline
  'MILESTONE',         -- Milestone due date
  'PROJECT_REVIEW'     -- Weekly recurring review
);

-- Google connection status
CREATE TYPE connection_status AS ENUM (
  'ACTIVE',     -- Connected and valid
  'INVALID',    -- Token expired/revoked
  'ERROR'       -- Connection error
);

-- ============================================================================
-- AUDIT & CONFIG ENUMS
-- ============================================================================

-- Audit log action types
CREATE TYPE audit_action AS ENUM (
  'GATE_RUN',           -- Gate execution
  'DECISION_OVERRIDE',  -- Manual decision override
  'CONFIG_CHANGE',      -- Config version change
  'PROMPT_CHANGE',      -- Prompt version change
  'TASK_CREATE',        -- Task created
  'TASK_UPDATE',        -- Task updated
  'EVIDENCE_ADD',       -- Evidence added
  'APPROVAL_GRANT',     -- Human approval granted
  'WORKSPACE_CREATE',   -- Workspace created
  'MEMBER_ADD',         -- Member added to workspace
  'MEMBER_REMOVE'       -- Member removed from workspace
);

-- Assumption criticality level
CREATE TYPE criticality_level AS ENUM (
  'LOW',     -- Nice to validate
  'MEDIUM',  -- Should validate
  'HIGH',    -- Must validate
  'CRITICAL' -- Blocker if false
);

-- Risk impact level
CREATE TYPE risk_impact AS ENUM (
  'LOW',
  'MEDIUM',
  'HIGH',
  'CRITICAL'
);

-- Risk likelihood
CREATE TYPE risk_likelihood AS ENUM (
  'LOW',
  'MEDIUM',
  'HIGH',
  'VERY_HIGH'
);

-- ============================================================================
-- COMMENT
-- ============================================================================

COMMENT ON TYPE workspace_role IS 'User roles within a workspace (admin/editor/viewer)';
COMMENT ON TYPE lifecycle_status IS 'Idea lifecycle status tracking progression through gates';
COMMENT ON TYPE gate IS 'Stage-Gate definitions (G0-G5)';
COMMENT ON TYPE gate_decision IS 'Gate decision outcomes (GO/REVISE/KILL + overrides)';
COMMENT ON TYPE kill_reason IS 'Hard kill reasons at G1 triage';
COMMENT ON TYPE gate_run_status IS 'Gate run execution status';
COMMENT ON TYPE agent_type IS 'Multi-agent analysis types';
COMMENT ON TYPE evidence_type IS 'Evidence types for validation';
COMMENT ON TYPE evidence_level IS 'Evidence level scale (0-5)';
COMMENT ON TYPE task_priority IS 'Task priority (P0-P3)';
COMMENT ON TYPE task_status IS 'Task status (TODO/IN_PROGRESS/BLOCKED/DONE/CANCELLED)';
COMMENT ON TYPE milestone_status IS 'Milestone status';
COMMENT ON TYPE outbox_operation IS 'Outbox operation types for calendar sync';
COMMENT ON TYPE outbox_status IS 'Outbox processing status';
COMMENT ON TYPE calendar_event_type IS 'Calendar event types';
COMMENT ON TYPE connection_status IS 'Google connection status';
COMMENT ON TYPE audit_action IS 'Audit log action types';
COMMENT ON TYPE criticality_level IS 'Assumption criticality level';
COMMENT ON TYPE risk_impact IS 'Risk impact level';
COMMENT ON TYPE risk_likelihood IS 'Risk likelihood level';
