import { Bot, X } from "lucide-react";
import { useEffect, useState } from "react";
import HelpChat, { hasTeamReply, useSupport } from "./HelpChat";
import { cx } from "./ui";

const SEEN_KEY = "help_bubble_seen";

function seen(): boolean {
  try {
    return localStorage.getItem(SEEN_KEY) === "1";
  } catch {
    return true;
  }
}

/**
 * Floating "Need help?" button on every member page. Opens the help chat in a panel
 * over the current page (full-screen sheet on phones). Shows a dot when the support
 * team has replied.
 */
export default function FloatingHelp() {
  const [open, setOpen] = useState(false);
  const [hint, setHint] = useState(() => !seen());
  const support = useSupport(true, open ? 30_000 : 60_000);
  const replied = hasTeamReply(support.data);

  useEffect(() => {
    if (!hint) return;
    const t = setTimeout(() => setHint(false), 9000);
    return () => clearTimeout(t);
  }, [hint]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  const toggle = () => {
    setOpen((o) => !o);
    setHint(false);
    try {
      localStorage.setItem(SEEN_KEY, "1");
    } catch {
      /* ignore */
    }
  };

  return (
    <>
      {open && (
        <div
          role="dialog"
          aria-label="Help & support"
          className={cx(
            "animate-rise fixed z-50 overflow-hidden bg-white shadow-2xl",
            // phones: full-screen sheet; larger screens: floating panel above the button
            "inset-0 sm:inset-auto sm:bottom-24 sm:right-6 sm:h-[min(640px,calc(100vh-8rem))] sm:w-[400px] sm:rounded-[2rem] sm:ring-1 sm:ring-line/70",
          )}
        >
          <HelpChat compact onClose={() => setOpen(false)} />
        </div>
      )}

      <div className={cx("fixed bottom-24 right-4 z-40 flex items-center gap-3 md:bottom-6 md:right-6", open && "max-sm:hidden")}>
        {(hint || replied) && !open && (
          <button
            onClick={toggle}
            className="animate-rise hidden rounded-full bg-white py-2 pl-4 pr-3 text-sm font-semibold text-ink shadow-xl ring-1 ring-line sm:block"
          >
            {replied ? "Our team replied to you 💬" : "Need help? Ask us 👋"}
          </button>
        )}
        <button
          onClick={toggle}
          aria-label={open ? "Close help" : "Open help chat"}
          title={open ? "Close help" : "Help & support"}
          className="group relative grid h-14 w-14 place-items-center rounded-full bg-gradient-to-br from-brand-500 to-brand-800 text-white shadow-glow ring-4 ring-white transition hover:scale-105 active:scale-95"
        >
          {!open && <span className="absolute inset-0 animate-ping rounded-full bg-brand-400/30 [animation-duration:2.5s]" />}
          {open ? <X className="h-6 w-6" /> : <Bot className="relative h-7 w-7 text-gold-200" />}
          {replied && !open && (
            <span className="absolute -right-0.5 -top-0.5 grid h-5 w-5 place-items-center rounded-full bg-gold-400 text-[10px] font-bold text-brand-950 ring-2 ring-white">
              1
            </span>
          )}
        </button>
      </div>
    </>
  );
}
