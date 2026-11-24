import { useMutation, useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  Ban,
  Briefcase,
  Flag,
  Heart,
  Home as HomeIcon,
  Lock,
  MapPin,
  MoonStar,
  MoreHorizontal,
  Sparkles,
  UserRound,
} from "lucide-react";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ApiError, api, mediaUrl } from "../api/client";
import type { PublicProfile } from "../api/types";
import AppShell from "../components/AppShell";
import Avatar from "../components/Avatar";
import InterestAction from "../components/InterestAction";
import { Empty, Modal } from "../components/Kit";
import { Facts } from "../components/Section";
import { Badge, Button, Card, ErrorBox, Field, IconChip, Select, Textarea, cx } from "../components/ui";
import {
  DIET,
  EMPLOYED_IN,
  FAMILY_STATUS,
  FAMILY_TYPE,
  FAMILY_VALUES,
  HABIT,
  INCOME_BANDS,
  MANGLIK,
  MARITAL,
  heightLabel,
} from "../lib/labels";
import { useRefreshSocial, useShortlist } from "../lib/social";

const lbl = (m: Record<string, string>, v?: string | null) => (v ? m[v] : undefined);
const REASONS = {
  fake: "Fake profile / not a real person",
  married: "Already married",
  harassment: "Harassment or abusive behaviour",
  scam_money: "Asked for money",
  dowry: "Dowry demand",
  obscene: "Obscene content",
  underage: "Looks under-age",
  other: "Something else",
};

