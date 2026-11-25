import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import {
  Activity,
  AlertTriangle,
  ChevronDown,
  Info,
  KeyRound,
  LogIn,
  OctagonX,
  Pause,
  Play,
  RefreshCw,
  Search,
  X,
  type LucideIcon,
} from "lucide-react";
import { Fragment, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Button, IconChip, cx, type ChipColor } from "../components/ui";
import AdminLayout from "./AdminLayout";
import type { AppEventRow, LogPage, LogSummary } from "./types";
import { PageHead, Panel, Seg, aapi } from "./ui";

const CATEGORIES = [
  { value: "", label: "All" },
  { value: "auth", label: "Member sign-in" },
  { value: "staff", label: "Staff sign-in" },
  { value: "profile", label: "Profiles" },
  { value: "photo", label: "Photos" },
  { value: "interest", label: "Interests" },
  { value: "chat", label: "Chat" },
  { value: "safety", label: "Safety" },
  { value: "support", label: "Help desk" },
  { value: "system", label: "System" },
];

const EVENT_LABEL: Record<string, string> = {
  otp_sent: "OTP sent",
  otp_failed: "Wrong / expired OTP",
  otp_rate_limited: "OTP limit hit",
  member_login: "Member signed in",
  member_signup: "New account",
  blocked_account_login: "Suspended/banned tried to sign in",
  token_reuse_detected: "Stolen token suspected",
  staff_login: "Staff signed in",
  staff_2fa_setup: "Staff set up 2-step",
  staff_login_failed: "Staff wrong password",
  staff_2fa_failed: "Staff wrong 2-step code",
  staff_locked_out: "Staff account locked",
  staff_locked_attempt: "Sign-in while locked",
  staff_disabled_login: "Disabled staff tried to sign in",
  profile_created: "Profile created",
  candidate_consent: "Candidate consented",
  photo_uploaded: "Photo uploaded",
  photo_duplicate: "Duplicate photo",
  interest_sent: "Interest sent",
  interest_accepted: "Interest accepted",
  interest_limit_reached: "Daily interest limit",
  message_flagged: "Message flagged",
  message_blocked: "Dowry message blocked",
  chat_rate_limited: "Chat rate limit",
  report_filed: "Report filed",
  member_blocked: "Member blocked someone",
  profile_auto_hidden: "Profile auto-hidden",
  server_error: "Server error",
  vulgar_language_blocked: "Vulgar language blocked",
  member_muted: "Member chat muted",
  support_escalated: "Help request to team",
  support_replied: "Team replied to help request",
  app_started: "API started",
};

const LEVEL: Record<string, { label: string; cls: string; icon: LucideIcon }> = {
  info: { label: "Info", cls: "bg-sky-50 text-sky-700 ring-sky-100", icon: Info },
  warning: { label: "Warning", cls: "bg-amber-50 text-amber-800 ring-amber-200", icon: AlertTriangle },
  error: { label: "Error", cls: "bg-red-50 text-red-700 ring-red-200", icon: OctagonX },
};

function LevelChip({ level }: { level: string }) {
  const l = LEVEL[level] ?? LEVEL.info;
  const Icon = l.icon;
  return (
    <span className={cx("inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-semibold ring-1", l.cls)}>
      <Icon className="h-3.5 w-3.5" /> {l.label}
    </span>
  );
}

function Tile({ label, value, note, icon, color }: { label: string; value?: number; note?: string; icon: LucideIcon; color: ChipColor }) {
  return (
    <div className="rounded-3xl bg-white p-5 shadow-soft ring-1 ring-line/70">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-muted">{label}</p>
        <IconChip icon={icon} color={color} />
      </div>
      <p className="mt-2 font-display text-3xl font-semibold tabular-nums text-ink">{value?.toLocaleString("en-IN") ?? "—"}</p>
      {note && <p className="mt-0.5 text-xs text-muted">{note}</p>}
    </div>
  );
}

const time = (iso: string) =>
  new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit", second: "2-digit" });

function device(ua: string | null) {
  if (!ua) return "—";
  const os = /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iOS" : /Windows/.test(ua) ? "Windows" : /Mac OS/.test(ua) ? "macOS" : /Linux/.test(ua) ? "Linux" : "";
  const br = /Edg\//.test(ua) ? "Edge" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : /python|httpx|curl/i.test(ua) ? "Script" : "Browser";
  return [br, os].filter(Boolean).join(" on ");
}

