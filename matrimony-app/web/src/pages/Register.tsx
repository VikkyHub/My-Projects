import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ClipboardCheck,
  Flower2,
  HandHeart,
  Landmark,
  MapPin,
  ShieldCheck,
  Smile,
  UserRound,
  Users,
  UsersRound,
  type LucideIcon,
} from "lucide-react";
import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";
import type { CreatedBy, Gender, MaritalStatus, MyProfile } from "../api/types";
import { Logo } from "../components/AppShell";
import { Button, ErrorBox, Field, IconChip, Input, PhoneInput, Select, cx, toNum } from "../components/ui";
import { CREATED_BY, HEIGHTS, MARITAL, heightLabel, options } from "../lib/labels";
import { nameOf, useCities, useCommunities, useMotherTongues, useReligions, useSubCommunities } from "../lib/master";

interface Form {
  created_by: CreatedBy | "";
  candidate_phone: string;
  first_name: string;
  last_name: string;
  gender: Gender | "";
  dob: string;
  marital_status: MaritalStatus;
  has_children: boolean;
  religion_id: number | null;
  community_id: number | null;
  sub_community_id: number | null;
  mother_tongue_id: number | null;
  city_id: number | null;
  height_cm: number | null;
  accept_terms: boolean;
}

const STEPS: { title: string; icon: LucideIcon }[] = [
  { title: "Profile for", icon: Users },
  { title: "Basic details", icon: UserRound },
  { title: "Community", icon: Landmark },
  { title: "Location", icon: MapPin },
  { title: "Review", icon: ClipboardCheck },
];

const WHO_ICON: Record<CreatedBy, LucideIcon> = {
  self: UserRound,
  parent: UsersRound,
  sibling: Users,
  relative: HandHeart,
  friend: Smile,
};

function maxDob(gender: Gender | "") {
  const d = new Date();
  d.setFullYear(d.getFullYear() - (gender === "male" ? 21 : 18));
  return d.toISOString().slice(0, 10);
}

function ChoiceCard({
  selected,
  onClick,
  icon,
  title,
  hint,
}: {
  selected: boolean;
  onClick: () => void;
  icon: LucideIcon;
  title: string;
  hint?: string;
}) {
  const Icon = icon;
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={selected}
      className={cx(
        "group relative flex items-center gap-4 rounded-2xl p-4 text-left ring-1 transition-all",
        selected
          ? "bg-brand-50 ring-2 ring-brand-500 shadow-glow/20"
          : "bg-white ring-line hover:-translate-y-0.5 hover:ring-brand-200 hover:shadow-soft",
      )}
    >
      <span
        className={cx(
          "grid h-12 w-12 shrink-0 place-items-center rounded-2xl transition",
          selected ? "bg-brand-600 text-white" : "bg-brand-50 text-brand-600 group-hover:bg-brand-100",
        )}
      >
        <Icon className="h-6 w-6" />
      </span>
      <span>
        <span className="block font-semibold text-ink">{title}</span>
        {hint && <span className="block text-sm text-muted">{hint}</span>}
      </span>
      {selected && (
        <span className="absolute right-3 top-3 grid h-5 w-5 place-items-center rounded-full bg-brand-600 text-white">
          <Check className="h-3 w-3" strokeWidth={3} />
        </span>
      )}
    </button>
  );
}

