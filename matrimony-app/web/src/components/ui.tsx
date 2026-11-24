import type { LucideIcon } from "lucide-react";
import {
  useId,
  useRef,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from "react";

export const cx = (...c: (string | false | undefined | null)[]) => c.filter(Boolean).join(" ");

/* ---------------- Button ---------------- */
type Variant = "primary" | "secondary" | "ghost" | "gold";
export function Button({
  variant = "primary",
  size = "md",
  className,
  loading,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  size?: "sm" | "md" | "lg";
  loading?: boolean;
}) {
  return (
    <button
      {...props}
      disabled={props.disabled || loading}
      className={cx(
        "inline-flex items-center justify-center gap-2 rounded-full font-semibold transition-all duration-200",
        "focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-brand-200",
        "disabled:cursor-not-allowed disabled:opacity-50 disabled:shadow-none",
        size === "sm" && "px-3.5 py-1.5 text-sm",
        size === "md" && "px-5 py-2.5 text-sm",
        size === "lg" && "px-6 py-3.5 text-base",
        variant === "primary" &&
          "bg-gradient-to-r from-brand-600 to-brand-700 text-white shadow-glow hover:-translate-y-0.5 hover:from-brand-500 hover:to-brand-600 active:translate-y-0",
        variant === "gold" &&
          "bg-gradient-to-r from-gold-300 to-gold-400 text-brand-950 shadow-md hover:-translate-y-0.5 hover:from-gold-200 hover:to-gold-300",
        variant === "secondary" &&
          "bg-white text-ink ring-1 ring-line hover:bg-brand-50 hover:ring-brand-200",
        variant === "ghost" && "text-brand-700 hover:bg-brand-50",
        className,
      )}
    >
      {loading && (
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-r-transparent" />
      )}
      {children}
    </button>
  );
}

/* ---------------- Form fields ---------------- */
export function Field({
  label,
  hint,
  error,
  optional,
  children,
}: {
  label: string;
  hint?: string;
  error?: string;
  optional?: boolean;
  children: ReactNode;
}) {
  return (
    <label className="block">
      <span className="text-sm font-semibold text-ink">
        {label}
        {optional && <span className="ml-1.5 text-xs font-medium text-muted">optional</span>}
      </span>
      <div className="mt-2">{children}</div>
      {hint && !error && <p className="mt-1.5 text-xs leading-relaxed text-muted">{hint}</p>}
      {error && <p className="mt-1.5 text-xs text-red-600">{error}</p>}
    </label>
  );
}

const inputCls =
  "w-full rounded-2xl border-0 bg-white px-4 py-3 text-[15px] text-ink ring-1 ring-line placeholder:text-muted/60 " +
  "transition focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:bg-sand";

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={cx(inputCls, props.className)} />;
}

export function Textarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={cx(inputCls, "min-h-32 leading-relaxed", props.className)} />;
}