export default function LogsPage() {
  const [params, setParams] = useSearchParams();
  const level = params.get("level") ?? "";
  const category = params.get("category") ?? "";
  const actor = params.get("actor") ?? "";
  const q = params.get("q") ?? "";
  const [search, setSearch] = useState(q);
  const [live, setLive] = useState(true);
  const [open, setOpen] = useState<number | null>(null);
  const set = (k: string, v: string) => {
    const next = new URLSearchParams(params);
    if (v) next.set(k, v);
    else next.delete(k);
    setParams(next);
  };

  const query = useMemo(() => {
    const u = new URLSearchParams();
    if (level) u.set("level", level);
    if (category) u.set("category", category);
    if (actor) u.set("actor", actor);
    if (q) u.set("q", q);
    return u.toString();
  }, [level, category, actor, q]);

  const summary = useQuery({
    queryKey: ["admin", "logs-summary"],
    queryFn: () => aapi<LogSummary>("/admin/logs/summary"),
    refetchInterval: live ? 10_000 : false,
  });
  const list = useInfiniteQuery({
    queryKey: ["admin", "logs", query],
    queryFn: ({ pageParam }) => aapi<LogPage>(`/admin/logs?${query}${pageParam ? `&before_id=${pageParam}` : ""}`),
    initialPageParam: 0,
    getNextPageParam: (last) => last.next_before_id ?? undefined,
    refetchInterval: live ? 10_000 : false,
  });
  const rows: AppEventRow[] = list.data?.pages.flatMap((p) => p.items) ?? [];
  const s = summary.data;

  return (
    <AdminLayout>
      <PageHead title="Application logs" sub="Sign-ins, security events and activity across the app. Kept for 90 days; phone numbers are masked and chat text is never logged.">
        <div className="flex gap-2">
          <Button variant="secondary" size="sm" onClick={() => setLive((v) => !v)}>
            {live ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
            {live ? "Live" : "Paused"}
            {live && <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-500" />}
          </Button>
          <Button variant="secondary" size="sm" onClick={() => { list.refetch(); summary.refetch(); }}>
            <RefreshCw className={cx("h-4 w-4", list.isFetching && "animate-spin")} /> Refresh
          </Button>
        </div>
      </PageHead>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Tile label="Events (24h)" value={s?.events_24h} icon={Activity} color="sky" />
        <Tile label="Sign-ins (24h)" value={s ? s.member_logins_24h + s.staff_logins_24h : undefined} note={s ? `${s.member_logins_24h} member${s.member_logins_24h === 1 ? "" : "s"} · ${s.staff_logins_24h} staff` : undefined} icon={LogIn} color="teal" />
        <Tile label="Failed sign-ins (24h)" value={s?.failed_logins_24h} note="Wrong OTP, password or 2-step code" icon={KeyRound} color="gold" />
        <Tile label="Errors (24h)" value={s?.errors_24h} note={s ? `${s.warnings_24h} warnings` : undefined} icon={OctagonX} color="rose" />
      </div>

      {/* Filters */}
      <div className="mt-8 flex flex-wrap items-center gap-3">
        <Seg
          value={level}
          onChange={(v) => set("level", v)}
          options={[
            { value: "", label: "All levels" },
            { value: "warning", label: "Warnings & errors" },
            { value: "error", label: "Errors only" },
          ]}
        />
        <form className="relative" onSubmit={(e) => { e.preventDefault(); set("q", search.trim()); }}>
          <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted/70" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search event, member ID, IP, request ID"
            className="w-80 rounded-full border-0 bg-white py-2.5 pl-10 pr-4 text-sm shadow-soft ring-1 ring-line/70 outline-none focus:ring-2 focus:ring-brand-500"
          />
        </form>
        {actor && (
          <span className="inline-flex items-center gap-2 rounded-full bg-brand-50 py-1.5 pl-3.5 pr-1.5 text-sm font-semibold text-brand-700 ring-1 ring-brand-200">
            Only: {actor}
            <button onClick={() => set("actor", "")} className="grid h-6 w-6 place-items-center rounded-full hover:bg-brand-100" aria-label="Clear person filter">
              <X className="h-3.5 w-3.5" />
            </button>
          </span>
        )}
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {CATEGORIES.map((c) => (
          <button
            key={c.value}
            onClick={() => set("category", c.value)}
            className={cx(
              "rounded-full px-3.5 py-1.5 text-sm font-semibold ring-1 transition",
              category === c.value ? "bg-brand-600 text-white ring-brand-600" : "bg-white text-ink/80 ring-line hover:ring-brand-200",
            )}
          >
            {c.label}
            {c.value && s?.by_category[c.value] ? <span className={cx("ml-1.5 text-xs", category === c.value ? "text-white/80" : "text-muted")}>{s.by_category[c.value]}</span> : null}
          </button>
        ))}
      </div>

      <Panel className="mt-6">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[960px] text-sm">
            <thead>
              <tr className="border-b border-line bg-sand/40 text-left text-xs font-bold uppercase tracking-wider text-muted">
                <th className="px-6 py-3.5">Time</th>
                <th className="px-3 py-3.5">Level</th>
                <th className="px-3 py-3.5">Event</th>
                <th className="px-3 py-3.5">Who</th>
                <th className="px-3 py-3.5">Details</th>
                <th className="px-3 py-3.5">IP</th>
                <th className="w-10 px-3 py-3.5" />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <Fragment key={r.id}>
                  <tr
                    onClick={() => setOpen(open === r.id ? null : r.id)}
                    className={cx("cursor-pointer border-b border-line/60 transition hover:bg-brand-50/40", r.level === "error" && "bg-red-50/40", open === r.id && "bg-brand-50/50")}
                  >
                    <td className="whitespace-nowrap px-6 py-3 font-mono text-xs text-muted">{time(r.created_at)}</td>
                    <td className="px-3 py-3"><LevelChip level={r.level} /></td>
                    <td className="px-3 py-3">
                      <p className="font-semibold text-ink">{EVENT_LABEL[r.event] ?? r.event}</p>
                      <p className="text-xs text-muted">{CATEGORIES.find((c) => c.value === r.category)?.label ?? r.category}</p>
                    </td>
                    <td className="px-3 py-3">
                      {r.actor ? (
                        r.actor_type === "member" && /^VM/.test(r.actor) ? (
                          <Link to={`/admin/profiles/${r.actor}`} onClick={(e) => e.stopPropagation()} className="font-mono text-xs font-semibold text-brand-700 hover:underline">{r.actor}</Link>
                        ) : (
                          <span className="font-mono text-xs text-ink">{r.actor}</span>
                        )
                      ) : (
                        <span className="text-muted">—</span>
                      )}
                      {r.actor_type && <p className="text-xs capitalize text-muted">{r.actor_type}</p>}
                    </td>
                    <td className="max-w-md px-3 py-3 text-ink/80"><p className="line-clamp-2">{r.message ?? "—"}</p></td>
                    <td className="whitespace-nowrap px-3 py-3 font-mono text-xs text-muted">{r.ip ?? "—"}</td>
                    <td className="px-3 py-3"><ChevronDown className={cx("h-4 w-4 text-muted transition", open === r.id && "rotate-180")} /></td>
                  </tr>
                  {open === r.id && (
                    <tr className="border-b border-line bg-sand/30">
                      <td colSpan={7} className="px-6 py-4">
                        <dl className="grid gap-x-8 gap-y-3 text-xs sm:grid-cols-2 lg:grid-cols-4">
                          <div><dt className="font-semibold uppercase tracking-wide text-muted">Event code</dt><dd className="mt-0.5 font-mono text-ink">{r.event}</dd></div>
                          <div><dt className="font-semibold uppercase tracking-wide text-muted">Request ID</dt><dd className="mt-0.5 font-mono text-ink">{r.request_id ?? "—"}</dd></div>
                          <div><dt className="font-semibold uppercase tracking-wide text-muted">Device</dt><dd className="mt-0.5 text-ink" title={r.user_agent ?? ""}>{device(r.user_agent)}</dd></div>
                          <div>
                            <dt className="font-semibold uppercase tracking-wide text-muted">More</dt>
                            <dd className="mt-0.5 flex flex-wrap gap-2">
                              {r.actor && <button onClick={() => set("actor", r.actor!)} className="font-semibold text-brand-700 hover:underline">All events by {r.actor}</button>}
                              {r.ip && <button onClick={() => { setSearch(r.ip!); set("q", r.ip!); }} className="font-semibold text-brand-700 hover:underline">Same IP</button>}
                            </dd>
                          </div>
                          {r.meta && (
                            <div className="sm:col-span-2 lg:col-span-4">
                              <dt className="font-semibold uppercase tracking-wide text-muted">Data</dt>
                              <dd className="mt-1 overflow-x-auto rounded-xl bg-white p-3 font-mono text-[11px] text-ink ring-1 ring-line">{JSON.stringify(r.meta)}</dd>
                            </div>
                          )}
                        </dl>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
        {list.isPending && <p className="p-6 text-sm text-muted">Loading…</p>}
        {list.isSuccess && rows.length === 0 && <p className="p-10 text-center text-sm text-muted">No events match these filters.</p>}
        {list.hasNextPage && (
          <div className="flex justify-center border-t border-line p-4">
            <Button variant="secondary" size="sm" loading={list.isFetchingNextPage} onClick={() => list.fetchNextPage()}>Load older events</Button>
          </div>
        )}
      </Panel>
    </AdminLayout>
  );
}
