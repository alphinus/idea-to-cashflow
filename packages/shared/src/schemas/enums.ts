/**
 * Zod schemas for all database enum types
 * Feature: F001
 *
 * IMPORTANT: These schemas MUST stay in sync with database enum definitions
 * in supabase/migrations/20250101000000_create_enum_types.sql
 */

import { z } from 'zod';

// ============================================================================
// WORKSPACE & MEMBERSHIP ENUMS
// ============================================================================

export const WorkspaceRoleSchema = z.enum([
  'ADMIN',
  'EDITOR',
  'VIEWER',
]);
export type WorkspaceRole = z.infer<typeof WorkspaceRoleSchema>;

// ============================================================================
// IDEA LIFECYCLE ENUMS
// ============================================================================

export const LifecycleStatusSchema = z.enum([
  'CREATED',
  'IN_TRIAGE',
  'KILLED_AT_TRIAGE',
  'IN_MARKET_FIT',
  'KILLED_AT_MARKET_FIT',
  'IN_ECONOMICS',
  'KILLED_AT_ECONOMICS',
  'IN_VALIDATION',
  'KILLED_AT_VALIDATION',
  'PENDING_HANDOFF',
  'AWAITING_APPROVAL',
  'APPROVED_FOR_BUILD',
  'IN_BUILD',
  'ARCHIVED',
]);
export type LifecycleStatus = z.infer<typeof LifecycleStatusSchema>;

// ============================================================================
// GATE ENUMS
// ============================================================================

export const GateSchema = z.enum([
  'G0_INTAKE',
  'G1_TRIAGE',
  'G2_MARKET_FIT',
  'G3_ECONOMICS',
  'G4_VALIDATION',
  'G5_HANDOFF',
]);
export type Gate = z.infer<typeof GateSchema>;

export const GateDecisionSchema = z.enum([
  'GO',
  'REVISE',
  'KILL',
  'OVERRIDE_GO',
  'OVERRIDE_KILL',
]);
export type GateDecision = z.infer<typeof GateDecisionSchema>;

export const KillReasonSchema = z.enum([
  'LEGAL_RED_FLAG',
  'NO_MONETIZATION',
  'NO_DISTRIBUTION_PATH',
  'MARGIN_BELOW_MIN',
  'TIME_TO_CASHFLOW_TOO_LONG',
  'CUSTOM',
]);
export type KillReason = z.infer<typeof KillReasonSchema>;

export const GateRunStatusSchema = z.enum([
  'PENDING',
  'RUNNING',
  'COMPLETED',
  'FAILED_RETRY',
  'FAILED_PERMANENT',
]);
export type GateRunStatus = z.infer<typeof GateRunStatusSchema>;

// ============================================================================
// AGENT & ANALYSIS ENUMS
// ============================================================================

export const AgentTypeSchema = z.enum([
  'MARKET_LIGHT',
  'RISK',
  'MARKET_DEEP',
  'COMPETITOR',
  'ECONOMICS',
  'PRICING',
  'EXPERIMENT',
  'MVP_SCOPE',
  'BUILD_DECISION',
  'ORCHESTRATOR',
]);
export type AgentType = z.infer<typeof AgentTypeSchema>;

export const EvidenceTypeSchema = z.enum([
  'DESK_RESEARCH',
  'COMPETITOR_SCAN',
  'UNIT_ECON_MODEL',
  'PRICING_HYPOTHESIS',
  'EXPERT_INTERVIEW',
  'USER_INTERVIEW',
  'SURVEY',
  'LANDING_PAGE_TEST',
  'WAITLIST',
  'EXPERIMENT_PLAN',
  'MVP_SCOPE',
  'AD_CLICK',
  'PREORDER',
  'PAID_PILOT',
  'REVENUE',
  'RETENTION_DATA',
]);
export type EvidenceType = z.infer<typeof EvidenceTypeSchema>;

export const EvidenceLevelSchema = z.enum([
  'LEVEL_0',
  'LEVEL_1',
  'LEVEL_2',
  'LEVEL_3',
  'LEVEL_4',
  'LEVEL_5',
]);
export type EvidenceLevel = z.infer<typeof EvidenceLevelSchema>;

// Helper to convert evidence level to numeric value (0-5)
export function evidenceLevelToNumber(level: EvidenceLevel): number {
  return parseInt(level.split('_')[1], 10);
}

// Helper to convert numeric value to evidence level
export function numberToEvidenceLevel(num: number): EvidenceLevel {
  if (num < 0 || num > 5) {
    throw new Error(`Invalid evidence level number: ${num}. Must be 0-5.`);
  }
  return `LEVEL_${num}` as EvidenceLevel;
}

// ============================================================================
// TASK & MILESTONE ENUMS
// ============================================================================

export const TaskPrioritySchema = z.enum([
  'P0',
  'P1',
  'P2',
  'P3',
]);
export type TaskPriority = z.infer<typeof TaskPrioritySchema>;

export const TaskStatusSchema = z.enum([
  'TODO',
  'IN_PROGRESS',
  'BLOCKED',
  'DONE',
  'CANCELLED',
]);
export type TaskStatus = z.infer<typeof TaskStatusSchema>;

export const MilestoneStatusSchema = z.enum([
  'PLANNED',
  'IN_PROGRESS',
  'COMPLETED',
  'MISSED',
  'CANCELLED',
]);
export type MilestoneStatus = z.infer<typeof MilestoneStatusSchema>;

// ============================================================================
// SYNC & INTEGRATION ENUMS
// ============================================================================

