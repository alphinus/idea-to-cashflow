/**
 * Zod schemas for sync_outbox and calendar sync payloads
 * Feature: F040
 *
 * These schemas define the structure of outbox items and their payloads
 * for the calendar sync worker.
 */

import { z } from 'zod';
import {
  OutboxOperationSchema,
  OutboxStatusSchema,
  CalendarEventTypeSchema,
} from './enums';

// ============================================================================
// CALENDAR EVENT PAYLOAD SCHEMA
// ============================================================================

/**
 * Schema for calendar event payload (Google Calendar API format)
 */
export const CalendarEventPayloadSchema = z.object({
  title: z.string().min(1).max(500),
  description: z.string().optional(),
  start: z.string().datetime(), // ISO 8601 datetime
  end: z.string().datetime(),   // ISO 8601 datetime
  isAllDay: z.boolean().default(false),
  recurrence: z.array(z.string()).optional(), // RRULE strings
  location: z.string().optional(),
  colorId: z.string().optional(), // Google Calendar color ID
});
export type CalendarEventPayload = z.infer<typeof CalendarEventPayloadSchema>;

// ============================================================================
// OUTBOX PAYLOAD SCHEMAS (POLYMORPHIC)
// ============================================================================

/**
 * Base payload with common fields
 */
const BaseOutboxPayloadSchema = z.object({
  workspaceId: z.string().uuid(),
  calendarId: z.string().min(1), // Google Calendar ID
});

/**
 * UPSERT_EVENT payload schema
 */
export const UpsertEventPayloadSchema = BaseOutboxPayloadSchema.extend({
  operation: z.literal('UPSERT_EVENT'),
  sourceType: z.enum(['task', 'milestone', 'gate_run', 'project_review']),
  sourceId: z.string().uuid(),
  eventType: CalendarEventTypeSchema,
  event: CalendarEventPayloadSchema,
});
export type UpsertEventPayload = z.infer<typeof UpsertEventPayloadSchema>;

/**
 * CANCEL_EVENT payload schema
 */
export const CancelEventPayloadSchema = BaseOutboxPayloadSchema.extend({
  operation: z.literal('CANCEL_EVENT'),
  sourceType: z.enum(['task', 'milestone', 'gate_run', 'project_review']),
  sourceId: z.string().uuid(),
  googleEventId: z.string().optional(), // If known from binding
});
export type CancelEventPayload = z.infer<typeof CancelEventPayloadSchema>;

/**
 * REBUILD_ALL payload schema
 */
export const RebuildAllPayloadSchema = BaseOutboxPayloadSchema.extend({
  operation: z.literal('REBUILD_ALL'),
  // No additional fields needed - rebuilds all events for workspace
});
export type RebuildAllPayload = z.infer<typeof RebuildAllPayloadSchema>;

/**
 * Discriminated union of all outbox payload types
 */
export const OutboxPayloadSchema = z.discriminatedUnion('operation', [
  UpsertEventPayloadSchema,
  CancelEventPayloadSchema,
  RebuildAllPayloadSchema,
]);
export type OutboxPayload = z.infer<typeof OutboxPayloadSchema>;

// ============================================================================
// SYNC_OUTBOX TABLE SCHEMA
// ============================================================================

/**
 * Schema for sync_outbox database row
 */
export const SyncOutboxSchema = z.object({
  id: z.string().uuid(),
  workspaceId: z.string().uuid(),
  operation: OutboxOperationSchema,
  payload: OutboxPayloadSchema,
  status: OutboxStatusSchema,
  attempts: z.number().int().min(0),
  maxAttempts: z.number().int().min(1).default(5),
  nextAttemptAt: z.string().datetime(),
  lastError: z.string().nullable().optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  processedAt: z.string().datetime().nullable().optional(),
});
export type SyncOutbox = z.infer<typeof SyncOutboxSchema>;

/**
 * Schema for creating a new outbox item
 */
export const CreateSyncOutboxSchema = z.object({
  workspaceId: z.string().uuid(),
  operation: OutboxOperationSchema,
  payload: OutboxPayloadSchema,
  maxAttempts: z.number().int().min(1).default(5).optional(),
});
export type CreateSyncOutbox = z.infer<typeof CreateSyncOutboxSchema>;

// ============================================================================
// CALENDAR_EVENT_BINDINGS TABLE SCHEMA
// ============================================================================

/**
 * Schema for calendar_event_bindings database row
 */
export const CalendarEventBindingSchema = z.object({
  id: z.string().uuid(),
  workspaceId: z.string().uuid(),
  googleEventId: z.string().min(1),
  calendarId: z.string().min(1),
  sourceType: z.enum(['task', 'milestone', 'gate_run', 'project_review']),
  sourceId: z.string().uuid(),
  eventType: CalendarEventTypeSchema,
  eventTitle: z.string().nullable().optional(),
  eventStart: z.string().datetime().nullable().optional(),
  eventEnd: z.string().datetime().nullable().optional(),
  lastSyncedAt: z.string().datetime(),
  syncVersion: z.number().int().min(1).default(1),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});
export type CalendarEventBinding = z.infer<typeof CalendarEventBindingSchema>;

/**
 * Schema for creating/upserting a calendar event binding
 */
export const UpsertCalendarEventBindingSchema = z.object({
  workspaceId: z.string().uuid(),
  googleEventId: z.string().min(1),
  calendarId: z.string().min(1),
  sourceType: z.enum(['task', 'milestone', 'gate_run', 'project_review']),
  sourceId: z.string().uuid(),
  eventType: CalendarEventTypeSchema,
  eventTitle: z.string().optional(),
  eventStart: z.string().datetime().optional(),
  eventEnd: z.string().datetime().optional(),
});
export type UpsertCalendarEventBinding = z.infer<typeof UpsertCalendarEventBindingSchema>;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Calculate next retry attempt timestamp with exponential backoff
 *
 * @param attemptNumber - Current attempt number (0-based)
 * @param baseDelayMs - Base delay in milliseconds (default: 1000ms = 1s)
 * @param maxDelayMs - Maximum delay in milliseconds (default: 3600000ms = 1h)
 * @returns ISO 8601 datetime string for next attempt
 */
export function calculateNextAttempt(
  attemptNumber: number,
  baseDelayMs: number = 1000,
  maxDelayMs: number = 3600000
): string {
  // Exponential backoff: base * 2^attempt
  // Attempts: 0 -> 1s, 1 -> 2s, 2 -> 4s, 3 -> 8s, 4 -> 16s, etc.
  const delayMs = Math.min(baseDelayMs * Math.pow(2, attemptNumber), maxDelayMs);

  const nextAttempt = new Date(Date.now() + delayMs);
  return nextAttempt.toISOString();
}

/**
 * Check if outbox item should be moved to dead letter
 *
 * @param item - Sync outbox item
 * @returns true if item should be dead lettered
 */
export function shouldDeadLetter(item: SyncOutbox): boolean {
  return item.attempts >= item.maxAttempts && item.status === 'FAILED';
}

/**
 * Validate outbox payload matches operation type
 *
 * @param operation - Outbox operation
 * @param payload - Payload to validate
 * @returns true if valid
 */
export function validateOutboxPayload(
  operation: z.infer<typeof OutboxOperationSchema>,
  payload: unknown
): boolean {
  try {
    OutboxPayloadSchema.parse(payload);
    return true;
  } catch {
    return false;
  }
}
