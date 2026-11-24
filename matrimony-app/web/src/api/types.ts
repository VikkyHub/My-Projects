// Hand-written for now. In week 2, generate from the backend with:
//   npx openapi-typescript http://localhost:8000/openapi.json -o src/api/schema.d.ts
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

export interface MyProfile {
  public_id: string;
  created_by: string;
  candidate_phone_masked: string | null;
  candidate_consent_pending: boolean;
  first_name: string;
  last_name: string | null;
  gender: "male" | "female";
  age: number;
  status: string;
  completeness: number;
}
