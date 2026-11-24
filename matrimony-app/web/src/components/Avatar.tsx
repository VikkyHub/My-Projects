import { Crown, Lock } from "lucide-react";
import { mediaUrl } from "../api/client";
import { cx } from "./ui";

const GRADS = [
  "from-brand-400 to-brand-700",
  "from-gold-300 to-gold-600",
  "from-violet-400 to-violet-700",
  "from-teal-400 to-teal-700",
  "from-rose-400 to-rose-700",
  "from-sky-400 to-sky-700",
];

function grad(seed: string) {
  let h = 0;
  for (const c of seed) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return GRADS[h % GRADS.length];
}

/** Photo if available (blurred + lock when private), else a gradient monogram. */
export default function Avatar({
  name,
  seed,
  photo,
  locked,
  premium,
  className,
  rounded = "rounded-full",
  text = "text-xl",
}: {
  name: string;
  seed: string;
  photo?: string | null;
  locked?: boolean;
  premium?: boolean;
  className?: string;
  rounded?: string;
  text?: string;
}) {
  const initials = name
    .split(" ")
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
  return (
    <div className={cx("relative shrink-0 overflow-hidden", rounded, className)}>
      {photo ? (
        <img src={mediaUrl(photo)} alt={name} loading="lazy" className="h-full w-full object-cover" />
      ) : (
        <div className={cx("grid h-full w-full place-items-center bg-gradient-to-br font-display font-semibold text-white", grad(seed), text)}>
          {initials}
        </div>
      )}
      {locked && (
        <div className="absolute inset-0 grid place-items-center bg-brand-950/20">
          <span className="grid h-9 w-9 place-items-center rounded-full bg-white/90 text-brand-700 shadow">
            <Lock className="h-4 w-4" />
          </span>
        </div>
      )}
      {premium && (
        <span className="absolute right-1.5 top-1.5 grid h-6 w-6 place-items-center rounded-full bg-gradient-to-br from-gold-300 to-gold-500 text-white shadow ring-2 ring-white">
          <Crown className="h-3.5 w-3.5" />
        </span>
      )}
    </div>
  );
}
