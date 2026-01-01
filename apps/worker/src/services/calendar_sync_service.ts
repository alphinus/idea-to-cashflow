/**
 * Calendar Sync Worker Service
 * Feature: F040
 *
 * Drains sync_outbox table and syncs events to Google Calendar with:
 * - Advisory locks for concurrency control
 * - Exponential backoff retry logic
 * - Dead letter queue after max attempts
 * - OAuth error handling
 */

import { createClient } from '@supabase/supabase-js';
import { google, calendar_v3 } from 'googleapis';
import {
  SyncOutbox,
  OutboxPayload,
  UpsertEventPayload,
  CancelEventPayload,
  RebuildAllPayload,
  calculateNextAttempt,
  shouldDeadLetter,
  OutboxPayloadSchema,
} from '@shared/schemas/sync';
import { OutboxStatus } from '@shared/schemas/enums';

// ============================================================================
// TYPES & INTERFACES
// ============================================================================

interface CalendarSyncConfig {
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  googleClientId: string;
  googleClientSecret: string;
  batchSize: number;
  pollIntervalMs: number;
  maxRetries: number;
}

interface GoogleConnection {
  refreshToken: string;
  calendarId: string;
  isValid: boolean;
}

interface ProcessingResult {
  success: boolean;
  error?: string;
  shouldRetry: boolean;
  isOAuthError: boolean;
}

// ============================================================================
// CALENDAR SYNC WORKER CLASS
// ============================================================================

export class CalendarSyncWorker {
  private supabase: ReturnType<typeof createClient>;
  private config: CalendarSyncConfig;
  private isRunning: boolean = false;
  private pollTimer: NodeJS.Timeout | null = null;

  constructor(config: CalendarSyncConfig) {
    this.config = config;
    this.supabase = createClient(
      config.supabaseUrl,
      config.supabaseServiceRoleKey
    );
  }

  // ==========================================================================
  // MAIN WORKER LOOP
  // ==========================================================================

  /**
   * Start the worker polling loop
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      console.warn('[CalendarSyncWorker] Already running');
      return;
    }

    this.isRunning = true;
    console.log('[CalendarSyncWorker] Starting worker...');

    // Run initial drain
    await this.drainOutbox();

    // Setup polling interval
    this.pollTimer = setInterval(async () => {
      await this.drainOutbox();
    }, this.config.pollIntervalMs);

    console.log(
      `[CalendarSyncWorker] Worker started (polling every ${this.config.pollIntervalMs}ms)`
    );
  }

  /**
   * Stop the worker polling loop
   */
  async stop(): Promise<void> {
    this.isRunning = false;

    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }

