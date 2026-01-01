/**
 * Zod schemas for Drive intake JSON
 * Feature: F016
 *
 * IMPORTANT: These schemas define the structure of idea intake data
 * ingested from Google Drive files.
 */

import { z } from 'zod';
import { TaskPrioritySchema } from './enums';

// ============================================================================
// CONSTRAINTS SCHEMA
// ============================================================================

export const ConstraintsSchema = z.object({
  // Budget constraints
  max_investment_usd: z.number().nonnegative().optional(),
  max_monthly_burn_usd: z.number().nonnegative().optional(),

  // Time constraints
  max_time_to_mvp_weeks: z.number().int().nonnegative().optional(),
  max_time_to_revenue_weeks: z.number().int().nonnegative().optional(),
  hard_deadline: z.string().datetime().optional(),

  // Resource constraints
  available_hours_per_week: z.number().nonnegative().optional(),
  team_size: z.number().int().nonnegative().optional(),
  requires_external_resources: z.boolean().optional(),

  // Business constraints
  min_margin_percent: z.number().min(0).max(100).optional(),
  target_revenue_monthly_usd: z.number().nonnegative().optional(),
  break_even_months: z.number().int().nonnegative().optional(),

  // Technical constraints
  tech_stack_constraints: z.array(z.string()).optional(),
  platform_constraints: z.array(z.string()).optional(),
  integration_requirements: z.array(z.string()).optional(),

  // Legal/Compliance constraints
  legal_jurisdictions: z.array(z.string()).optional(),
  compliance_requirements: z.array(z.string()).optional(),
  requires_licensing: z.boolean().optional(),
});

export type Constraints = z.infer<typeof ConstraintsSchema>;

// ============================================================================
// TARGET CUSTOMER SCHEMA
// ============================================================================

export const TargetCustomerSchema = z.object({
  segment: z.string().min(1, 'Customer segment is required'),
  description: z.string().optional(),
  pain_points: z.array(z.string()).optional(),
  jobs_to_be_done: z.array(z.string()).optional(),
  alternatives_used: z.array(z.string()).optional(),
  budget_range: z.string().optional(),
  decision_makers: z.array(z.string()).optional(),
  geographic_focus: z.array(z.string()).optional(),
});

export type TargetCustomer = z.infer<typeof TargetCustomerSchema>;

// ============================================================================
// MONETIZATION SCHEMA
// ============================================================================

export const MonetizationSchema = z.object({
  model: z.enum([
    'SUBSCRIPTION',
    'ONE_TIME_PURCHASE',
    'FREEMIUM',
    'USAGE_BASED',
    'MARKETPLACE_FEE',
    'ADVERTISING',
    'LICENSING',
    'CONSULTING',
    'HYBRID',
    'OTHER',
  ]),
  description: z.string().optional(),
  price_point_low: z.number().nonnegative().optional(),
  price_point_high: z.number().nonnegative().optional(),
  currency: z.string().default('USD'),
  billing_frequency: z.enum(['ONCE', 'MONTHLY', 'YEARLY', 'USAGE']).optional(),
  estimated_ltv_usd: z.number().nonnegative().optional(),
  estimated_cac_usd: z.number().nonnegative().optional(),
});

export type Monetization = z.infer<typeof MonetizationSchema>;

// ============================================================================
// DISTRIBUTION SCHEMA
// ============================================================================

export const DistributionSchema = z.object({
  channels: z.array(z.enum([
    'DIRECT_SALES',
    'ONLINE_STORE',
    'APP_STORE',
    'MARKETPLACE',
    'AFFILIATE',
    'PARTNERSHIPS',
    'CONTENT_MARKETING',
    'SEO',
    'PAID_ADS',
    'SOCIAL_MEDIA',
    'EMAIL',
    'REFERRAL',
    'OTHER',
  ])),
  primary_channel: z.string().optional(),
  existing_audience: z.boolean().optional(),
  audience_size: z.number().int().nonnegative().optional(),
  distribution_advantages: z.array(z.string()).optional(),
});

export type Distribution = z.infer<typeof DistributionSchema>;

// ============================================================================
// COMPETITOR SCHEMA
// ============================================================================

export const CompetitorSchema = z.object({
  name: z.string().min(1),
  url: z.string().url().optional(),
  description: z.string().optional(),
  pricing: z.string().optional(),
  strengths: z.array(z.string()).optional(),
  weaknesses: z.array(z.string()).optional(),
  market_share_estimate: z.string().optional(),
});

export type Competitor = z.infer<typeof CompetitorSchema>;

