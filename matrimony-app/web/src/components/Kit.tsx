import { X, type LucideIcon } from "lucide-react";
import { useEffect, type ReactNode } from "react";
import { cx } from "./ui";

export function Modal({
  open,
  onClose,
  title,
  children,
  wide,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  wide?: boolean;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-6" role="dialog" aria-modal aria-label={title}>
      <div className="absolute inset-0 bg-brand-950/40 backdrop-blur-sm" onClick={onClose} />
      <div
        className={cx(
          "animate-rise relative flex max-h-[92vh] w-full flex-col overflow-hidden rounded-t-[2rem] bg-white shadow-2xl sm:rounded-[2rem]",
          wide ? "sm:max-w-2xl" : "sm:max-w-md",
        )}
      >
        <div className="flex items-center justify-between border-b border-line px-6 py-4">
          <h2 className="font-display text-xl font-semibold">{title}</h2>
          <button onClick={onClose} className="grid h-9 w-9 place-items-center rounded-full text-muted hover:bg-sand" aria-label="Close">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="overflow-y-auto p-6">{children}</div>
      </div>
    </div>
  );
}

export function Tabs<T extends string>({
  tabs,
  value,
  onChange,
}: {
  tabs: { value: T; label: string; count?: number; icon?: LucideIcon }[];
  value: T;
  onChange: (v: T) => void;
}) {
  return (
    <div className="flex gap-1 overflow-x-auto rounded-full bg-white p-1.5 shadow-soft ring-1 ring-line/70">
      {tabs.map(({ value: v, label, count, icon: Icon }) => (
        <button
          key={v}
          onClick={() => onChange(v)}
          className={cx(
            "flex flex-1 items-center justify-center gap-2 whitespace-nowrap rounded-full px-4 py-2.5 text-sm font-semibold transition",
            v === value ? "bg-gradient-to-r from-brand-600 to-brand-700 text-white shadow-glow" : "text-muted hover:text-ink",
          )}
        >
          {Icon && <Icon className="h-4 w-4" />}
          {label}
          {!!count && (
            <span className={cx("rounded-full px-1.5 text-xs", v === value ? "bg-white/25" : "bg-brand-100 text-brand-700")}>{count}</span>
          )}
        </button>
      ))}
    </div>
  );
}

export function Empty({ icon: Icon, title, text, action }: { icon: LucideIcon; title: string; text: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center rounded-3xl bg-white/70 px-6 py-16 text-center ring-1 ring-line/70">
      <span className="grid h-16 w-16 place-items-center rounded-3xl bg-gradient-to-br from-brand-50 to-gold-50 text-brand-500">
        <Icon className="h-8 w-8" />
      </span>
      <h3 className="mt-5 font-display text-xl font-semibold">{title}</h3>
      <p className="mt-2 max-w-sm text-sm text-muted">{text}</p>
      {action && <div className="mt-6">{action}</div>}
    </div>
  );
}

/** Toggleable chips for multi-select preferences. Empty selection = "Any". */
export function ChipSelect<T extends string | number>({
  options,
  value,
  onChange,
}: {
  options: { value: T; label: string }[];
  value: T[];
  onChange: (v: T[]) => void;
}) {
  const toggle = (v: T) => onChange(value.includes(v) ? value.filter((x) => x !== v) : [...value, v]);
  return (
    <div className="flex flex-wrap gap-2">
      <button
        type="button"
        onClick={() => onChange([])}
        className={cx("rounded-full px-3.5 py-1.5 text-sm font-medium ring-1 transition", value.length === 0 ? "bg-brand-600 text-white ring-brand-600" : "bg-white text-muted ring-line hover:ring-brand-200")}
      >
        Any
      </button>
      {options.map((o) => (
        <button
          type="button"
          key={o.value}
          onClick={() => toggle(o.value)}
          className={cx(
            "rounded-full px-3.5 py-1.5 text-sm font-medium ring-1 transition",
            value.includes(o.value) ? "bg-brand-50 text-brand-700 ring-brand-400" : "bg-white text-ink ring-line hover:ring-brand-200",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