    console.log('[CalendarSyncWorker] Worker stopped');
  }

  // ==========================================================================
  // OUTBOX DRAINING
  // ==========================================================================

  /**
   * Drain pending/failed outbox items with advisory locks
   */
  private async drainOutbox(): Promise<void> {
    try {
      // Fetch pending/failed items ready for processing
      const { data: items, error } = await this.supabase
        .from('sync_outbox')
        .select('*')
        .in('status', ['PENDING', 'FAILED'])
        .lte('next_attempt_at', new Date().toISOString())
        .order('created_at', { ascending: true })
        .limit(this.config.batchSize);

      if (error) {
        console.error('[CalendarSyncWorker] Error fetching outbox items:', error);
        return;
      }

      if (!items || items.length === 0) {
        // No items to process
        return;
      }

      console.log(
        `[CalendarSyncWorker] Processing ${items.length} outbox items...`
      );

      // Process each item with advisory lock
      for (const item of items) {
        await this.processOutboxItem(item as SyncOutbox);
      }
    } catch (err) {
      console.error('[CalendarSyncWorker] Error in drainOutbox:', err);
    }
  }

  /**
   * Process a single outbox item with advisory lock
   */
  private async processOutboxItem(item: SyncOutbox): Promise<void> {
    // Try to acquire advisory lock
    const { data: lockAcquired, error: lockError } = await this.supabase.rpc(
      'try_lock_outbox_item',
      { outbox_id: item.id }
    );

    if (lockError) {
      console.error(
        `[CalendarSyncWorker] Error acquiring lock for ${item.id}:`,
        lockError
      );
      return;
    }

    if (!lockAcquired) {
      // Another worker has this item locked, skip
      console.log(
        `[CalendarSyncWorker] Item ${item.id} locked by another worker, skipping`
      );
      return;
    }

    try {
      // Update status to PROCESSING
      await this.updateOutboxStatus(item.id, 'PROCESSING');

      // Validate payload
      const payloadValidation = OutboxPayloadSchema.safeParse(item.payload);
      if (!payloadValidation.success) {
        throw new Error(
          `Invalid payload: ${payloadValidation.error.message}`
        );
      }

      const payload = payloadValidation.data;

      // Process based on operation type
      let result: ProcessingResult;
      switch (payload.operation) {
        case 'UPSERT_EVENT':
          result = await this.processUpsertEvent(payload);
          break;
        case 'CANCEL_EVENT':
          result = await this.processCancelEvent(payload);
          break;
        case 'REBUILD_ALL':
          result = await this.processRebuildAll(payload);
          break;
        default:
          throw new Error(`Unknown operation: ${(payload as any).operation}`);
      }

      // Handle result
      if (result.success) {
        // Mark as completed
        await this.updateOutboxStatus(item.id, 'COMPLETED', null, true);
        console.log(`[CalendarSyncWorker] Item ${item.id} completed successfully`);
      } else {
        // Handle failure
        await this.handleFailure(item, result);
      }
    } catch (err) {
      // Unexpected error - treat as retriable unless it's critical
      const error = err as Error;
      console.error(
        `[CalendarSyncWorker] Error processing item ${item.id}:`,
        error
      );

      await this.handleFailure(item, {
        success: false,
        error: error.message,
        shouldRetry: true,
        isOAuthError: false,
      });
    } finally {
      // Always release lock
      await this.supabase.rpc('unlock_outbox_item', { outbox_id: item.id });
    }
  }

  // ==========================================================================
  // OPERATION HANDLERS
  // ==========================================================================

  /**
   * Process UPSERT_EVENT operation
   */
  private async processUpsertEvent(
    payload: UpsertEventPayload
  ): Promise<ProcessingResult> {
    try {
      // Get Google connection for workspace
      const connection = await this.getGoogleConnection(payload.workspaceId);
      if (!connection.isValid) {
        return {
          success: false,
          error: 'Google connection invalid - OAuth token expired or revoked',
          shouldRetry: false,
          isOAuthError: true,
        };
      }

      // Get Calendar API client
      const calendar = await this.getCalendarClient(connection.refreshToken);

      // Check if binding exists
      const { data: binding } = await this.supabase
        .from('calendar_event_bindings')
        .select('*')
        .eq('workspace_id', payload.workspaceId)
        .eq('source_type', payload.sourceType)
        .eq('source_id', payload.sourceId)
        .single();

      let googleEventId: string;

      if (binding) {
        // Update existing event
        googleEventId = binding.google_event_id;
        await calendar.events.update({
          calendarId: payload.calendarId,
          eventId: googleEventId,
          requestBody: this.buildGoogleEvent(payload.event),
        });

        console.log(
          `[CalendarSyncWorker] Updated event ${googleEventId} for ${payload.sourceType}:${payload.sourceId}`
        );
      } else {
        // Create new event
        const response = await calendar.events.insert({
          calendarId: payload.calendarId,
          requestBody: this.buildGoogleEvent(payload.event),
        });

        googleEventId = response.data.id!;

        console.log(
          `[CalendarSyncWorker] Created event ${googleEventId} for ${payload.sourceType}:${payload.sourceId}`
        );
      }

      // Upsert binding
      await this.supabase
        .from('calendar_event_bindings')
        .upsert({
          workspace_id: payload.workspaceId,
          google_event_id: googleEventId,
          calendar_id: payload.calendarId,
          source_type: payload.sourceType,
          source_id: payload.sourceId,
          event_type: payload.eventType,
          event_title: payload.event.title,
          event_start: payload.event.start,
          event_end: payload.event.end,
        });

      return { success: true, shouldRetry: false, isOAuthError: false };
    } catch (err) {
      return this.handleGoogleApiError(err as Error);
    }
  }

  /**
   * Process CANCEL_EVENT operation
   */
  private async processCancelEvent(
    payload: CancelEventPayload
  ): Promise<ProcessingResult> {
    try {
      // Get Google connection for workspace
      const connection = await this.getGoogleConnection(payload.workspaceId);
      if (!connection.isValid) {
        return {
          success: false,
          error: 'Google connection invalid - OAuth token expired or revoked',
          shouldRetry: false,
          isOAuthError: true,
        };
      }

      // Get binding
      const { data: binding } = await this.supabase
        .from('calendar_event_bindings')
        .select('*')
        .eq('workspace_id', payload.workspaceId)
        .eq('source_type', payload.sourceType)
        .eq('source_id', payload.sourceId)
        .single();

      if (!binding) {
        // No binding exists, nothing to cancel - consider success
        console.log(
          `[CalendarSyncWorker] No binding found for ${payload.sourceType}:${payload.sourceId}, skipping cancel`
        );
        return { success: true, shouldRetry: false, isOAuthError: false };
      }

      // Get Calendar API client
      const calendar = await this.getCalendarClient(connection.refreshToken);

      // Cancel event
      await calendar.events.delete({
        calendarId: payload.calendarId,
        eventId: binding.google_event_id,
      });

      // Delete binding
      await this.supabase
        .from('calendar_event_bindings')
        .delete()
        .eq('id', binding.id);

      console.log(
        `[CalendarSyncWorker] Cancelled event ${binding.google_event_id} for ${payload.sourceType}:${payload.sourceId}`
      );

      return { success: true, shouldRetry: false, isOAuthError: false };
    } catch (err) {
      return this.handleGoogleApiError(err as Error);
    }
  }

  /**
   * Process REBUILD_ALL operation
   */
  private async processRebuildAll(
    payload: RebuildAllPayload
  ): Promise<ProcessingResult> {
    try {
      // Get Google connection for workspace
      const connection = await this.getGoogleConnection(payload.workspaceId);
      if (!connection.isValid) {
        return {
          success: false,
          error: 'Google connection invalid - OAuth token expired or revoked',
          shouldRetry: false,
          isOAuthError: true,
        };
      }

      // Get Calendar API client
      const calendar = await this.getCalendarClient(connection.refreshToken);

      // Get all bindings for workspace
      const { data: bindings } = await this.supabase
        .from('calendar_event_bindings')
        .select('*')
        .eq('workspace_id', payload.workspaceId);

      // Cancel all existing events
      if (bindings && bindings.length > 0) {
        for (const binding of bindings) {
          try {
            await calendar.events.delete({
              calendarId: binding.calendar_id,
              eventId: binding.google_event_id,
            });
          } catch (err) {
            // Ignore errors (event might already be deleted)
            console.warn(
              `[CalendarSyncWorker] Error deleting event ${binding.google_event_id}:`,
              err
            );
          }
        }

        // Delete all bindings
        await this.supabase
          .from('calendar_event_bindings')
          .delete()
          .eq('workspace_id', payload.workspaceId);
      }

      // TODO: Create outbox items for all current tasks/milestones/gate_runs
      // This would require querying the database for all active entities
      // and creating UPSERT_EVENT items for each one.
      // For now, we'll just log a warning.
      console.warn(
        '[CalendarSyncWorker] REBUILD_ALL completed cancel phase. Recreation phase not yet implemented.'
      );

      return { success: true, shouldRetry: false, isOAuthError: false };
    } catch (err) {
      return this.handleGoogleApiError(err as Error);
    }
  }

  // ==========================================================================
  // GOOGLE API HELPERS
  // ==========================================================================

  /**
   * Get Google Calendar API client with OAuth2 authentication
   */
  private async getCalendarClient(
    refreshToken: string
  ): Promise<calendar_v3.Calendar> {
    const oauth2Client = new google.auth.OAuth2(
      this.config.googleClientId,
      this.config.googleClientSecret
    );

    oauth2Client.setCredentials({
      refresh_token: refreshToken,
    });

    return google.calendar({ version: 'v3', auth: oauth2Client });
  }

  /**
   * Build Google Calendar event object from payload
   */
  private buildGoogleEvent(event: UpsertEventPayload['event']): calendar_v3.Schema$Event {
    const googleEvent: calendar_v3.Schema$Event = {
      summary: event.title,
      description: event.description,
      location: event.location,
      colorId: event.colorId,
    };

    if (event.isAllDay) {
      // All-day event
      googleEvent.start = {
        date: event.start.split('T')[0], // YYYY-MM-DD
      };
      googleEvent.end = {
        date: event.end.split('T')[0],
      };
    } else {
      // Timed event
      googleEvent.start = {
        dateTime: event.start,
      };
      googleEvent.end = {
        dateTime: event.end,
      };
    }

    if (event.recurrence && event.recurrence.length > 0) {
      googleEvent.recurrence = event.recurrence;
    }

    return googleEvent;
  }

  /**
   * Get Google connection for workspace
   */
  private async getGoogleConnection(
    workspaceId: string
  ): Promise<GoogleConnection> {
    const { data: connection, error } = await this.supabase
      .from('google_connections')
      .select('*')
      .eq('workspace_id', workspaceId)
      .single();

    if (error || !connection) {
      return {
        refreshToken: '',
        calendarId: '',
        isValid: false,
      };
    }

    return {
      refreshToken: connection.refresh_token_encrypted, // TODO: Decrypt
      calendarId: connection.calendar_id || '',
      isValid: connection.is_valid,
    };
  }

  /**
   * Handle Google API errors and determine retry strategy
   */
  private handleGoogleApiError(error: Error): ProcessingResult {
    const errorMessage = error.message.toLowerCase();

    // OAuth errors (401, 403 with invalid_grant)
    if (
      errorMessage.includes('invalid_grant') ||
      errorMessage.includes('unauthorized') ||
      errorMessage.includes('token')
    ) {
      return {
        success: false,
        error: `OAuth error: ${error.message}`,
        shouldRetry: false,
        isOAuthError: true,
      };
    }

    // Rate limit errors (429)
    if (errorMessage.includes('rate limit') || errorMessage.includes('quota')) {
      return {
        success: false,
        error: `Rate limit error: ${error.message}`,
        shouldRetry: true,
        isOAuthError: false,
      };
    }

    // Not found errors (404) - don't retry
    if (errorMessage.includes('not found')) {
      return {
        success: false,
        error: `Not found: ${error.message}`,
        shouldRetry: false,
        isOAuthError: false,
      };
    }

    // Default: retriable error
    return {
      success: false,
      error: error.message,
      shouldRetry: true,
      isOAuthError: false,
    };
  }

  // ==========================================================================
  // FAILURE HANDLING & RETRY LOGIC
  // ==========================================================================

  /**
   * Handle processing failure with retry logic
   */
  private async handleFailure(
    item: SyncOutbox,
    result: ProcessingResult
  ): Promise<void> {
    const newAttempts = item.attempts + 1;

    // Check if should dead letter
    if (
      !result.shouldRetry ||
      newAttempts >= this.config.maxRetries ||
      result.isOAuthError
    ) {
      // Move to dead letter
      await this.updateOutboxStatus(
        item.id,
        'DEAD_LETTER',
        result.error || 'Unknown error'
      );

      console.error(
        `[CalendarSyncWorker] Item ${item.id} moved to DEAD_LETTER: ${result.error}`
      );

      // If OAuth error, mark connection as invalid
      if (result.isOAuthError) {
        await this.markConnectionInvalid(item.workspaceId);
      }

      return;
    }

    // Calculate next attempt with exponential backoff
    const nextAttemptAt = calculateNextAttempt(newAttempts);

    // Update for retry
    await this.supabase
      .from('sync_outbox')
      .update({
        status: 'FAILED',
        attempts: newAttempts,
        next_attempt_at: nextAttemptAt,
        last_error: result.error || 'Unknown error',
      })
      .eq('id', item.id);

    console.warn(
      `[CalendarSyncWorker] Item ${item.id} failed (attempt ${newAttempts}/${this.config.maxRetries}), will retry at ${nextAttemptAt}`
    );
  }

  /**
   * Update outbox item status
   */
  private async updateOutboxStatus(
    itemId: string,
    status: OutboxStatus,
    error?: string | null,
    markProcessed: boolean = false
  ): Promise<void> {
    const updates: any = { status };

    if (error !== undefined) {
      updates.last_error = error;
    }

    if (markProcessed) {
      updates.processed_at = new Date().toISOString();
    }

    await this.supabase.from('sync_outbox').update(updates).eq('id', itemId);
  }

  /**
   * Mark Google connection as invalid
   */
  private async markConnectionInvalid(workspaceId: string): Promise<void> {
    await this.supabase
      .from('google_connections')
      .update({ is_valid: false })
      .eq('workspace_id', workspaceId);

    console.warn(
      `[CalendarSyncWorker] Marked Google connection for workspace ${workspaceId} as INVALID`
    );
  }
}

// ============================================================================
// FACTORY FUNCTION
// ============================================================================

/**
 * Create and configure calendar sync worker
 */
export function createCalendarSyncWorker(
  config: CalendarSyncConfig
): CalendarSyncWorker {
  return new CalendarSyncWorker(config);
}
