/**
 * Small fetch wrapper:
 *  - access token kept in memory only
 *  - refresh token in localStorage (TODO before launch: move to an httpOnly cookie
 *    so XSS can't read it — needs a cookie mode on the /auth endpoints)
 *  - on 401, refreshes once and retries; concurrent 401s share one refresh call
 */
export const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000/api/v1";
const API_ORIGIN = new URL(API_URL).origin;

/** Backend returns signed media paths like /api/v1/media/...; make them absolute. */
export function mediaUrl(path: string | null | undefined): string | undefined {
  if (!path) return undefined;
  return path.startsWith("http") ? path : `${API_ORIGIN}${path}`;
}

export function wsUrl(ticket: string): string {
  const u = new URL(API_URL);
  u.protocol = u.protocol === "https:" ? "wss:" : "ws:";
  return `${u.toString().replace(/\/$/, "")}/ws?ticket=${encodeURIComponent(ticket)}`;
}
const REFRESH_KEY = "rt";

let accessToken: string | null = null;
let refreshing: Promise<boolean> | null = null;

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

export interface Tokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

export function setTokens(t: Tokens) {
  accessToken = t.access_token;
  localStorage.setItem(REFRESH_KEY, t.refresh_token);
}

export function clearTokens() {
  accessToken = null;
  localStorage.removeItem(REFRESH_KEY);
}

export function hasSession() {
  return accessToken !== null || localStorage.getItem(REFRESH_KEY) !== null;
}

async function refresh(): Promise<boolean> {
  const rt = localStorage.getItem(REFRESH_KEY);
  if (!rt) return false;
  const r = await fetch(`${API_URL}/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: rt }),
  });
  if (!r.ok) {
    clearTokens();
    return false;
  }
  setTokens(await r.json());
  return true;
}

function errorMessage(body: unknown, status: number): string {
  const detail = (body as { detail?: unknown })?.detail;
  if (typeof detail === "string") return detail;
  // FastAPI 422 validation errors: [{msg, loc}, ...]
  if (Array.isArray(detail) && detail[0]?.msg) return String(detail[0].msg).replace(/^Value error, /, "");
  return `Request failed (${status})`;
}

const PUBLIC_AUTH = /^\/auth\/(otp\/|refresh|logout)/;

export async function api<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  // After a page reload the access token (memory only) is gone: renew it first instead of
  // letting every request fail with 401. Concurrent callers share one refresh.
  if (!accessToken && localStorage.getItem(REFRESH_KEY) && !PUBLIC_AUTH.test(path)) {
    refreshing ??= refresh().finally(() => (refreshing = null));
    await refreshing;
  }
  const headers = new Headers(init.headers);
  if (init.body && !(init.body instanceof FormData)) headers.set("Content-Type", "application/json");
  if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);

  const r = await fetch(`${API_URL}${path}`, { ...init, headers });

  if (r.status === 401 && retry && localStorage.getItem(REFRESH_KEY)) {
    refreshing ??= refresh().finally(() => (refreshing = null));
    if (await refreshing) return api<T>(path, init, false);
  }
  if (r.status === 204) return undefined as T;
  const body = await r.json().catch(() => null);
  if (!r.ok) throw new ApiError(r.status, errorMessage(body, r.status));
  return body as T;
}

export async function logout() {
  const rt = localStorage.getItem(REFRESH_KEY);
  if (rt) {
    await api("/auth/logout", { method: "POST", body: JSON.stringify({ refresh_token: rt }) }).catch(
      () => undefined,
    );
  }
  clearTokens();
}