// ============================================================================
// RISK SCHEMA
// ============================================================================

export const IntakeRiskSchema = z.object({
  category: z.enum([
    'TECHNICAL',
    'MARKET',
    'FINANCIAL',
    'LEGAL',
    'OPERATIONAL',
    'COMPETITIVE',
    'REGULATORY',
    'OTHER',
  ]),
  description: z.string().min(1),
  severity: z.enum(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']).optional(),
  mitigation: z.string().optional(),
});

export type IntakeRisk = z.infer<typeof IntakeRiskSchema>;

// ============================================================================
// IDEA INTAKE SCHEMA (Main Schema)
// ============================================================================

export const IdeaIntakeSchema = z.object({
  // Core identification
  title: z.string().min(1, 'Title is required').max(200),
  tagline: z.string().max(300).optional(),
  description: z.string().min(1, 'Description is required'),

  // Problem/Solution
  problem_statement: z.string().min(1, 'Problem statement is required'),
  proposed_solution: z.string().min(1, 'Proposed solution is required'),
  unique_value_proposition: z.string().optional(),

  // Market context
  target_customers: z.array(TargetCustomerSchema).min(1, 'At least one target customer required'),
  market_size_estimate: z.string().optional(),
  tam_usd: z.number().nonnegative().optional(), // Total Addressable Market
  sam_usd: z.number().nonnegative().optional(), // Serviceable Addressable Market
  som_usd: z.number().nonnegative().optional(), // Serviceable Obtainable Market

  // Competition
  competitors: z.array(CompetitorSchema).optional(),
  competitive_advantages: z.array(z.string()).optional(),

  // Business model
  monetization: MonetizationSchema.optional(),
  distribution: DistributionSchema.optional(),

  // Constraints
  constraints: ConstraintsSchema.optional(),

  // Known risks
  known_risks: z.array(IntakeRiskSchema).optional(),

  // Assumptions
  key_assumptions: z.array(z.string()).optional(),
  must_validate: z.array(z.string()).optional(),

  // Technical info
  tech_stack_preferred: z.array(z.string()).optional(),
  mvp_scope_ideas: z.array(z.string()).optional(),
  existing_assets: z.array(z.string()).optional(),

  // Priority
  priority: TaskPrioritySchema.optional(),

  // Metadata
  source: z.enum(['DRIVE', 'MANUAL', 'API', 'IMPORT']).optional(),
  author: z.string().optional(),
  created_at: z.string().datetime().optional(),
  tags: z.array(z.string()).optional(),
  notes: z.string().optional(),
});

export type IdeaIntake = z.infer<typeof IdeaIntakeSchema>;

// ============================================================================
// PARTIAL INTAKE SCHEMA (for updates)
// ============================================================================

export const PartialIdeaIntakeSchema = IdeaIntakeSchema.partial();
export type PartialIdeaIntake = z.infer<typeof PartialIdeaIntakeSchema>;

// ============================================================================
// VALIDATION HELPERS
// ============================================================================

/**
 * Validates an intake object and returns typed result
 */
export function validateIntake(data: unknown): {
  success: boolean;
  data?: IdeaIntake;
  errors?: z.ZodError;
} {
  const result = IdeaIntakeSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, errors: result.error };
}

/**
 * Checks if intake has monetization defined
 */
export function hasMonetization(intake: IdeaIntake): boolean {
  return !!intake.monetization;
}

/**
 * Checks if intake has distribution path defined
 */
export function hasDistributionPath(intake: IdeaIntake): boolean {
  return !!intake.distribution && intake.distribution.channels.length > 0;
}

/**
 * Checks if intake has legal red flags in known risks
 */
export function hasLegalRedFlags(intake: IdeaIntake): boolean {
  if (!intake.known_risks) return false;
  return intake.known_risks.some(
    (risk) =>
      (risk.category === 'LEGAL' || risk.category === 'REGULATORY') &&
      (risk.severity === 'CRITICAL' || risk.severity === 'HIGH')
  );
}

/**
 * Calculates time to cashflow constraint in weeks
 */
export function getTimeToCashflowWeeks(intake: IdeaIntake): number | null {
  if (!intake.constraints) return null;
  return intake.constraints.max_time_to_revenue_weeks ?? null;
}

/**
 * Checks if margin constraint is met
 */
export function checkMarginConstraint(
  intake: IdeaIntake,
  actualMarginPercent: number
): boolean {
  if (!intake.constraints?.min_margin_percent) return true;
  return actualMarginPercent >= intake.constraints.min_margin_percent;
}
