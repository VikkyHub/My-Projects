import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";
import type { CreatedBy, Gender, MaritalStatus, MyProfile } from "../api/types";
import { Logo } from "../components/AppShell";
import { Badge, Button, Card, ErrorBox, Field, Input, Select, toNum } from "../components/ui";
import { CREATED_BY, HEIGHTS, MARITAL, heightLabel, options } from "../lib/labels";
import {
  nameOf,
  useCities,
  useCommunities,
  useMotherTongues,
  useReligions,
  useSubCommunities,
} from "../lib/master";

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

const STEPS = ["Profile for", "Basic details", "Religion & community", "Location & height", "Review"];

function maxDob(gender: Gender | "") {
  const minAge = gender === "male" ? 21 : 18;
  const d = new Date();
  d.setFullYear(d.getFullYear() - minAge);
  return d.toISOString().slice(0, 10);
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
  const who = isSelf ? "your" : "the candidate's";

  const cityGroups = useMemo(() => {
    const g: Record<string, { id: number; name: string }[]> = {};
    for (const c of cities.data ?? []) (g[c.state] ??= []).push(c);
    return g;
  }, [cities.data]);

  function validate(): string | null {
    if (step === 0) {
      if (!f.created_by) return "Please choose who this profile is for.";
      if (!isSelf && !/^[6-9]\d{9}$/.test(f.candidate_phone))
        return "Enter the candidate's 10-digit mobile number.";
    }
    if (step === 1) {
      if (!f.first_name.trim()) return "Please enter the first name.";
      if (!f.gender) return "Please choose a gender.";
      if (!f.dob) return "Please enter the date of birth.";
      if (f.dob > maxDob(f.gender))
        return `Minimum age is ${f.gender === "male" ? 21 : 18} years.`;
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

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="border-b border-gray-200 bg-white">
        <div className="mx-auto max-w-3xl px-4 py-3">
          <Logo />
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="text-2xl font-semibold text-gray-900">Create your profile</h1>
        <p className="mt-1 text-sm text-gray-600">Takes about 2 minutes. You can add more details later.</p>

        {/* Stepper */}
        <ol className="mt-6 flex gap-2">
          {STEPS.map((s, i) => (
            <li key={s} className="flex-1">
              <div className={`h-1.5 rounded-full ${i <= step ? "bg-brand-600" : "bg-gray-200"}`} />
              <p className={`mt-2 hidden text-xs sm:block ${i === step ? "font-medium text-brand-700" : "text-gray-500"}`}>
                {s}
              </p>
            </li>
          ))}
        </ol>
        <p className="mt-2 text-xs text-gray-500 sm:hidden">
          Step {step + 1} of {STEPS.length}: {STEPS[step]}
        </p>

        <Card className="mt-6">
          <form
            className="space-y-5"
            onSubmit={(e) => {
              e.preventDefault();
              next();
            }}
          >
            {step === 0 && (
              <>
                <h2 className="text-lg font-medium">Who is this profile for?</h2>
                <div className="grid gap-3 sm:grid-cols-2">
                  {CREATED_BY.map((o) => (
                    <button
                      type="button"
                      key={o.value}
                      onClick={() => set("created_by", o.value)}
                      className={`rounded-xl border p-4 text-left transition ${
                        f.created_by === o.value
                          ? "border-brand-600 bg-brand-50 ring-1 ring-brand-600"
                          : "border-gray-200 hover:border-gray-300"
                      }`}
                    >
                      <p className="font-medium text-gray-900">{o.label}</p>
                      <p className="text-sm text-gray-500">{o.hint}</p>
                    </button>
                  ))}
                </div>
                {f.created_by && !isSelf && (
                  <div className="rounded-xl bg-amber-50 p-4">
                    <Field
                      label="Candidate's own mobile number"
                      hint="We'll send them an OTP. The profile stays hidden until they confirm — this protects people from being listed without their consent."
                    >
                      <div className="flex rounded-lg border border-gray-300 bg-white focus-within:border-brand-600 focus-within:ring-2 focus-within:ring-brand-600/20">
                        <span className="px-3 py-2.5 text-sm text-gray-500">+91</span>
                        <input
                          className="w-full rounded-r-lg py-2.5 pr-3 text-sm outline-none"
                          inputMode="numeric"
                          maxLength={10}
                          value={f.candidate_phone}
                          onChange={(e) => set("candidate_phone", e.target.value.replace(/\D/g, ""))}
                          placeholder="98765 43210"
                        />
                      </div>
                    </Field>
                  </div>
                )}
              </>
            )}

            {step === 1 && (
              <>
                <h2 className="text-lg font-medium">Basic details</h2>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="First name">
                    <Input value={f.first_name} onChange={(e) => set("first_name", e.target.value)} autoFocus />
                  </Field>
                  <Field label="Last name" optional hint="Shown only as an initial to free members">
                    <Input value={f.last_name} onChange={(e) => set("last_name", e.target.value)} />
                  </Field>
                </div>
                <Field label="Gender">
                  <div className="grid grid-cols-2 gap-3">
                    {(["female", "male"] as const).map((g) => (
                      <button
                        type="button"
                        key={g}
                        onClick={() => set("gender", g)}
                        className={`rounded-lg border px-4 py-2.5 text-sm font-medium ${
                          f.gender === g ? "border-brand-600 bg-brand-50 text-brand-700" : "border-gray-300 text-gray-700"
                        }`}
                      >
                        {g === "female" ? "Female (Bride)" : "Male (Groom)"}
                      </button>
                    ))}
                  </div>
                </Field>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Date of birth" hint="Can't be changed later">
                    <Input type="date" value={f.dob} max={maxDob(f.gender)} min="1946-01-01" onChange={(e) => set("dob", e.target.value)} />
                  </Field>
                  <Field label="Marital status">
                    <Select
                      value={f.marital_status}
                      onChange={(e) => set("marital_status", e.target.value as MaritalStatus)}
                      options={options(MARITAL)}
                    />
                  </Field>
                </div>
                {f.marital_status !== "never_married" && (
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={f.has_children} onChange={(e) => set("has_children", e.target.checked)} />
                    Has children
                  </label>
                )}
              </>
            )}

            {step === 2 && (
              <>
                <h2 className="text-lg font-medium">Religion & community</h2>
                <Field label="Religion">
                  <Select
                    value={f.religion_id ?? ""}
                    onChange={(e) =>
                      setF((s) => ({ ...s, religion_id: toNum(e.target.value), community_id: null, sub_community_id: null }))
                    }
                    options={(religions.data ?? []).map((r) => ({ value: r.id, label: r.name }))}
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
                <Field label="Mother tongue">
                  <Select
                    value={f.mother_tongue_id ?? ""}
                    onChange={(e) => set("mother_tongue_id", toNum(e.target.value))}
                    options={(tongues.data ?? []).map((t) => ({ value: t.id, label: t.name }))}
                  />
                </Field>
              </>
            )}

            {step === 3 && (
              <>
                <h2 className="text-lg font-medium">Location & height</h2>
                <Field label={`City (${who} current city)`}>
                  <select
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5 text-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20"
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
              </>
            )}

            {step === 4 && (
              <>
                <h2 className="text-lg font-medium">Review</h2>
                <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
                  {[
                    ["Profile for", CREATED_BY.find((o) => o.value === f.created_by)?.label],
                    ["Name", `${f.first_name} ${f.last_name}`.trim()],
                    ["Gender", f.gender === "female" ? "Female" : "Male"],
                    ["Date of birth", f.dob],
                    ["Marital status", MARITAL[f.marital_status]],
                    ["Religion", nameOf(religions.data, f.religion_id)],
                    ["Community", [nameOf(communities.data, f.community_id), nameOf(subs.data, f.sub_community_id)].filter(Boolean).join(" · ") || "—"],
                    ["Mother tongue", nameOf(tongues.data, f.mother_tongue_id)],
                    ["City", nameOf(cities.data, f.city_id)],
                    ["Height", heightLabel(f.height_cm)],
                  ].map(([k, v]) => (
                    <div key={k}>
                      <dt className="text-gray-500">{k}</dt>
                      <dd className="font-medium text-gray-900">{v}</dd>
                    </div>
                  ))}
                </dl>
                {!isSelf && (
                  <p className="rounded-lg bg-amber-50 p-3 text-sm text-amber-900">
                    <Badge tone="amber">Next</Badge> We'll ask the candidate (+91 {f.candidate_phone}) to confirm with an OTP before the profile becomes visible.
                  </p>
                )}
                <label className="flex items-start gap-2 text-sm text-gray-700">
                  <input type="checkbox" className="mt-0.5" checked={f.accept_terms} onChange={(e) => set("accept_terms", e.target.checked)} />
                  <span>
                    I confirm these details are true and I accept the <a className="text-brand-700 underline" href="#">Terms of Use</a> and{" "}
                    <a className="text-brand-700 underline" href="#">Privacy Policy</a>.
                  </span>
                </label>
              </>
            )}

            <ErrorBox message={error} />

            <div className="flex justify-between gap-3 border-t border-gray-100 pt-5">
              <Button type="button" variant="secondary" disabled={step === 0} onClick={() => { setError(null); setStep(step - 1); }}>
                Back
              </Button>
              <Button type="submit" loading={create.isPending}>
                {step === STEPS.length - 1 ? "Create profile" : "Continue"}
              </Button>
            </div>
          </form>
        </Card>
      </main>
    </div>
  );
}
