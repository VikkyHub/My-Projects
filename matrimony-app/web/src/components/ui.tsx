import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";

const cx = (...c: (string | false | undefined | null)[]) => c.filter(Boolean).join(" ");

type Variant = "primary" | "secondary" | "ghost";
export function Button({
  variant = "primary",
  className,
  loading,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; loading?: boolean }) {
  return (
    <button
      {...props}
      disabled={props.disabled || loading}
      className={cx(
        "inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-600 focus-visible:ring-offset-2",
        "disabled:cursor-not-allowed disabled:opacity-50",
        variant === "primary" && "bg-brand-600 text-white hover:bg-brand-700",
        variant === "secondary" && "border border-gray-300 bg-white text-gray-800 hover:bg-gray-50",
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
      <span className="text-sm font-medium text-gray-800">
        {label}
        {optional && <span className="ml-1 font-normal text-gray-400">(optional)</span>}
      </span>
      <div className="mt-1.5">{children}</div>
      {hint && !error && <p className="mt-1 text-xs text-gray-500">{hint}</p>}
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </label>
  );
}

const inputCls =
  "w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5 text-sm text-gray-900 placeholder:text-gray-400 " +
  "focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20 disabled:bg-gray-50";

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={cx(inputCls, props.className)} />;
}

export function Textarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={cx(inputCls, "min-h-28", props.className)} />;
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
    <select {...props} className={cx(inputCls, "appearance-auto", props.className)}>
      <option value="">{placeholder}</option>
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <section className={cx("rounded-2xl border border-gray-200 bg-white p-5 sm:p-6", className)}>
      {children}
    </section>
  );
}

export function Badge({
  tone = "gray",
  children,
}: {
  tone?: "gray" | "green" | "amber" | "red" | "brand";
  children: ReactNode;
}) {
  return (
    <span
      className={cx(
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
        tone === "gray" && "bg-gray-100 text-gray-700",
        tone === "green" && "bg-green-50 text-green-700",
        tone === "amber" && "bg-amber-50 text-amber-800",
        tone === "red" && "bg-red-50 text-red-700",
        tone === "brand" && "bg-brand-50 text-brand-700",
      )}
    >
      {children}
    </span>
  );
}

export function ErrorBox({ message }: { message?: string | null }) {
  if (!message) return null;
  return (
    <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
      {message}
    </p>
  );
}

export function Progress({ value }: { value: number }) {
  return (
    <div className="h-2 w-full overflow-hidden rounded-full bg-gray-100">
      <div
        className="h-full rounded-full bg-brand-600 transition-all"
        style={{ width: `${Math.min(100, Math.max(0, value))}%` }}
      />
    </div>
  );
}

/** Convert "" from a <select>/<input> to null, numbers to numbers. */
export const toNum = (v: string) => (v === "" ? null : Number(v));
export const toStr = (v: string) => (v.trim() === "" ? null : v);
