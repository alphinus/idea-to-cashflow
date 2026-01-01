-- Migration: Create workspaces and memberships tables with RLS
-- Feature: F002
-- Description: Multi-tenant workspace structure with role-based access control

-- ============================================================================
-- WORKSPACES TABLE
-- ============================================================================

CREATE TABLE workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  timezone TEXT NOT NULL DEFAULT 'Europe/Zurich',

  -- Google Drive integration
  drive_folder_inbox_id TEXT,
  drive_folder_processed_id TEXT,
  drive_folder_error_id TEXT,

  -- Google Calendar integration
  calendar_id TEXT,
  weekly_review_rrule TEXT DEFAULT 'RRULE:FREQ=WEEKLY;BYDAY=MO;BYHOUR=9;BYMINUTE=0',

  -- Budget controls
  budget_daily_usd NUMERIC(10, 2) DEFAULT 10.00,
  budget_monthly_usd NUMERIC(10, 2) DEFAULT 200.00,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for workspaces
CREATE INDEX idx_workspaces_slug ON workspaces(slug);
CREATE INDEX idx_workspaces_created_at ON workspaces(created_at);

-- Comments
COMMENT ON TABLE workspaces IS 'Multi-tenant workspaces - root entity for all data';
COMMENT ON COLUMN workspaces.slug IS 'URL-safe unique identifier for workspace';
COMMENT ON COLUMN workspaces.timezone IS 'IANA timezone for calendar and scheduling';
COMMENT ON COLUMN workspaces.drive_folder_inbox_id IS 'Google Drive folder ID for incoming intake files';
COMMENT ON COLUMN workspaces.drive_folder_processed_id IS 'Google Drive folder ID for processed files';
COMMENT ON COLUMN workspaces.drive_folder_error_id IS 'Google Drive folder ID for failed files';
COMMENT ON COLUMN workspaces.calendar_id IS 'Google Calendar ID for sync';
COMMENT ON COLUMN workspaces.weekly_review_rrule IS 'RRULE for weekly project review events';
COMMENT ON COLUMN workspaces.budget_daily_usd IS 'Daily LLM spending limit in USD';
COMMENT ON COLUMN workspaces.budget_monthly_usd IS 'Monthly LLM spending limit in USD';

-- ============================================================================
-- MEMBERSHIPS TABLE
-- ============================================================================

CREATE TABLE memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role workspace_role NOT NULL DEFAULT 'VIEWER',

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Unique constraint: one role per user per workspace
  CONSTRAINT unique_workspace_user UNIQUE (workspace_id, user_id)
);

-- Indexes for memberships
CREATE INDEX idx_memberships_workspace_id ON memberships(workspace_id);
CREATE INDEX idx_memberships_user_id ON memberships(user_id);
CREATE INDEX idx_memberships_role ON memberships(role);

-- Comments
COMMENT ON TABLE memberships IS 'User membership in workspaces with role-based access';
COMMENT ON COLUMN memberships.role IS 'User role: ADMIN (full access), EDITOR (create/edit), VIEWER (read-only)';

-- ============================================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to workspaces
CREATE TRIGGER tr_workspaces_updated_at
  BEFORE UPDATE ON workspaces
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Apply updated_at trigger to memberships
CREATE TRIGGER tr_memberships_updated_at
  BEFORE UPDATE ON memberships
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- HELPER FUNCTIONS FOR RLS
-- ============================================================================

-- Get current user's ID from JWT
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claim.sub', true)::UUID,
    (current_setting('request.jwt.claims', true)::JSONB ->> 'sub')::UUID
  );
$$ LANGUAGE sql STABLE;

