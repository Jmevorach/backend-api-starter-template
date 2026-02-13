/**
 * Frontend-facing API contract types.
 *
 * These interfaces mirror documented payloads in docs/API_CONTRACT.md
 * and core controller behavior in the Phoenix backend.
 */

export interface ApiError {
  error: string;
  message?: string;
  details?: Record<string, unknown>;
}

export interface AuthenticatedUser {
  email?: string;
  name?: string;
  first_name?: string | null;
  last_name?: string | null;
  image?: string | null;
  provider?: string;
  provider_uid?: string;
  id?: string;
}

export interface MeResponse {
  user: AuthenticatedUser;
  authenticated: true;
}

export interface PatientProfile {
  id: string;
  email?: string;
  name?: string;
  first_name?: string | null;
  last_name?: string | null;
  avatar_url?: string | null;
  auth_provider?: string;
}

export interface PatientProfileResponse {
  data: PatientProfile;
}

export interface Note {
  id: string;
  title: string;
  content: string | null;
  archived: boolean;
  inserted_at: string;
  updated_at: string;
}

export interface NotesListMeta {
  count: number;
  total: number;
  limit: number;
  offset: number;
}

export interface NotesListResponse {
  data: Note[];
  meta: NotesListMeta;
}

export interface NoteResponse {
  data: Note;
}

export interface PatientDashboard {
  patient: {
    id: string;
    name?: string;
    email?: string;
  };
  care_summary: {
    active_notes: number;
    archived_notes: number;
    recent_notes: Note[];
  };
}

export interface PatientDashboardResponse {
  data: PatientDashboard;
}

export interface UploadPresignRequest {
  filename: string;
  content_type: string;
}

export interface UploadPresignResponse {
  url: string;
  key: string;
  fields: Record<string, string>;
}

export interface UploadFileMetadata {
  key: string;
  filename?: string;
  size?: number;
  content_type?: string;
  last_modified?: string;
  etag?: string;
}

export interface UploadListResponse {
  files: UploadFileMetadata[];
  next_token: string | null;
}

export interface UploadDownloadResponse {
  url: string;
  key: string;
}

export interface UploadAllowedTypesResponse {
  content_types: string[];
}
