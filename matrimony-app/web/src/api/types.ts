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
  completeness: number;
  is_premium: boolean;
  family: Family | null;
  career: Career | null;
  horoscope: Horoscope | null;
  created_at: string;
}
