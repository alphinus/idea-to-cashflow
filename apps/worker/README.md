# Worker Services

This directory contains background worker services for the Idea-to-Cashflow pipeline.

## Calendar Sync Worker (F040)

The Calendar Sync Worker drains the `sync_outbox` table and synchronizes events to Google Calendar.

### Features

- **Advisory Locks**: Prevents duplicate processing across multiple worker instances
- **Exponential Backoff**: Retries failed operations with increasing delays (1s → 2s → 4s → 8s → 16s → ...)
- **Dead Letter Queue**: Moves items to `DEAD_LETTER` status after max retries
- **OAuth Error Handling**: Gracefully handles token expiration/revocation and marks connections as invalid
- **Idempotent Operations**: Uses `calendar_event_bindings` to prevent duplicate events

### Configuration

Required environment variables:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
CALENDAR_SYNC_BATCH_SIZE=10
CALENDAR_SYNC_POLL_INTERVAL_MS=5000
CALENDAR_SYNC_MAX_RETRIES=5
```

### Usage

```typescript
import { createCalendarSyncWorker } from './services/calendar_sync_service';

const worker = createCalendarSyncWorker({
  supabaseUrl: process.env.SUPABASE_URL!,
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
  googleClientId: process.env.GOOGLE_CLIENT_ID!,
  googleClientSecret: process.env.GOOGLE_CLIENT_SECRET!,
  batchSize: 10,
  pollIntervalMs: 5000,
  maxRetries: 5,
});

// Start the worker
await worker.start();

// Stop the worker (on shutdown)
await worker.stop();
```

### Operations

#### UPSERT_EVENT

Creates or updates a calendar event for a task, milestone, gate_run, or project_review.

**Payload:**
```json
{
  "operation": "UPSERT_EVENT",
  "workspaceId": "uuid",
  "calendarId": "calendar@example.com",
  "sourceType": "task",
  "sourceId": "uuid",
  "eventType": "BLOCKER_DEADLINE",
  "event": {
    "title": "Complete user interviews",
    "description": "P1 blocking task",
    "start": "2025-01-15T14:00:00Z",
    "end": "2025-01-15T15:00:00Z",
    "isAllDay": false
  }
}
```

#### CANCEL_EVENT

Cancels/deletes a calendar event.

**Payload:**
```json
{
  "operation": "CANCEL_EVENT",
  "workspaceId": "uuid",
  "calendarId": "calendar@example.com",
  "sourceType": "task",
  "sourceId": "uuid"
}
```

#### REBUILD_ALL

Cancels all events for a workspace and recreates them from current state.

**Payload:**
```json
{
  "operation": "REBUILD_ALL",
  "workspaceId": "uuid",
  "calendarId": "calendar@example.com"
}
```

### Error Handling

The worker handles errors gracefully:

1. **OAuth Errors** (401, 403 invalid_grant):
   - Marks `google_connections.is_valid = false`
   - Moves item to `DEAD_LETTER` (no retry)
   - Admin must reconnect OAuth

2. **Rate Limit Errors** (429):
   - Retries with exponential backoff
   - Max delay capped at 1 hour

3. **Not Found Errors** (404):
   - Moves to `DEAD_LETTER` (no retry)
   - Event may have been manually deleted

4. **Other Errors**:
   - Retries with exponential backoff
   - Moves to `DEAD_LETTER` after max attempts

### Monitoring

Check outbox status:
```sql
SELECT status, COUNT(*)
FROM sync_outbox
GROUP BY status;
```

View dead letter items:
```sql
SELECT *
FROM sync_outbox
WHERE status = 'DEAD_LETTER'
ORDER BY updated_at DESC;
```

Clean up old items:
```sql
SELECT cleanup_old_outbox_items(30); -- Delete items older than 30 days
```

### Architecture Notes

- Uses PostgreSQL advisory locks (`pg_try_advisory_lock`) for distributed locking
- Lock key is derived from `hashtext(outbox_id::text)`
- Locks are automatically released on connection close
- Worker polls every N milliseconds (configurable)
- Each worker processes up to `batchSize` items per poll
- Items are ordered by `created_at` (FIFO)

### Dependencies

This worker depends on:
- F012: `calendar_event_bindings` table
- F013: `sync_outbox` table
- F014: `google_connections` table (with encrypted tokens)
- F026: Token encryption utility (TODO: implement decryption)

### Future Enhancements

- [ ] Implement token decryption for `google_connections.refresh_token_encrypted`
- [ ] Complete `REBUILD_ALL` recreation phase
- [ ] Add metrics/observability (Prometheus, DataDog, etc.)
- [ ] Batch API calls for efficiency (Google Calendar Batch API)
- [ ] Add circuit breaker for repeated failures
