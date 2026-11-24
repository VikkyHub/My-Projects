import { Heart, LogOut, MessageCircle, Send, Sparkles, UserRound, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { logout } from "../api/client";
import { useRealtime } from "../lib/realtime";
import { useCounts } from "../lib/social";
import { cx } from "./ui";

type Badge = "interests" | "messages";
const NAV: { to: string; label: string; icon: LucideIcon; ready: boolean; badge?: Badge }[] = [
  { to: "/matches", label: "Matches", icon: Sparkles, ready: true },
  { to: "/interests", label: "Interests", icon: Send, ready: true, badge: "interests" },
  { to: "/messages", label: "Messages", icon: MessageCircle, ready: true, badge: "messages" },
  { to: "/", label: "My Profile", icon: UserRound, ready: true },
];

export function Logo({ light = false }: { light?: boolean }) {
  return (
    <span className="flex items-center gap-2.5">
      <span
        className={cx(
          "grid h-9 w-9 place-items-center rounded-xl shadow-sm",
          light ? "bg-white/15 ring-1 ring-white/25" : "bg-gradient-to-br from-brand-500 to-brand-800",
        )}
      >
        <Heart className="h-[18px] w-[18px] fill-gold-300 text-gold-300" />
      </span>
      <span className={cx("font-display text-xl font-semibold tracking-tight", light ? "text-white" : "text-brand-800")}>
        Matrimony
      </span>
    </span>
  );
}

function NavItem({ n, mobile = false, count = 0 }: { n: (typeof NAV)[number]; mobile?: boolean; count?: number }) {
  const Icon = n.icon;
  const dot = count > 0 && (
    <span
      className={cx(
        "grid min-w-5 place-items-center rounded-full bg-brand-600 px-1.5 text-[10px] font-bold leading-5 text-white ring-2 ring-white",
        mobile && "absolute -top-1 left-1/2 ml-1.5",
      )}
    >
      {count > 99 ? "99+" : count}
    </span>
  );
  if (!n.ready) {
    return (
      <span
        title="Coming soon"
        className={cx(
          "relative flex cursor-not-allowed items-center text-muted/50",
          mobile ? "flex-1 flex-col gap-1 py-2 text-[11px] font-medium" : "gap-2 rounded-full px-4 py-2 text-sm font-medium",
        )}
      >
        <Icon className="h-5 w-5" />
        {n.label}
        {!mobile && (
          <span className="rounded-full bg-gold-50 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-gold-600">
            Soon
          </span>
        )}
      </span>
    );
  }
  return (
    <NavLink
      to={n.to}
      end={n.to === "/"}
      className={({ isActive }) =>
        cx(
          "relative flex items-center transition",
          mobile ? "flex-1 flex-col gap-1 py-2 text-[11px] font-semibold" : "gap-2 rounded-full px-4 py-2 text-sm font-semibold",
          isActive
            ? mobile
              ? "text-brand-600"
              : "bg-brand-50 text-brand-700"
            : "text-muted hover:text-ink",
        )
      }
    >
      <Icon className="h-5 w-5" />
      {n.label}
      {dot}
    </NavLink>
  );
}

export default function AppShell({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  useRealtime();
  const counts = useCounts();
  const countFor = (b?: Badge) =>
    b === "interests" ? counts.data?.received_pending : b === "messages" ? counts.data?.unread_messages : 0;
  return (
    <div className="pattern-soft min-h-screen pb-20 md:pb-0">
      <header className="sticky top-0 z-20 border-b border-line/70 bg-white/80 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl 2xl:max-w-[1440px] sm:px-6 items-center gap-6 px-4 py-3">
          <NavLink to="/matches" aria-label="Home">
            <Logo />
          </NavLink>
          <nav className="hidden flex-1 items-center gap-1 md:flex">
            {NAV.map((n) => (
              <NavItem key={n.to} n={n} count={countFor(n.badge)} />
            ))}
          </nav>
          <button
            className="ml-auto flex items-center gap-2 rounded-full px-3 py-2 text-sm font-semibold text-muted transition hover:bg-brand-50 hover:text-brand-700"
            onClick={async () => {
              await logout();
              navigate("/login", { replace: true });
            }}
          >
            <LogOut className="h-4 w-4" />
            <span className="hidden sm:inline">Log out</span>
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-7xl 2xl:max-w-[1440px] sm:px-6 px-4 py-6 sm:py-8">{children}</main>

      {/* Mobile bottom tab bar */}
      <nav className="fixed inset-x-0 bottom-0 z-20 flex border-t border-line bg-white/95 px-2 pb-[env(safe-area-inset-bottom)] backdrop-blur-xl md:hidden">
        {NAV.map((n) => (
          <NavItem key={n.to} n={n} mobile count={countFor(n.badge)} />
        ))}
      </nav>
    </div>
  );
}
