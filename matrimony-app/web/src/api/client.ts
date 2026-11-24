/**
 * Small fetch wrapper with two independent sessions:
 *  - member session: refresh token in localStorage (stays logged in for 30 days)
 *    TODO before launch: move to an httpOnly cookie so XSS can't read it.
 *  - staff session (admin panel): refresh token in sessionStorage — gone when the browser
 *    closes, and never mixed with a member login in the same browser.
 * Access tokens live in memory only. On 401 we refresh once and retry; concurrent callers
 * share one refresh.
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

function errorMessage(body: unknown, status: number): string {
  const detail = (body as { detail?: unknown })?.detail;
  if (typeof detail === "string") return detail;
  // FastAPI 422 validation errors: [{msg, loc}, ...]
  if (Array.isArray(detail) && detail[0]?.msg) return String(detail[0].msg).replace(/^Value error, /, "");
  return `Request failed (${status})`;
}

const PUBLIC_AUTH = /^\/(admin\/)?auth\/(otp\/|login|verify|refresh|logout)/;

function safeStorage(kind: "local" | "session"): Storage | null {
  try {
    return kind === "local" ? window.localStorage : window.sessionStorage;
  } catch {
    return null;
  }
}

function createSession(storageKind: "local" | "session", key: string, onExpired?: () => void) {
  let accessToken: string | null = null;
  let refreshing: Promise<boolean> | null = null;
  const store = () => safeStorage(storageKind);
  const getRefresh = () => store()?.getItem(key) ?? null;

  const setTokens = (t: Tokens) => {
    accessToken = t.access_token;
    store()?.setItem(key, t.refresh_token);
  };
  const clearTokens = () => {
    accessToken = null;
    store()?.removeItem(key);
  };
  const hasSession = () => accessToken !== null || getRefresh() !== null;

  async function refresh(): Promise<boolean> {
    const rt = getRefresh();
    if (!rt) return false;
    const r = await fetch(`${API_URL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: rt }),
    });
    if (!r.ok) {
      clearTokens();
      onExpired?.();
      return false;
    }
    setTokens(await r.json());
    return true;
  }
  const sharedRefresh = () => (refreshing ??= refresh().finally(() => (refreshing = null)));

  async function api<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
    // After a page reload the access token (memory only) is gone: renew it first instead of
    // letting every request fail with 401.
    if (!accessToken && getRefresh() && !PUBLIC_AUTH.test(path)) await sharedRefresh();
    const headers = new Headers(init.headers);
    if (init.body && !(init.body instanceof FormData)) headers.set("Content-Type", "application/json");
    if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);

    const r = await fetch(`${API_URL}${path}`, { ...init, headers });

    if (r.status === 401 && retry && getRefresh() && !PUBLIC_AUTH.test(path)) {
      if (await sharedRefresh()) return api<T>(path, init, false);
    }
    if (r.status === 204) return undefined as T;
    const body = await r.json().catch(() => null);
    if (!r.ok) throw new ApiError(r.status, errorMessage(body, r.status));
    return body as T;
  }

  async function logout() {
    const rt = getRefresh();
    if (rt) {
      await api("/auth/logout", { method: "POST", body: JSON.stringify({ refresh_token: rt }) }).catch(
        () => undefined,
      );
    }
    clearTokens();
  }

  return { api, setTokens, clearTokens, hasSession, logout };
}

// ---- member session (the app) ----
const member = createSession("local", "rt");
export const api = member.api;
export const setTokens = member.setTokens;
export const clearTokens = member.clearTokens;
export const hasSession = member.hasSession;
export const logout = member.logout;

// ---- staff session (admin panel) ----
export const admin = createSession("session", "admin_rt", () => {
  if (location.pathname.startsWith("/admin") && !location.pathname.startsWith("/admin/login"))
    location.assign("/admin/login?expired=1");
});
