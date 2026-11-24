import { Briefcase, GraduationCap, Heart, MapPin, Sparkles } from "lucide-react";
import { Link } from "react-router-dom";
import type { ProfileCard } from "../api/types";
import { heightLabel } from "../lib/labels";
import { useShortlist } from "../lib/social";
import Avatar from "./Avatar";
import InterestAction from "./InterestAction";
import { cx } from "./ui";

export default function MatchCard({ p }: { p: ProfileCard }) {
  const shortlist = useShortlist();
  return (
    <article className="group animate-rise flex flex-col overflow-hidden rounded-3xl bg-white shadow-soft ring-1 ring-line/70 transition hover:-translate-y-1 hover:shadow-xl">
      <Link to={`/p/${p.public_id}`} className="relative block">
        <Avatar name={p.name} seed={p.public_id} photo={p.photo_url} locked={p.photo_locked} rounded="rounded-none" className="aspect-[4/3] w-full" text="text-5xl" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-brand-950/70 to-transparent" />
        <div className="absolute bottom-3 left-4 right-4 text-white">
          <h3 className="font-display text-xl font-semibold leading-tight text-white drop-shadow">
            {p.name}, {p.age}
          </h3>
          {p.last_active && (
            <p className="flex items-center gap-1.5 text-xs font-medium text-white/85">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" /> {p.last_active}
            </p>
          )}
        </div>
        {p.match_score != null && (
          <span className="absolute left-3 top-3 flex items-center gap-1 rounded-full bg-white/95 px-2.5 py-1 text-xs font-bold text-brand-700 shadow">
            <Sparkles className="h-3.5 w-3.5 text-gold-500" /> {p.match_score}% match
          </span>
        )}
        {p.is_premium && (
          <span className="absolute right-3 top-3 rounded-full bg-gradient-to-r from-gold-300 to-gold-400 px-2.5 py-1 text-xs font-bold text-brand-950 shadow">
            Premium
          </span>
        )}
      </Link>

      <div className="flex flex-1 flex-col p-5">
        <p className="text-sm text-muted">
          {[heightLabel(p.height_cm)?.split(" (")[0], p.community ?? p.religion, p.mother_tongue].filter(Boolean).join(" · ")}
        </p>
        <ul className="mt-3 space-y-1.5 text-sm text-ink/85">
          {p.city && (
            <li className="flex items-center gap-2">
              <MapPin className="h-4 w-4 shrink-0 text-brand-400" /> {p.city}
              {p.state ? `, ${p.state}` : ""}
            </li>
          )}
          {p.occupation && (
            <li className="flex items-center gap-2">
              <Briefcase className="h-4 w-4 shrink-0 text-gold-500" /> {p.occupation}
            </li>
          )}
          {p.education && (
            <li className="flex items-center gap-2">
              <GraduationCap className="h-4 w-4 shrink-0 text-violet-500" /> {p.education}
            </li>
          )}
        </ul>
        {p.match_reasons.length > 0 && (
          <div className="mt-4 flex flex-wrap gap-1.5">
            {p.match_reasons.map((r) => (
              <span key={r} className="rounded-full bg-brand-50 px-2.5 py-1 text-xs font-semibold text-brand-700">
                {r}
              </span>
            ))}
          </div>
        )}
        <div className="mt-auto flex items-center gap-2 pt-5">
          <div className="flex-1">
            <InterestAction p={p} size="sm" full />
          </div>
          <button
            onClick={() => shortlist.mutate(p)}
            aria-label={p.shortlisted ? "Remove from shortlist" : "Shortlist"}
            className={cx(
              "grid h-9 w-9 shrink-0 place-items-center rounded-full ring-1 transition",
              p.shortlisted ? "bg-brand-50 text-brand-600 ring-brand-200" : "text-muted ring-line hover:text-brand-600 hover:ring-brand-200",
            )}
          >
            <Heart className={cx("h-4 w-4", p.shortlisted && "fill-brand-500")} />
          </button>
        </div>
      </div>
    </article>
  );
}
