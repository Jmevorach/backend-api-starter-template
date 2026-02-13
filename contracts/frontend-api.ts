/**
 * Frontend-facing API contract types.
 *
 * These interfaces mirror documented payloads in docs/API_CONTRACT.md
 * and core controller behavior in the Phoenix backend.
 */

export interface ApiError {
  error: string;
  code?: string;
  message?: string;
  request_id?: string | null;
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

export interface Profile {
  id: string;
  email?: string;
  name?: string;
  first_name?: string | null;
  last_name?: string | null;
  avatar_url?: string | null;
  auth_provider?: string;
}

export interface ProfileResponse {
  data: Profile;
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

export interface Dashboard {
  user: {
    id: string;
    name?: string;
    email?: string;
  };
  summary: {
    active_notes: number;
    archived_notes: number;
    recent_notes: Note[];
  };
}

export interface DashboardResponse {
  data: Dashboard;
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

export interface Project {
  id: string;
  name: string;
  description?: string | null;
  archived: boolean;
  inserted_at: string;
  updated_at: string;
}

export interface ProjectWithTasks extends Project {
  tasks: Task[];
}

export interface ProjectResponse {
  data: Project | ProjectWithTasks;
}

export interface ProjectsListResponse {
  data: Project[];
}

export type TaskStatus = "todo" | "in_progress" | "done";

export interface Task {
  id: string;
  project_id: string;
  title: string;
  details?: string | null;
  status: TaskStatus;
  due_date?: string | null;
  inserted_at: string;
  updated_at: string;
}

export interface TaskResponse {
  data: Task;
}

export interface TasksListResponse {
  data: Task[];
}
