import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Ban, CheckCircle2, CircleDashed, Clock, EyeOff, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { admin } from "../api/client";
import { cx } from "../components/ui";
import type { StaffMe } from "./types";

export const aapi = admin.api;

export function useStaff() {
  return useQuery({ queryKey: ["admin", "me"], queryFn: () => aapi<StaffMe>("/admin/auth/me"), retry: false, staleTime: 60_000 });
}

const STATUS: Record<string, { label: string; cls: string; icon: LucideIcon }> = {
  active: { label: "Live", cls: "bg-emerald-50 text-emerald-700 ring-emerald-200", icon: CheckCircle2 },
  approved: { label: "Approved", cls: "bg-emerald-50 text-emerald-700 ring-emerald-200", icon: CheckCircle2 },
  pending_review: { label: "In review", cls: "bg-amber-50 text-amber-800 ring-amber-200", icon: Clock },
  pending: { label: "Pending", cls: "bg-amber-50 text-amber-800 ring-amber-200", icon: Clock },
  open: { label: "Open", cls: "bg-amber-50 text-amber-800 ring-amber-200", icon: Clock },
  draft: { label: "Awaiting consent", cls: "bg-slate-100 text-slate-600 ring-slate-200", icon: CircleDashed },
  rejected: { label: "Needs changes", cls: "bg-orange-50 text-orange-700 ring-orange-200", icon: AlertTriangle },
  suspended: { label: "Suspended", cls: "bg-red-50 text-red-700 ring-red-200", icon: Ban },
  banned: { label: "Banned", cls: "bg-red-50 text-red-700 ring-red-200", icon: Ban },
  hidden: { label: "Hidden", cls: "bg-slate-100 text-slate-600 ring-slate-200", icon: EyeOff },
  actioned: { label: "Actioned", cls: "bg-slate-100 text-slate-700 ring-slate-200", icon: CheckCircle2 },
  dismissed: { label: "Dismissed", cls: "bg-slate-100 text-slate-600 ring-slate-200", icon: CircleDashed },
};

/** Status always carries an icon + label, never color alone. */
export function Status({ s }: { s: string }) {
  const v = STATUS[s] ?? { label: s, cls: "bg-slate-100 text-slate-600 ring-slate-200", icon: CircleDashed };
  const Icon = v.icon;
  return (
    <span className={cx("inline-flex items-center gap-1 whitespace-nowrap rounded-md px-2 py-0.5 text-xs font-semibold ring-1", v.cls)}>
      <Icon className="h-3.5 w-3.5" /> {v.label}
    </span>
  );
}

export function Panel({ title, action, children, className }: { title?: string; action?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={cx("rounded-xl border border-slate-200 bg-white", className)}>
      {title && (
        <header className="flex items-center justify-between gap-3 border-b border-slate-100 px-5 py-3.5">
          <h2 className="text-sm font-semibold text-slate-900">{title}</h2>
          {action}
        </header>
      )}
      {children}
    </section>
  );
}

export function PageHead({ title, sub, children }: { title: string; sub?: string; children?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-slate-900">{title}</h1>
        {sub && <p className="mt-1 text-sm text-slate-500">{sub}</p>}
      </div>
      {children}
    </div>
  );
}

export function Seg<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { value: T; label: string; count?: number }[] }) {
  return (
    <div className="inline-flex rounded-lg border border-slate-200 bg-white p-1">
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className={cx(
            "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition",
            value === o.value ? "bg-slate-900 text-white" : "text-slate-600 hover:bg-slate-100",
          )}
        >
          {o.label}
          {o.count != null && o.count > 0 && (
            <span className={cx("rounded px-1.5 text-xs", value === o.value ? "bg-white/20" : "bg-slate-200")}>{o.count}</span>
          )}
        </button>
      ))}
    </div>
  );
}

export const when = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" }) : "—";

export const ACTION_LABEL: Record<string, string> = {
  approve: "Approved profile",
  reject: "Asked for changes",
  suspend: "Suspended",
  ban: "Banned",
  reactivate: "Reactivated",
  warn: "Warned member",
  reveal_phone: "Revealed phone",
  photo_approve: "Approved photo",
  photo_reject: "Rejected photo",
  report_dismiss: "Dismissed report",
  report_warn: "Resolved report: warn",
  report_suspend: "Resolved report: suspend",
  report_ban: "Resolved report: ban",
  login: "Signed in",
  login_2fa_setup: "Signed in (set up 2-step)",
  locked_out: "Locked out (failed attempts)",
  staff_create_moderator: "Invited moderator",
  staff_create_admin: "Invited admin",
  staff_disable: "Disabled staff",
  staff_enable: "Enabled staff",
  staff_reset: "Reset staff login",
};

export const REASON_LABEL: Record<string, string> = {
  fake: "Fake profile",
  harassment: "Harassment",
  married: "Already married",
  scam_money: "Asked for money",
  dowry: "Dowry demand",
  obscene: "Obscene content",
  underage: "Under-age",
  other: "Other",
};