export const OutboxOperationSchema = z.enum([
  'UPSERT_EVENT',
  'CANCEL_EVENT',
  'REBUILD_ALL',
]);
export type OutboxOperation = z.infer<typeof OutboxOperationSchema>;

export const OutboxStatusSchema = z.enum([
  'PENDING',
  'PROCESSING',
  'COMPLETED',
  'FAILED',
  'DEAD_LETTER',
]);
export type OutboxStatus = z.infer<typeof OutboxStatusSchema>;

export const CalendarEventTypeSchema = z.enum([
  'GATE_REVIEW',
  'BLOCKER_DEADLINE',
  'MILESTONE',
  'PROJECT_REVIEW',
]);
export type CalendarEventType = z.infer<typeof CalendarEventTypeSchema>;

export const ConnectionStatusSchema = z.enum([
  'ACTIVE',
  'INVALID',
  'ERROR',
]);
export type ConnectionStatus = z.infer<typeof ConnectionStatusSchema>;

// ============================================================================
// AUDIT & CONFIG ENUMS
// ============================================================================

export const AuditActionSchema = z.enum([
  'GATE_RUN',
  'DECISION_OVERRIDE',
  'CONFIG_CHANGE',
  'PROMPT_CHANGE',
  'TASK_CREATE',
  'TASK_UPDATE',
  'EVIDENCE_ADD',
  'APPROVAL_GRANT',
  'WORKSPACE_CREATE',
  'MEMBER_ADD',
  'MEMBER_REMOVE',
]);
export type AuditAction = z.infer<typeof AuditActionSchema>;

export const CriticalityLevelSchema = z.enum([
  'LOW',
  'MEDIUM',
  'HIGH',
  'CRITICAL',
]);
export type CriticalityLevel = z.infer<typeof CriticalityLevelSchema>;

export const RiskImpactSchema = z.enum([
  'LOW',
  'MEDIUM',
  'HIGH',
  'CRITICAL',
]);
export type RiskImpact = z.infer<typeof RiskImpactSchema>;

export const RiskLikelihoodSchema = z.enum([
  'LOW',
  'MEDIUM',
  'HIGH',
  'VERY_HIGH',
]);
export type RiskLikelihood = z.infer<typeof RiskLikelihoodSchema>;

// ============================================================================
// VALIDATION HELPERS
// ============================================================================

/**
 * Validates that a gate decision is appropriate for the given gate
 */
export function validateGateDecision(gate: Gate, decision: GateDecision): boolean {
  // All gates can have GO, REVISE, KILL
  const validDecisions: GateDecision[] = ['GO', 'REVISE', 'KILL', 'OVERRIDE_GO', 'OVERRIDE_KILL'];
  return validDecisions.includes(decision);
}

/**
 * Determines if a decision is a terminal state (idea stops progressing)
 */
export function isTerminalDecision(decision: GateDecision): boolean {
  return decision === 'KILL' || decision === 'OVERRIDE_KILL';
}

/**
 * Determines if a decision allows progression to next gate
 */
export function canProgressToNextGate(decision: GateDecision): boolean {
  return decision === 'GO' || decision === 'OVERRIDE_GO';
}

/**
 * Gets the next gate in sequence, or null if no next gate
 */
export function getNextGate(currentGate: Gate): Gate | null {
  const gates: Gate[] = [
    'G0_INTAKE',
    'G1_TRIAGE',
    'G2_MARKET_FIT',
    'G3_ECONOMICS',
    'G4_VALIDATION',
    'G5_HANDOFF',
  ];

  const currentIndex = gates.indexOf(currentGate);
  if (currentIndex === -1 || currentIndex === gates.length - 1) {
    return null;
  }

  return gates[currentIndex + 1];
}

/**
 * Maps lifecycle status to current gate
 */
export function lifecycleStatusToGate(status: LifecycleStatus): Gate | null {
  const mapping: Partial<Record<LifecycleStatus, Gate>> = {
    'CREATED': 'G0_INTAKE',
    'IN_TRIAGE': 'G1_TRIAGE',
    'KILLED_AT_TRIAGE': 'G1_TRIAGE',
    'IN_MARKET_FIT': 'G2_MARKET_FIT',
    'KILLED_AT_MARKET_FIT': 'G2_MARKET_FIT',
    'IN_ECONOMICS': 'G3_ECONOMICS',
    'KILLED_AT_ECONOMICS': 'G3_ECONOMICS',
    'IN_VALIDATION': 'G4_VALIDATION',
    'KILLED_AT_VALIDATION': 'G4_VALIDATION',
    'PENDING_HANDOFF': 'G5_HANDOFF',
    'AWAITING_APPROVAL': 'G5_HANDOFF',
  };

  return mapping[status] ?? null;
}

/**
 * Checks if a lifecycle status represents a killed/terminated idea
 */
export function isKilledStatus(status: LifecycleStatus): boolean {
  return status.startsWith('KILLED_');
}

/**
 * Gets minimum evidence level required for a gate (from default config)
 */
export function getMinEvidenceLevelForGate(gate: Gate): number {
  const defaults: Record<Gate, number> = {
    'G0_INTAKE': 0,
    'G1_TRIAGE': 0,
    'G2_MARKET_FIT': 1,  // Desk research required
    'G3_ECONOMICS': 1,   // Desk research required
    'G4_VALIDATION': 3,  // Behavioral signals required
    'G5_HANDOFF': 3,     // Behavioral signals required
  };

  return defaults[gate] ?? 0;
}