export default function Register() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [step, setStep] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [f, setF] = useState<Form>({
    created_by: "",
    candidate_phone: "",
    first_name: "",
    last_name: "",
    gender: "",
    dob: "",
    marital_status: "never_married",
    has_children: false,
    religion_id: null,
    community_id: null,
    sub_community_id: null,
    mother_tongue_id: null,
    city_id: null,
    height_cm: null,
    accept_terms: false,
  });
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((s) => ({ ...s, [k]: v }));

  const religions = useReligions();
  const communities = useCommunities(f.religion_id);
  const subs = useSubCommunities(f.community_id);
  const tongues = useMotherTongues();
  const cities = useCities();

  const isSelf = f.created_by === "self";
  const subject = isSelf ? "your" : "their";

  const cityGroups = useMemo(() => {
    const g: Record<string, { id: number; name: string }[]> = {};
    for (const c of cities.data ?? []) (g[c.state] ??= []).push(c);
    return g;
  }, [cities.data]);

  function validate(): string | null {
    if (step === 0) {
      if (!f.created_by) return "Please choose who this profile is for.";
      if (!isSelf && !/^[6-9]\d{9}$/.test(f.candidate_phone)) return "Enter the candidate's 10-digit mobile number.";
    }
    if (step === 1) {
      if (!f.first_name.trim()) return "Please enter the first name.";
      if (!f.gender) return "Please choose bride or groom.";
      if (!f.dob) return "Please enter the date of birth.";
      if (f.dob > maxDob(f.gender)) return `Minimum age is ${f.gender === "male" ? 21 : 18} years.`;
    }
    if (step === 2) {
      if (!f.religion_id) return "Please choose a religion.";
      if ((communities.data?.length ?? 0) > 0 && !f.community_id) return "Please choose a community.";
      if (!f.mother_tongue_id) return "Please choose a mother tongue.";
    }
    if (step === 3) {
      if (!f.city_id) return "Please choose a city.";
      if (!f.height_cm) return "Please choose a height.";
    }
    if (step === 4 && !f.accept_terms) return "Please accept the Terms and Privacy Policy.";
    return null;
  }

  const create = useMutation({
    mutationFn: () =>
      api<MyProfile>("/profiles", {
        method: "POST",
        body: JSON.stringify({
          ...f,
          candidate_phone: isSelf ? null : `+91${f.candidate_phone}`,
          last_name: f.last_name.trim() || null,
          has_children: f.marital_status === "never_married" ? false : f.has_children,
        }),
      }),
    onSuccess: (p) => {
      qc.setQueryData(["profile", "me"], p);
      navigate("/", { replace: true });
    },
    onError: (e) => setError(e.message),
  });

  function next() {
    const err = validate();
    setError(err);
    if (err) return;
    if (step === STEPS.length - 1) create.mutate();
    else setStep(step + 1);
  }

  const back = () => {
    setError(null);
    setStep(step - 1);
  };

  return (
    <div className="pattern-soft min-h-screen">
      {/* Decorative header band */}
      <div className="hero-rani relative overflow-hidden pb-28">
        <div className="pointer-events-none absolute -right-20 -top-20 h-72 w-72 rounded-full bg-gold-400/25 blur-3xl" />
        <div className="relative mx-auto max-w-3xl px-5 pt-5">
          <Logo light />
          <h1 className="mt-10 font-display text-3xl font-semibold text-white sm:text-4xl">Let's create your profile</h1>
          <p className="mt-2 text-white/70">Just 5 quick steps — you can add photos and more details after.</p>
        </div>
      </div>

      <main className="relative mx-auto -mt-20 max-w-3xl px-5 pb-16">
        <div className="rounded-[2rem] bg-white shadow-soft ring-1 ring-line/70">
          {/* Stepper */}
          <ol className="flex items-start justify-between gap-1 border-b border-line px-5 py-6 sm:px-8">
            {STEPS.map((s, i) => {
              const done = i < step;
              const active = i === step;
              const Icon = s.icon;
              return (
                <li key={s.title} className="relative flex flex-1 flex-col items-center">
                  {i > 0 && (
                    <span
                      className={cx(
                        "absolute right-1/2 top-5 h-0.5 w-full -translate-y-1/2",
                        i <= step ? "bg-brand-500" : "bg-line",
                      )}
                    />
                  )}
                  <span
                    className={cx(
                      "relative z-10 grid h-10 w-10 place-items-center rounded-full ring-4 ring-white transition-all",
                      done && "bg-brand-600 text-white",
                      active && "bg-gradient-to-br from-brand-500 to-brand-700 text-white shadow-glow",
                      !done && !active && "bg-sand text-muted",
                    )}
                  >
                    {done ? <Check className="h-5 w-5" strokeWidth={3} /> : <Icon className="h-[18px] w-[18px]" />}
                  </span>
                  <span
                    className={cx(
                      "mt-2 hidden text-center text-xs sm:block",
                      active ? "font-semibold text-brand-700" : "font-medium text-muted",
                    )}
                  >
                    {s.title}
                  </span>
                </li>
              );
            })}
          </ol>

          <form
            key={step}
            className="animate-rise space-y-6 p-6 sm:p-8"
            onSubmit={(e) => {
              e.preventDefault();
              next();
            }}
          >
            <p className="text-xs font-bold uppercase tracking-widest text-gold-500">
              Step {step + 1} of {STEPS.length}
            </p>

            {step === 0 && (
              <>
                <h2 className="-mt-3 font-display text-2xl font-semibold">Who is this profile for?</h2>
                <div className="grid gap-3 sm:grid-cols-2">
                  {CREATED_BY.map((o) => (
                    <ChoiceCard
                      key={o.value}
                      selected={f.created_by === o.value}
                      onClick={() => set("created_by", o.value)}
                      icon={WHO_ICON[o.value]}
                      title={o.label}
                      hint={o.hint}
                    />
                  ))}
                </div>
                {f.created_by && !isSelf && (
                  <div className="animate-rise rounded-3xl bg-gradient-to-br from-gold-50 to-brand-50 p-5 ring-1 ring-gold-100">
                    <div className="mb-4 flex gap-3">
                      <IconChip icon={ShieldCheck} color="gold" />
                      <p className="text-sm leading-relaxed text-ink/80">
                        <span className="font-semibold text-ink">Consent matters.</span> We'll send the candidate an
                        OTP, and the profile stays hidden until they confirm it themselves.
                      </p>
                    </div>
                    <Field label="Candidate's own mobile number">
                      <PhoneInput value={f.candidate_phone} onChange={(v) => set("candidate_phone", v)} />
                    </Field>
                  </div>
                )}
              </>
            )}

            {step === 1 && (
              <>
                <h2 className="-mt-3 font-display text-2xl font-semibold">
                  {isSelf ? "Tell us about yourself" : "Tell us about them"}
                </h2>
                <div className="grid grid-cols-2 gap-3">
                  <ChoiceCard selected={f.gender === "female"} onClick={() => set("gender", "female")} icon={Flower2} title="Bride" hint="Female" />
                  <ChoiceCard selected={f.gender === "male"} onClick={() => set("gender", "male")} icon={UserRound} title="Groom" hint="Male" />
                </div>
                <div className="grid gap-5 sm:grid-cols-2">
                  <Field label="First name">
                    <Input value={f.first_name} onChange={(e) => set("first_name", e.target.value)} placeholder="e.g. Priya" />
                  </Field>
                  <Field label="Last name" optional hint="Free members see only the initial">
                    <Input value={f.last_name} onChange={(e) => set("last_name", e.target.value)} placeholder="e.g. Sharma" />
                  </Field>
                  <Field label="Date of birth" hint="Can't be changed later">
                    <Input type="date" value={f.dob} max={maxDob(f.gender)} min="1946-01-01" onChange={(e) => set("dob", e.target.value)} />
                  </Field>
                  <Field label="Marital status">
                    <Select value={f.marital_status} placeholder="" onChange={(e) => set("marital_status", e.target.value as MaritalStatus)} options={options(MARITAL)} />
                  </Field>
                </div>
                {f.marital_status !== "never_married" && (
                  <label className="flex items-center gap-3 rounded-2xl bg-sand/60 p-4 text-sm font-medium">
                    <input type="checkbox" className="h-4 w-4 accent-brand-600" checked={f.has_children} onChange={(e) => set("has_children", e.target.checked)} />
                    Has children
                  </label>
                )}
              </>
            )}

            {step === 2 && (
              <>
                <h2 className="-mt-3 font-display text-2xl font-semibold">Religion & community</h2>
                <div className="grid gap-5 sm:grid-cols-2">
                  <Field label="Religion">
                    <Select
                      value={f.religion_id ?? ""}
                      onChange={(e) => setF((s) => ({ ...s, religion_id: toNum(e.target.value), community_id: null, sub_community_id: null }))}
                      options={(religions.data ?? []).map((r) => ({ value: r.id, label: r.name }))}
                    />
                  </Field>
                  <Field label="Mother tongue">
                    <Select
                      value={f.mother_tongue_id ?? ""}
                      onChange={(e) => set("mother_tongue_id", toNum(e.target.value))}
                      options={(tongues.data ?? []).map((t) => ({ value: t.id, label: t.name }))}
                    />
                  </Field>
                  {(communities.data?.length ?? 0) > 0 && (
                    <Field label="Community / caste">
                      <Select
                        value={f.community_id ?? ""}
                        onChange={(e) => setF((s) => ({ ...s, community_id: toNum(e.target.value), sub_community_id: null }))}
                        options={(communities.data ?? []).map((c) => ({ value: c.id, label: c.name }))}
                      />
                    </Field>
                  )}
                  {(subs.data?.length ?? 0) > 0 && (
                    <Field label="Sub-community" optional>
                      <Select
                        value={f.sub_community_id ?? ""}
                        onChange={(e) => set("sub_community_id", toNum(e.target.value))}
                        options={(subs.data ?? []).map((c) => ({ value: c.id, label: c.name }))}
                      />
                    </Field>
                  )}
                </div>
              </>
            )}

            {step === 3 && (
              <>
                <h2 className="-mt-3 font-display text-2xl font-semibold">Where {isSelf ? "do you" : "do they"} live?</h2>
                <div className="grid gap-5 sm:grid-cols-2">
                  <Field label="City" hint={`Only ${subject} city is shown — never an address`}>
                    <select
                      className="w-full cursor-pointer rounded-2xl border-0 bg-white px-4 py-3 text-[15px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-brand-500"
                      value={f.city_id ?? ""}
                      onChange={(e) => set("city_id", toNum(e.target.value))}
                    >
                      <option value="">Select</option>
                      {Object.entries(cityGroups).map(([state, list]) => (
                        <optgroup key={state} label={state}>
                          {list.map((c) => (
                            <option key={c.id} value={c.id}>
                              {c.name}
                            </option>
                          ))}
                        </optgroup>
                      ))}
                    </select>
                  </Field>
                  <Field label="Height">
                    <Select
                      value={f.height_cm ?? ""}
                      onChange={(e) => set("height_cm", toNum(e.target.value))}
                      options={HEIGHTS.map((h) => ({ value: h.cm, label: `${h.label} (${h.cm} cm)` }))}
                    />
                  </Field>
                </div>
              </>
            )}

            {step === 4 && (
              <>
                <h2 className="-mt-3 font-display text-2xl font-semibold">Looks good?</h2>
                <div className="rounded-3xl bg-gradient-to-br from-brand-50 via-white to-gold-50 p-6 ring-1 ring-brand-100">
                  <div className="flex items-center gap-4">
                    <span className="grid h-16 w-16 place-items-center rounded-full bg-gradient-to-br from-brand-500 to-brand-800 font-display text-2xl font-semibold text-white ring-4 ring-gold-200">
                      {f.first_name[0]?.toUpperCase()}
                    </span>
                    <div>
                      <p className="font-display text-2xl font-semibold">
                        {f.first_name} {f.last_name}
                      </p>
                      <p className="text-sm text-muted">
                        {f.gender === "female" ? "Bride" : "Groom"} · {MARITAL[f.marital_status]}
                      </p>
                    </div>
                  </div>
                  <dl className="mt-6 grid gap-x-6 gap-y-4 text-sm sm:grid-cols-2">
                    {[
                      ["Profile created by", CREATED_BY.find((o) => o.value === f.created_by)?.label],
                      ["Date of birth", f.dob && new Date(f.dob).toLocaleDateString("en-IN", { day: "numeric", month: "long", year: "numeric" })],
                      ["Religion", nameOf(religions.data, f.religion_id)],
                      ["Community", [nameOf(communities.data, f.community_id), nameOf(subs.data, f.sub_community_id)].filter(Boolean).join(" · ") || "—"],
                      ["Mother tongue", nameOf(tongues.data, f.mother_tongue_id)],
                      ["City", nameOf(cities.data, f.city_id)],
                      ["Height", heightLabel(f.height_cm)],
                    ].map(([k, v]) => (
                      <div key={k}>
                        <dt className="text-xs font-semibold uppercase tracking-wide text-muted">{k}</dt>
                        <dd className="mt-0.5 font-semibold text-ink">{v}</dd>
                      </div>
                    ))}
                  </dl>
                </div>
                {!isSelf && (
                  <p className="flex gap-3 rounded-2xl bg-gold-50 p-4 text-sm text-ink/80 ring-1 ring-gold-100">
                    <ShieldCheck className="h-5 w-5 shrink-0 text-gold-500" />
                    Next, we'll ask the candidate (+91 {f.candidate_phone}) to confirm with an OTP before the profile goes live.
                  </p>
                )}
                <label className="flex cursor-pointer items-start gap-3 rounded-2xl p-1 text-sm text-ink/80">
                  <input type="checkbox" className="mt-0.5 h-4 w-4 accent-brand-600" checked={f.accept_terms} onChange={(e) => set("accept_terms", e.target.checked)} />
                  <span>
                    I confirm these details are true and I accept the{" "}
                    <a className="font-semibold text-brand-700 underline-offset-2 hover:underline" href="#">Terms of Use</a> and{" "}
                    <a className="font-semibold text-brand-700 underline-offset-2 hover:underline" href="#">Privacy Policy</a>.
                  </span>
                </label>
              </>
            )}

            <ErrorBox message={error} />

            <div className="flex items-center justify-between gap-3 pt-2">
              {step > 0 ? (
                <Button type="button" variant="secondary" onClick={back}>
                  <ArrowLeft className="h-4 w-4" /> Back
                </Button>
              ) : (
                <span />
              )}
              <Button type="submit" size="lg" loading={create.isPending}>
                {step === STEPS.length - 1 ? "Create my profile" : "Continue"}
                {step < STEPS.length - 1 && <ArrowRight className="h-4 w-4" />}
              </Button>
            </div>
          </form>
        </div>
      </main>
    </div>
  );
}