export default function ProfileView() {
  const { publicId = "" } = useParams();
  const navigate = useNavigate();
  const q = useQuery({ queryKey: ["public", publicId], queryFn: () => api<PublicProfile>(`/profiles/${publicId}`), retry: false });
  const shortlist = useShortlist();
  const [photo, setPhoto] = useState(0);
  const [menu, setMenu] = useState(false);
  const [reporting, setReporting] = useState(false);
  const refresh = useRefreshSocial();
  const block = useMutation({
    mutationFn: () => api(`/profiles/${publicId}/block`, { method: "POST" }),
    onSuccess: () => {
      refresh();
      navigate("/matches", { replace: true });
    },
  });

  if (q.error)
    return (
      <AppShell>
        <Empty
          icon={UserRound}
          title={q.error instanceof ApiError && q.error.status === 404 ? "Profile not available" : "Couldn't load profile"}
          text={q.error.message}
          action={<Button variant="secondary" onClick={() => navigate(-1)}>Go back</Button>}
        />
      </AppShell>
    );
  if (!q.data)
    return (
      <AppShell>
        <div className="h-[32rem] animate-pulse rounded-[2rem] bg-white/70" />
      </AppShell>
    );

  const p = q.data;
  const accepted = p.interest?.status === "accepted";

  return (
    <AppShell>
      <button onClick={() => navigate(-1)} className="mb-4 flex items-center gap-1.5 text-sm font-semibold text-muted hover:text-brand-700">
        <ArrowLeft className="h-4 w-4" /> Back
      </button>

      <div className="grid gap-6 lg:grid-cols-[400px_1fr] xl:grid-cols-[440px_1fr]">
        {/* Photos + action */}
        <aside className="space-y-4 lg:sticky lg:top-24 lg:self-start">
          <div className="overflow-hidden rounded-[2rem] bg-white shadow-soft ring-1 ring-line/70">
            <div className="relative">
              {p.photos.length ? (
                <img src={mediaUrl(p.photos[photo])} alt={p.name} className={cx("aspect-[4/5] w-full object-cover", p.photo_locked && "scale-105")} />
              ) : (
                <Avatar name={p.name} seed={p.public_id} rounded="rounded-none" className="aspect-[4/5] w-full" text="text-7xl" />
              )}
              {p.photo_locked && (
                <div className="absolute inset-0 grid place-items-center bg-brand-950/30 p-8 text-center text-white">
                  <div>
                    <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-white/90 text-brand-700">
                      <Lock className="h-6 w-6" />
                    </span>
                    <p className="mt-3 font-semibold">Photos are private</p>
                    <p className="text-sm text-white/80">{p.first_name} shares photos once you're connected.</p>
                  </div>
                </div>
              )}
              {p.match_score != null && (
                <span className="absolute left-4 top-4 flex items-center gap-1 rounded-full bg-white/95 px-3 py-1.5 text-sm font-bold text-brand-700 shadow">
                  <Sparkles className="h-4 w-4 text-gold-500" /> {p.match_score}% match
                </span>
              )}
            </div>
            {p.photos.length > 1 && !p.photo_locked && (
              <div className="flex gap-2 p-3">
                {p.photos.map((u, i) => (
                  <button key={u} onClick={() => setPhoto(i)} className={cx("h-16 w-14 overflow-hidden rounded-xl ring-2", i === photo ? "ring-brand-500" : "ring-transparent opacity-70")}>
                    <img src={mediaUrl(u)} alt="" className="h-full w-full object-cover" />
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="flex gap-2">
            <div className="flex-1">
              <InterestAction p={p} full />
            </div>
            <Button variant="secondary" aria-label="Shortlist" onClick={() => shortlist.mutate(p)}>
              <Heart className={cx("h-4 w-4", p.shortlisted && "fill-brand-500 text-brand-600")} />
            </Button>
            <div className="relative">
              <Button variant="secondary" aria-label="More" onClick={() => setMenu((m) => !m)}>
                <MoreHorizontal className="h-4 w-4" />
              </Button>
              {menu && (
                <div className="absolute bottom-12 right-0 z-10 w-48 overflow-hidden rounded-2xl bg-white py-1 shadow-xl ring-1 ring-line">
                  <button className="flex w-full items-center gap-2 px-4 py-2.5 text-sm font-medium hover:bg-sand" onClick={() => { setMenu(false); setReporting(true); }}>
                    <Flag className="h-4 w-4 text-gold-500" /> Report profile
                  </button>
                  <button
                    className="flex w-full items-center gap-2 px-4 py-2.5 text-sm font-medium text-red-600 hover:bg-red-50"
                    onClick={() => {
                      setMenu(false);
                      if (confirm(`Block ${p.first_name}? You won't see each other anywhere.`)) block.mutate();
                    }}
                  >
                    <Ban className="h-4 w-4" /> Block
                  </button>
                </div>
              )}
            </div>
          </div>
        </aside>

        {/* Details */}
        <div className="space-y-6">
          <Card>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h1 className="font-display text-3xl font-semibold sm:text-4xl">{p.name}</h1>
                <p className="mt-1 flex flex-wrap items-center gap-x-2 text-[15px] text-muted">
                  {p.age} yrs · {heightLabel(p.height_cm)?.split(" (")[0]} · {MARITAL[p.marital_status]}
                  {p.city && (
                    <span className="inline-flex items-center gap-1">
                      · <MapPin className="h-4 w-4 text-brand-500" /> {p.city}, {p.state}
                    </span>
                  )}
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                {p.is_premium && <Badge tone="gold">Premium</Badge>}
                {p.last_active && <Badge tone="green">{p.last_active}</Badge>}
                <Badge tone="gray">{p.public_id}</Badge>
              </div>
            </div>
            {p.match_reasons.length > 0 && (
              <div className="mt-4 flex flex-wrap gap-2">
                {p.match_reasons.map((r) => (
                  <span key={r} className="rounded-full bg-brand-50 px-3 py-1 text-sm font-semibold text-brand-700">{r}</span>
                ))}
              </div>
            )}
            {p.about_full && (
              <p className="mt-5 rounded-2xl bg-sand/50 p-5 font-display text-lg italic leading-relaxed text-ink/85">“{p.about_full}”</p>
            )}
            {p.created_by !== "self" && <p className="mt-4 text-sm text-muted">Profile managed by their {p.created_by}.</p>}
          </Card>

          <Block title="Basics" icon={UserRound}>
            <Facts items={[
              ["Religion", p.religion], ["Community", p.community], ["Mother tongue", p.mother_tongue],
              ["Diet", lbl(DIET, p.diet)], ["Smoking", lbl(HABIT, p.smoke)], ["Drinking", lbl(HABIT, p.drink)],
            ]} />
          </Block>

          {p.career && (
            <Block title="Education & career" icon={Briefcase} color="gold">
              <Facts items={[
                ["Education", p.career.education], ["Degree", p.career.education_detail], ["College", p.career.college],
                ["Occupation", p.career.occupation], ["Employed in", lbl(EMPLOYED_IN, p.career.employed_in)],
                ["Annual income", p.career.annual_income_band != null ? INCOME_BANDS[p.career.annual_income_band] : undefined],
              ]} />
            </Block>
          )}

          {p.family && (
            <Block title="Family" icon={HomeIcon} color="teal">
              <Facts items={[
                ["Father", p.family.father_occupation], ["Mother", p.family.mother_occupation],
                ["Brothers", p.family.brothers != null ? `${p.family.brothers} (${p.family.brothers_married ?? 0} married)` : undefined],
                ["Sisters", p.family.sisters != null ? `${p.family.sisters} (${p.family.sisters_married ?? 0} married)` : undefined],
                ["Family type", lbl(FAMILY_TYPE, p.family.family_type)], ["Family status", lbl(FAMILY_STATUS, p.family.family_status)],
                ["Family values", lbl(FAMILY_VALUES, p.family.family_values)], ["Native place", p.family.native_place],
              ]} />
            </Block>
          )}

          {(p.horoscope || p.horoscope_locked) && (
            <Block title="Horoscope" icon={MoonStar} color="violet">
              {p.horoscope ? (
                <Facts items={[
                  ["Rashi", p.horoscope.rashi], ["Nakshatra", p.horoscope.nakshatra], ["Manglik", lbl(MANGLIK, p.horoscope.manglik)],
                  ["Time of birth", p.horoscope.birth_time], ["Place of birth", p.horoscope.birth_place], ["Gotra", p.horoscope.gotra],
                ]} />
              ) : (
                <p className="flex items-center gap-2 rounded-2xl bg-sand/60 px-4 py-3 text-sm text-muted">
                  <Lock className="h-4 w-4" /> {p.first_name} shares horoscope details {accepted ? "" : "after you're connected"}.
                </p>
              )}
            </Block>
          )}

          <p className="text-center text-xs text-muted">
            Contact details are never shown on profiles. <Link to="/" className="font-semibold text-brand-700">Stay safe tips</Link>
          </p>
        </div>
      </div>

      <ReportModal open={reporting} onClose={() => setReporting(false)} publicId={p.public_id} name={p.first_name} />
    </AppShell>
  );
}

function Block({ title, icon, color = "brand", children }: { title: string; icon: typeof UserRound; color?: "brand" | "gold" | "teal" | "violet"; children: React.ReactNode }) {
  return (
    <Card>
      <div className="mb-5 flex items-center gap-3">
        <IconChip icon={icon} color={color} />
        <h2 className="font-display text-lg font-semibold">{title}</h2>
      </div>
      {children}
    </Card>
  );
}

export function ReportModal({ open, onClose, publicId, name, messageId }: { open: boolean; onClose: () => void; publicId: string; name: string; messageId?: number }) {
  const [reason, setReason] = useState("");
  const [details, setDetails] = useState("");
  const send = useMutation({
    mutationFn: () => api(`/profiles/${publicId}/report`, { method: "POST", body: JSON.stringify({ reason, details: details || null, message_id: messageId ?? null }) }),
  });
  return (
    <Modal open={open} onClose={onClose} title={`Report ${name}`}>
      {send.isSuccess ? (
        <div className="text-center">
          <p className="font-display text-xl font-semibold">Thank you</p>
          <p className="mt-2 text-sm text-muted">Our safety team will review this. You can also block {name} so they can't contact you.</p>
          <Button className="mt-6" onClick={onClose}>Done</Button>
        </div>
      ) : (
        <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); send.mutate(); }}>
          <Field label="What's wrong?">
            <Select value={reason} onChange={(e) => setReason(e.target.value)} options={Object.entries(REASONS).map(([value, label]) => ({ value, label }))} />
          </Field>
          <Field label="Details" optional>
            <Textarea value={details} onChange={(e) => setDetails(e.target.value)} placeholder="Anything that helps us review faster" />
          </Field>
          <ErrorBox message={send.error?.message} />
          <Button type="submit" className="w-full" disabled={!reason} loading={send.isPending}>Submit report</Button>
        </form>
      )}
    </Modal>
  );
}
