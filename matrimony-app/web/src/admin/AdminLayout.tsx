import { useQuery } from "@tanstack/react-query";
import { Flag, Image, LayoutDashboard, LogOut, ScrollText, Shield, UserCog, Users, type LucideIcon } from "lucide-react";
import { useEffect, type ReactNode } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { admin } from "../api/client";
import { cx } from "../components/ui";
import type { Stats } from "./types";
import { aapi, useStaff } from "./ui";

export default function AdminLayout({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const me = useStaff();
  const stats = useQuery({ queryKey: ["admin", "stats"], queryFn: () => aapi<Stats>("/admin/stats"), refetchInterval: 60_000, enabled: me.isSuccess });

  useEffect(() => {
    if (!admin.hasSession() || me.isError) navigate("/admin/login", { replace: true });
  }, [me.isError, navigate]);

  if (!me.data) return <div className="min-h-screen bg-slate-50" />;
  const isAdmin = me.data.role === "admin";
  const nav: { to: string; label: string; icon: LucideIcon; count?: number; show: boolean }[] = [
    { to: "/admin", label: "Dashboard", icon: LayoutDashboard, show: true },
    { to: "/admin/profiles", label: "Profiles", icon: Users, count: stats.data?.profiles_pending, show: true },
    { to: "/admin/photos", label: "Photos", icon: Image, count: stats.data?.photos_pending, show: true },
    { to: "/admin/reports", label: "Reports", icon: Flag, count: stats.data?.reports_open, show: true },
    { to: "/admin/audit", label: "Audit log", icon: ScrollText, show: isAdmin },
    { to: "/admin/staff", label: "Staff", icon: UserCog, show: isAdmin },
  ];

  return (
    <div className="min-h-screen bg-slate-50 font-sans text-slate-900 lg:flex">
      <aside className="flex shrink-0 flex-col bg-slate-900 text-slate-300 lg:sticky lg:top-0 lg:h-screen lg:w-60">
        <div className="flex items-center gap-2.5 px-5 py-5">
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-brand-600 text-white">
            <Shield className="h-4 w-4" />
          </span>
          <div>
            <p className="text-sm font-semibold text-white">Matrimony</p>
            <p className="text-[11px] uppercase tracking-wider text-slate-400">Admin panel</p>
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-3 pb-3 lg:flex-1 lg:flex-col lg:overflow-visible">
          {nav.filter((n) => n.show).map(({ to, label, icon: Icon, count }) => (
            <NavLink
              key={to}
              to={to}
              end={to === "/admin"}
              className={({ isActive }) =>
                cx(
                  "flex items-center gap-3 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition",
                  isActive ? "bg-white/10 text-white" : "hover:bg-white/5 hover:text-white",
                )
              }
            >
              <Icon className="h-4 w-4" />
              <span className="flex-1">{label}</span>
              {!!count && <span className="rounded-md bg-amber-400/90 px-1.5 text-xs font-bold text-slate-900">{count}</span>}
            </NavLink>
          ))}
        </nav>
        <div className="hidden border-t border-white/10 p-4 lg:block">
          <p className="truncate text-sm font-medium text-white">{me.data.name}</p>
          <p className="truncate text-xs text-slate-400">{me.data.email}</p>
          <div className="mt-3 flex items-center justify-between">
            <span className="rounded bg-white/10 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-slate-200">{me.data.role}</span>
            <button
              onClick={async () => {
                await admin.logout();
                navigate("/admin/login", { replace: true });
              }}
              className="flex items-center gap-1.5 text-xs font-medium text-slate-400 hover:text-white"
            >
              <LogOut className="h-3.5 w-3.5" /> Sign out
            </button>
          </div>
        </div>
      </aside>
      <main className="min-w-0 flex-1 px-4 py-6 sm:px-8 sm:py-8">{children}</main>
    </div>
  );
}
