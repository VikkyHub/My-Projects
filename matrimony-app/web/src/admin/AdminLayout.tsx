import { useQuery } from "@tanstack/react-query";
import { Activity, Flag, Heart, LifeBuoy, Image, LayoutDashboard, LogOut, ScrollText, UserCog, Users, type LucideIcon } from "lucide-react";
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

  if (!me.data) return <div className="pattern-soft min-h-screen bg-ivory" />;
  const isAdmin = me.data.role === "admin";
  const nav: { to: string; label: string; icon: LucideIcon; count?: number; show: boolean }[] = [
    { to: "/admin", label: "Dashboard", icon: LayoutDashboard, show: true },
    { to: "/admin/profiles", label: "Profiles", icon: Users, count: stats.data?.profiles_pending, show: true },
    { to: "/admin/photos", label: "Photos", icon: Image, count: stats.data?.photos_pending, show: true },
    { to: "/admin/reports", label: "Reports", icon: Flag, count: stats.data?.reports_open, show: true },
    { to: "/admin/support", label: "Support", icon: LifeBuoy, count: stats.data?.support_waiting, show: true },
    { to: "/admin/audit", label: "Audit log", icon: ScrollText, show: isAdmin },
    { to: "/admin/logs", label: "App logs", icon: Activity, show: isAdmin },
    { to: "/admin/staff", label: "Staff", icon: UserCog, show: isAdmin },
  ];

  const initials = (me.data.name ?? "S").split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase();
  return (
    <div className="pattern-soft min-h-screen bg-ivory font-sans text-ink lg:flex">
      <aside className="hero-rani relative flex shrink-0 flex-col overflow-hidden text-white lg:sticky lg:top-0 lg:h-screen lg:w-64">
        <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-gold-400/25 blur-3xl" />
        <div className="relative flex items-center gap-2.5 px-5 py-6">
          <span className="grid h-10 w-10 place-items-center rounded-xl bg-white/15 ring-1 ring-white/25">
            <Heart className="h-5 w-5 fill-gold-300 text-gold-300" />
          </span>
          <div>
            <p className="font-display text-lg font-semibold leading-tight text-white">Matrimony</p>
            <p className="text-[11px] font-semibold uppercase tracking-widest text-gold-200">Admin panel</p>
          </div>
        </div>
        <nav className="relative flex gap-1 overflow-x-auto px-3 pb-3 lg:flex-1 lg:flex-col lg:overflow-visible">
          {nav.filter((n) => n.show).map(({ to, label, icon: Icon, count }) => (
            <NavLink
              key={to}
              to={to}
              end={to === "/admin"}
              className={({ isActive }) =>
                cx(
                  "flex items-center gap-3 whitespace-nowrap rounded-2xl px-4 py-2.5 text-sm font-semibold transition",
                  isActive ? "bg-white text-brand-800 shadow-lg" : "text-white/80 hover:bg-white/10 hover:text-white",
                )
              }
            >
              <Icon className="h-[18px] w-[18px]" />
              <span className="flex-1">{label}</span>
              {!!count && <span className="rounded-full bg-gold-300 px-2 py-0.5 text-xs font-bold text-brand-950">{count}</span>}
            </NavLink>
          ))}
        </nav>
        <div className="relative m-3 hidden rounded-2xl bg-white/10 p-4 ring-1 ring-white/15 backdrop-blur lg:block">
          <div className="flex items-center gap-3">
            <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-gradient-to-br from-gold-300 to-gold-500 font-display font-semibold text-brand-950">{initials}</span>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-white">{me.data.name}</p>
              <p className="truncate text-xs text-white/60">{me.data.email}</p>
            </div>
          </div>
          <div className="mt-3 flex items-center justify-between">
            <span className="rounded-full bg-gold-300/20 px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wide text-gold-200">{me.data.role}</span>
            <button
              onClick={async () => {
                await admin.logout();
                navigate("/admin/login", { replace: true });
              }}
              className="flex items-center gap-1.5 text-xs font-semibold text-white/70 hover:text-white"
            >
              <LogOut className="h-3.5 w-3.5" /> Sign out
            </button>
          </div>
        </div>
      </aside>
      <main className="min-w-0 flex-1 px-4 py-6 sm:px-8 sm:py-10 2xl:px-12">{children}</main>
    </div>
  );
}
