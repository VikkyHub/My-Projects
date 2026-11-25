export interface StaffMe {
  id: string;
  name: string | null;
  email: string | null;
  role: "moderator" | "admin";
}

export interface Stats {
  members_total: number;
  signups_today: number;
  signups_7d: number;
  profiles_live: number;
  profiles_pending: number;
  photos_pending: number;
  reports_open: number;
  premium_members: number;
  interests_today: number;
  messages_today: number;
}

export interface ProfileRow {
  public_id: string;
  name: string;
  gender: "male" | "female";
  age: number;
  religion: string | null;
  community: string | null;
  city: string | null;
  created_by: string;
  status: string;
  account_status: string;
  completeness: number;
  photos_pending: number;
  photos_total: number;
  reports_open: number;
  is_premium: boolean;
  created_at: string;
  moderation_note: string | null;
}

export interface ProfilePage {
  items: ProfileRow[];
  total: number;
  page: number;
  pages: number;
}

export interface AdminPhoto {
  id: string;
  url: string;
  status: "pending" | "approved" | "rejected";
  is_primary: boolean;
  duplicate: boolean;
  created_at: string;
}

export interface Mini {
  public_id: string;
  name: string;
  status: string;
}

export interface ReportRow {
  id: string;
  reason: string;
  details: string | null;
  status: string;
  created_at: string;
  reporter: Mini;
  reported: Mini;
  message: string | null;
  reported_open_reports: number;
}

export interface ActionRow {
  id: number;
  staff: string;
  action: string;
  target_type: string;
  target_id: string;
  reason: string | null;
  created_at: string;
}

export interface ProfileDetail extends ProfileRow {
  phone_masked: string | null;
  consent_pending: boolean;
  dob: string;
  height_cm: number | null;
  marital_status: string;
  mother_tongue: string | null;
  about_me: string | null;
  family: Record<string, string | null> | null;
  career: Record<string, string | null> | null;
  horoscope: Record<string, string | null> | null;
  photos: AdminPhoto[];
  reports: ReportRow[];
  history: ActionRow[];
}

export interface PhotoQueueItem extends AdminPhoto {
  profile: { public_id: string; name: string; gender: string; age: number; status: string };
}

export interface StaffRow {
  id: string;
  name: string | null;
  email: string | null;
  role: "moderator" | "admin";
  status: string;
  totp_enabled: boolean;
  last_login_at: string | null;
  created_at: string;
}

export interface AppEventRow {
  id: number;
  created_at: string;
  level: "info" | "warning" | "error";
  category: string;
  event: string;
  actor_type: string | null;
  actor: string | null;
  message: string | null;
  ip: string | null;
  user_agent: string | null;
  request_id: string | null;
  meta: Record<string, unknown> | null;
}

export interface LogPage {
  items: AppEventRow[];
  next_before_id: number | null;
}

export interface LogSummary {
  events_24h: number;
  warnings_24h: number;
  errors_24h: number;
  failed_logins_24h: number;
  member_logins_24h: number;
  staff_logins_24h: number;
  by_category: Record<string, number>;
}
