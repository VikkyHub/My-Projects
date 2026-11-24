// Hand-written to match the backend. Later: generate with openapi-typescript.
export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number;
  is_new_user: boolean;
  has_profile: boolean;
}

export interface OtpSent {
  message: string;
  expires_in: number;
  resend_after: number;
}

export interface Option {
  id: number;
  name: string;
}

export interface CityOption extends Option {
  state: string;
}

export type CreatedBy = "self" | "parent" | "sibling" | "relative" | "friend";
export type Gender = "male" | "female";
export type MaritalStatus = "never_married" | "divorced" | "widowed" | "awaiting_divorce";

export interface Family {
  father_occupation: string | null;
  mother_occupation: string | null;
  brothers: number | null;
  brothers_married: number | null;
  sisters: number | null;
  sisters_married: number | null;
  family_type: "joint" | "nuclear" | null;
  family_status: "middle" | "upper_middle" | "rich" | "affluent" | null;
  family_values: "traditional" | "moderate" | "liberal" | null;
  native_place: string | null;
}

export interface Career {
  education_level_id: number | null;
  education_detail: string | null;
  college: string | null;
  occupation_id: number | null;
  employer: string | null;
  employed_in: "private" | "govt" | "business" | "self_employed" | "not_working" | null;
  annual_income_band: number | null;
}

export interface Horoscope {
  rashi: string | null;
  nakshatra: string | null;
  manglik: "yes" | "no" | "anshik" | "dont_know" | null;
  birth_time: string | null;
  birth_place: string | null;
  gotra: string | null;
  visible_to: "all" | "premium" | "accepted";
}

export interface MyProfile {
  public_id: string;
  created_by: CreatedBy;
  candidate_phone_masked: string | null;
  candidate_consent_pending: boolean;
  first_name: string;
  last_name: string | null;
  gender: Gender;
  dob: string;
  age: number;
  height_cm: number | null;
  marital_status: MaritalStatus;
  has_children: boolean | null;
  religion_id: number;
  community_id: number | null;
  sub_community_id: number | null;
  mother_tongue_id: number | null;
  city_id: number | null;
  diet: string | null;
  smoke: string | null;
  drink: string | null;
  about_me: string | null;
  status: "draft" | "pending_review" | "active" | "hidden" | "rejected" | "suspended";
  moderation_note: string | null;
  completeness: number;
  is_premium: boolean;
  family: Family | null;
  career: Career | null;
  horoscope: Horoscope | null;
  created_at: string;
}

// ---------- social ----------
export interface InterestRef {
  id: string;
  status: "pending" | "accepted" | "declined" | "withdrawn";
  direction: "sent" | "received";
}

export interface ProfileCard {
  public_id: string;
  name: string;
  first_name: string;
  gender: Gender;
  age: number;
  height_cm: number | null;
  marital_status: MaritalStatus;
  religion: string | null;
  community: string | null;
  mother_tongue: string | null;
  city: string | null;
  state: string | null;
  education: string | null;
  occupation: string | null;
  about: string | null;
  is_premium: boolean;
  created_by: CreatedBy;
  last_active: string | null;
  photo_url: string | null;
  photo_locked: boolean;
  match_score: number | null;
  match_reasons: string[];
  interest: InterestRef | null;
  conversation_id: string | null;
  shortlisted: boolean;
}

export interface MatchPage {
  items: ProfileCard[];
  next_cursor: string | null;
}

export interface PublicProfile extends ProfileCard {
  about_full: string | null;
  photos: string[];
  family: Partial<Family> | null;
  career: {
    education: string | null;
    education_detail: string | null;
    college: string | null;
    occupation: string | null;
    employed_in: string | null;
    annual_income_band: number | null;
  } | null;
  horoscope: Partial<Horoscope> | null;
  horoscope_locked: boolean;
  diet: string | null;
  smoke: string | null;
  drink: string | null;
  has_children: boolean | null;
}

export interface Preferences {
  age_min: number | null;
  age_max: number | null;
  height_min_cm: number | null;
  height_max_cm: number | null;
  marital_statuses: MaritalStatus[] | null;
  religion_ids: number[] | null;
  community_ids: number[] | null;
  mother_tongue_ids: number[] | null;
  state_ids: number[] | null;
  min_education_rank: number | null;
  min_income_band: number | null;
  diets: string[] | null;
}

export interface InterestItem {
  id: string;
  status: InterestRef["status"];
  direction: "sent" | "received";
  note: string | null;
  created_at: string;
  responded_at: string | null;
  profile: ProfileCard;
}

export interface Counts {
  received_pending: number;
  unread_messages: number;
  sent_today: number;
  daily_limit: number;
}

export interface Conversation {
  id: string;
  profile: ProfileCard;
  last_message: string | null;
  last_message_at: string | null;
  last_from_me: boolean;
  unread: number;
  can_chat: boolean;
  blocked_reason: "premium_required" | "closed" | null;
}

export interface Message {
  id: number;
  conversation_id: string;
  sender_public_id: string;
  body: string;
  flagged: boolean;
  created_at: string;
  read_at: string | null;
}

export interface Photo {
  id: string;
  url: string;
  status: "pending" | "approved" | "rejected";
  is_primary: boolean;
}