export function Select({
  options,
  placeholder = "Select",
  ...props
}: SelectHTMLAttributes<HTMLSelectElement> & {
  options: { value: string | number; label: string }[];
  placeholder?: string;
}) {
  return (
    <select {...props} className={cx(inputCls, "cursor-pointer", props.className)}>
      <option value="">{placeholder}</option>
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

/** +91 mobile number input */
export function PhoneInput({
  value,
  onChange,
  autoFocus,
}: {
  value: string;
  onChange: (v: string) => void;
  autoFocus?: boolean;
}) {
  return (
    <div className="flex items-center rounded-2xl bg-white ring-1 ring-line transition focus-within:ring-2 focus-within:ring-brand-500">
      <span className="flex items-center gap-1.5 border-r border-line py-3 pl-4 pr-3 text-[15px] font-medium text-muted">
        <span aria-hidden>🇮🇳</span> +91
      </span>
      <input
        className="w-full rounded-r-2xl bg-transparent px-3 py-3 text-[15px] font-medium tracking-wide outline-none placeholder:font-normal placeholder:text-muted/60"
        inputMode="numeric"
        autoComplete="tel-national"
        maxLength={10}
        value={value}
        autoFocus={autoFocus}
        onChange={(e) => onChange(e.target.value.replace(/\D/g, ""))}
        placeholder="98765 43210"
        aria-label="Mobile number"
      />
    </div>
  );
}

/** Six separate boxes; supports typing, backspace and pasting the whole code. */
export function OtpInput({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const refs = useRef<(HTMLInputElement | null)[]>([]);
  const id = useId();
  const digits = Array.from({ length: 6 }, (_, i) => value[i] ?? "");

  const setAt = (i: number, d: string) => {
    const next = digits.slice();
    next[i] = d;
    onChange(next.join("").slice(0, 6));
  };

  return (
    <div className="flex justify-between gap-2" role="group" aria-label="One-time password">
      {digits.map((d, i) => (
        <input
          key={i}
          id={`${id}-${i}`}
          ref={(el) => {
            refs.current[i] = el;
          }}
          className={cx(
            "h-14 w-full min-w-0 rounded-2xl bg-white text-center text-2xl font-semibold text-ink ring-1 transition",
            "focus:outline-none focus:ring-2 focus:ring-brand-500",
            d ? "ring-brand-300" : "ring-line",
          )}
          inputMode="numeric"
          autoComplete={i === 0 ? "one-time-code" : "off"}
          maxLength={1}
          value={d}
          autoFocus={i === 0}
          aria-label={`Digit ${i + 1}`}
          onChange={(e) => {
            const v = e.target.value.replace(/\D/g, "");
            if (v.length > 1) {
              // autofill / paste into one box
              onChange(v.slice(0, 6));
              refs.current[Math.min(v.length, 5)]?.focus();
              return;
            }
            setAt(i, v);
            if (v && i < 5) refs.current[i + 1]?.focus();
          }}
          onKeyDown={(e) => {
            if (e.key === "Backspace" && !d && i > 0) refs.current[i - 1]?.focus();
          }}
          onPaste={(e) => {
            const v = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
            if (v) {
              e.preventDefault();
              onChange(v);
              refs.current[Math.min(v.length, 5)]?.focus();
            }
          }}
        />
      ))}
    </div>
  );
}

/* ---------------- Surfaces ---------------- */
export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <section className={cx("rounded-3xl bg-white p-6 shadow-soft ring-1 ring-line/70 sm:p-7", className)}>
      {children}
    </section>
  );
}

type Tone = "gray" | "green" | "amber" | "red" | "brand" | "gold";
const toneCls: Record<Tone, string> = {
  gray: "bg-sand text-muted",
  green: "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100",
  amber: "bg-amber-50 text-amber-800 ring-1 ring-amber-100",
  red: "bg-red-50 text-red-700 ring-1 ring-red-100",
  brand: "bg-brand-50 text-brand-700 ring-1 ring-brand-100",
  gold: "bg-gold-50 text-gold-600 ring-1 ring-gold-100",
};

export function Badge({ tone = "gray", icon: Icon, children }: { tone?: Tone; icon?: LucideIcon; children: ReactNode }) {
  return (
    <span className={cx("inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold", toneCls[tone])}>
      {Icon && <Icon className="h-3.5 w-3.5" strokeWidth={2.5} />}
      {children}
    </span>
  );
}

const chipCls = {
  brand: "bg-brand-50 text-brand-600",
  gold: "bg-gold-50 text-gold-500",
  teal: "bg-teal-50 text-teal-600",
  violet: "bg-violet-50 text-violet-600",
  sky: "bg-sky-50 text-sky-600",
  rose: "bg-rose-50 text-rose-500",
};
export type ChipColor = keyof typeof chipCls;

export function IconChip({ icon: Icon, color = "brand", size = "md" }: { icon: LucideIcon; color?: ChipColor; size?: "md" | "lg" }) {
  return (
    <span className={cx("grid shrink-0 place-items-center rounded-2xl", chipCls[color], size === "md" ? "h-10 w-10" : "h-12 w-12")}>
      <Icon className={size === "md" ? "h-5 w-5" : "h-6 w-6"} strokeWidth={2} />
    </span>
  );
}

export function ErrorBox({ message }: { message?: string | null }) {
  if (!message) return null;
  return (
    <p role="alert" className="animate-rise rounded-2xl bg-red-50 px-4 py-3 text-sm font-medium text-red-700 ring-1 ring-red-100">
      {message}
    </p>
  );
}

/** Circular progress with a rani → marigold gradient. */
export function ProgressRing({ value, size = 112 }: { value: number; size?: number }) {
  const r = 46;
  const c = 2 * Math.PI * r;
  const v = Math.min(100, Math.max(0, value));
  const gid = useId();
  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg viewBox="0 0 100 100" className="-rotate-90" width={size} height={size}>
        <defs>
          <linearGradient id={gid} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#e2336b" />
            <stop offset="100%" stopColor="#f5a623" />
          </linearGradient>
        </defs>
        <circle cx="50" cy="50" r={r} fill="none" stroke="#f7efe8" strokeWidth="8" />
        <circle
          cx="50"
          cy="50"
          r={r}
          fill="none"
          stroke={`url(#${gid})`}
          strokeWidth="8"
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c - (v / 100) * c}
          className="transition-[stroke-dashoffset] duration-700"
        />
      </svg>
      <div className="absolute inset-0 grid place-items-center">
        <span className="font-display text-2xl font-semibold text-ink">
          {v}
          <span className="text-sm">%</span>
        </span>
      </div>
    </div>
  );
}

/** Convert "" from a <select>/<input> to null, numbers to numbers. */
export const toNum = (v: string) => (v === "" ? null : Number(v));
export const toStr = (v: string) => (v.trim() === "" ? null : v);
