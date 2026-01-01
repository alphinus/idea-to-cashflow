/**
 * Zod schemas for workspace and membership entities
 * Feature: F002
 *
 * IMPORTANT: These schemas MUST stay in sync with database table definitions
 * in supabase/migrations/20250101000001_create_workspaces_memberships.sql
 */

import { z } from 'zod';
import { WorkspaceRoleSchema } from './enums';

// ============================================================================
// WORKSPACE SCHEMA
// ============================================================================

export const WorkspaceSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1).max(100),
  slug: z.string().min(1).max(50).regex(/^[a-z0-9-]+$/, 'Slug must be lowercase alphanumeric with hyphens'),
  timezone: z.string().default('Europe/Zurich'),

  // Google Drive integration
  drive_folder_inbox_id: z.string().nullable().optional(),
  drive_folder_processed_id: z.string().nullable().optional(),
  drive_folder_error_id: z.string().nullable().optional(),

  // Google Calendar integration
  calendar_id: z.string().nullable().optional(),
  weekly_review_rrule: z.string().nullable().default('RRULE:FREQ=WEEKLY;BYDAY=MO;BYHOUR=9;BYMINUTE=0'),

  // Budget controls
  budget_daily_usd: z.number().nonnegative().default(10.00),
  budget_monthly_usd: z.number().nonnegative().default(200.00),

  // Timestamps
  created_at: z.string().datetime().or(z.date()),
  updated_at: z.string().datetime().or(z.date()),
});

export type Workspace = z.infer<typeof WorkspaceSchema>;

// Schema for creating a new workspace
export const CreateWorkspaceSchema = z.object({
  name: z.string().min(1).max(100),
  slug: z.string().min(1).max(50).regex(/^[a-z0-9-]+$/, 'Slug must be lowercase alphanumeric with hyphens'),
  timezone: z.string().optional().default('Europe/Zurich'),
  budget_daily_usd: z.number().nonnegative().optional().default(10.00),
  budget_monthly_usd: z.number().nonnegative().optional().default(200.00),
});

export type CreateWorkspace = z.infer<typeof CreateWorkspaceSchema>;

// Schema for updating a workspace
export const UpdateWorkspaceSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  timezone: z.string().optional(),
  drive_folder_inbox_id: z.string().nullable().optional(),
  drive_folder_processed_id: z.string().nullable().optional(),
  drive_folder_error_id: z.string().nullable().optional(),
  calendar_id: z.string().nullable().optional(),
  weekly_review_rrule: z.string().nullable().optional(),
  budget_daily_usd: z.number().nonnegative().optional(),
  budget_monthly_usd: z.number().nonnegative().optional(),
});

export type UpdateWorkspace = z.infer<typeof UpdateWorkspaceSchema>;

// ============================================================================
// MEMBERSHIP SCHEMA
// ============================================================================

export const MembershipSchema = z.object({
  id: z.string().uuid(),
  workspace_id: z.string().uuid(),
  user_id: z.string().uuid(),
  role: WorkspaceRoleSchema,
  created_at: z.string().datetime().or(z.date()),
  updated_at: z.string().datetime().or(z.date()),
});

export type Membership = z.infer<typeof MembershipSchema>;

// Schema for creating a new membership
export const CreateMembershipSchema = z.object({
  workspace_id: z.string().uuid(),
  user_id: z.string().uuid(),
  role: WorkspaceRoleSchema.optional().default('VIEWER'),
});

export type CreateMembership = z.infer<typeof CreateMembershipSchema>;

// Schema for updating a membership (only role can be updated)
export const UpdateMembershipSchema = z.object({
  role: WorkspaceRoleSchema,
});

export type UpdateMembership = z.infer<typeof UpdateMembershipSchema>;

// ============================================================================
// EXTENDED TYPES WITH RELATIONS
// ============================================================================

// Workspace with member count
export const WorkspaceWithStatsSchema = WorkspaceSchema.extend({
  member_count: z.number().int().nonnegative(),
});

export type WorkspaceWithStats = z.infer<typeof WorkspaceWithStatsSchema>;

// Membership with user info (for display)
export const MembershipWithUserSchema = MembershipSchema.extend({
  user: z.object({
    id: z.string().uuid(),
    email: z.string().email(),
    full_name: z.string().nullable().optional(),
    avatar_url: z.string().url().nullable().optional(),
  }),
});

export type MembershipWithUser = z.infer<typeof MembershipWithUserSchema>;

// ============================================================================
// VALIDATION HELPERS
// ============================================================================

/**
 * Validates that a slug is unique format (lowercase, alphanumeric, hyphens)
 */
export function isValidSlug(slug: string): boolean {
  return /^[a-z0-9-]+$/.test(slug) && slug.length >= 1 && slug.length <= 50;
}

/**
 * Generates a slug from a workspace name
 */
export function generateSlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .substring(0, 50);
}

/**
 * Validates timezone string (basic check)
 */
export function isValidTimezone(tz: string): boolean {
  try {
    Intl.DateTimeFormat(undefined, { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}