-- Check if user is member of workspace
CREATE OR REPLACE FUNCTION is_workspace_member(ws_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM memberships
    WHERE workspace_id = ws_id
      AND user_id = auth.uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Check if user has specific role in workspace
CREATE OR REPLACE FUNCTION has_workspace_role(ws_id UUID, required_role workspace_role)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM memberships
    WHERE workspace_id = ws_id
      AND user_id = auth.uid()
      AND (
        role = required_role
        OR role = 'ADMIN'  -- Admin has all permissions
        OR (required_role = 'VIEWER' AND role IN ('EDITOR', 'ADMIN'))  -- Editor includes viewer
      )
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Check if user is admin of workspace
CREATE OR REPLACE FUNCTION is_workspace_admin(ws_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM memberships
    WHERE workspace_id = ws_id
      AND user_id = auth.uid()
      AND role = 'ADMIN'
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Check if user is editor or admin of workspace
CREATE OR REPLACE FUNCTION is_workspace_editor(ws_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM memberships
    WHERE workspace_id = ws_id
      AND user_id = auth.uid()
      AND role IN ('ADMIN', 'EDITOR')
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================================
-- ROW LEVEL SECURITY - WORKSPACES
-- ============================================================================

ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can view their workspaces
CREATE POLICY workspaces_select_policy ON workspaces
  FOR SELECT
  USING (is_workspace_member(id));

-- INSERT: Any authenticated user can create a workspace
CREATE POLICY workspaces_insert_policy ON workspaces
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: Only admins can update workspace settings
CREATE POLICY workspaces_update_policy ON workspaces
  FOR UPDATE
  USING (is_workspace_admin(id))
  WITH CHECK (is_workspace_admin(id));

-- DELETE: Only admins can delete workspaces
CREATE POLICY workspaces_delete_policy ON workspaces
  FOR DELETE
  USING (is_workspace_admin(id));

-- ============================================================================
-- ROW LEVEL SECURITY - MEMBERSHIPS
-- ============================================================================

ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

-- SELECT: Members can see all memberships in their workspaces
CREATE POLICY memberships_select_policy ON memberships
  FOR SELECT
  USING (is_workspace_member(workspace_id));

-- INSERT: Only admins can add members
CREATE POLICY memberships_insert_policy ON memberships
  FOR INSERT
  WITH CHECK (is_workspace_admin(workspace_id));

-- UPDATE: Only admins can update member roles
CREATE POLICY memberships_update_policy ON memberships
  FOR UPDATE
  USING (is_workspace_admin(workspace_id))
  WITH CHECK (is_workspace_admin(workspace_id));

-- DELETE: Only admins can remove members (except themselves - must have at least one admin)
CREATE POLICY memberships_delete_policy ON memberships
  FOR DELETE
  USING (
    is_workspace_admin(workspace_id)
    AND NOT (
      -- Prevent deleting the last admin
      user_id = auth.uid()
      AND role = 'ADMIN'
      AND (
        SELECT COUNT(*) FROM memberships m
        WHERE m.workspace_id = memberships.workspace_id
          AND m.role = 'ADMIN'
      ) = 1
    )
  );

-- ============================================================================
-- SPECIAL POLICY: First member becomes admin
-- ============================================================================

-- When a workspace is created, the creator should be added as admin
-- This is handled by application logic (API routes) after workspace creation

-- ============================================================================
-- SERVICE ROLE BYPASS
-- ============================================================================

-- Service role (worker processes) can bypass RLS
-- This is automatic in Supabase when using service_role key

COMMENT ON POLICY workspaces_select_policy ON workspaces IS 'Members can view workspaces they belong to';
COMMENT ON POLICY workspaces_insert_policy ON workspaces IS 'Authenticated users can create workspaces';
COMMENT ON POLICY workspaces_update_policy ON workspaces IS 'Only admins can modify workspace settings';
COMMENT ON POLICY workspaces_delete_policy ON workspaces IS 'Only admins can delete workspaces';

COMMENT ON POLICY memberships_select_policy ON memberships IS 'Members can see all memberships in their workspace';
COMMENT ON POLICY memberships_insert_policy ON memberships IS 'Only admins can add new members';
COMMENT ON POLICY memberships_update_policy ON memberships IS 'Only admins can change member roles';
COMMENT ON POLICY memberships_delete_policy ON memberships IS 'Admins can remove members, but cannot delete the last admin';
