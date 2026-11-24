import type { ReactNode } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { logout } from "../api/client";

const NAV = [
  { to: "/", label: "My Profile", ready: true },
  { to: "/matches", label: "Matches", ready: false },
  { to: "/interests", label: "Interests", ready: false },
  { to: "/messages", label: "Messages", ready: false },
];

export function Logo() {
  return (
    <span className="flex items-center gap-2 text-lg font-semibold text-brand-700">
      <span className="grid h-8 w-8 place-items-center rounded-lg bg-brand-600 text-white">♥</span>
      Matrimony
    </span>
  );
}

export default function AppShell({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center gap-6 px-4 py-3">
          <Logo />
          <nav className="flex flex-1 gap-1 overflow-x-auto">
            {NAV.map((n) =>
              n.ready ? (
                <NavLink
                  key={n.to}
                  to={n.to}
                  end
                  className={({ isActive }) =>
                    `whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium ${
                      isActive ? "bg-brand-50 text-brand-700" : "text-gray-600 hover:bg-gray-100"
                    }`
                  }
                >
                  {n.label}
                </NavLink>
              ) : (
                <span
                  key={n.to}
                  title="Coming soon"
                  className="flex cursor-not-allowed items-center gap-1.5 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium text-gray-400"
                >
                  {n.label}
                  <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[10px] uppercase tracking-wide">
                    Soon
                  </span>
                </span>
              ),
            )}
          </nav>
          <button
            className="whitespace-nowrap text-sm text-gray-600 hover:text-gray-900"
            onClick={async () => {
              await logout();
              navigate("/login", { replace: true });
            }}
          >
            Log out
          </button>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6 sm:py-8">{children}</main>
    </div>
  );
}
