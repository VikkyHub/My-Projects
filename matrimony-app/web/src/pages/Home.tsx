import { useQuery } from "@tanstack/react-query";
import { Navigate } from "react-router-dom";
import { ApiError, api } from "../api/client";
import type { Career, Family, Horoscope, MyProfile } from "../api/types";
import AppShell from "../components/AppShell";
import ConsentCard from "../components/ConsentCard";
import Section, { Facts } from "../components/Section";
import { Badge, Card, Field, Input, Progress, Select, Textarea, toNum, toStr } from "../components/ui";
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
  NAKSHATRAS,
  RASHIS,
  VISIBLE_TO,
  heightLabel,
  options,
} from "../lib/labels";
import {
  nameOf,
  useCities,
  useCommunities,
  useEducationLevels,
  useMotherTongues,
  useOccupations,
  useReligions,
  useSubCommunities,
} from "../lib/master";

const STATUS: Record<MyProfile["status"], { label: string; tone: "gray" | "green" | "amber" | "red" }> = {
  draft: { label: "Awaiting candidate consent", tone: "amber" },
  pending_review: { label: "Under review", tone: "amber" },
  active: { label: "Live", tone: "green" },
  hidden: { label: "Hidden", tone: "gray" },
  rejected: { label: "Needs changes", tone: "red" },
  suspended: { label: "Suspended", tone: "red" },
};

const lbl = <T extends Record<string, string>>(map: T, v: string | null | undefined) =>
  v ? (map as Record<string, string>)[v] : undefined;

function todo(p: MyProfile): string[] {
  const t: string[] = [];
  if (!p.about_me || p.about_me.length < 50) t.push("Write a few lines about yourself");
  if (!p.diet) t.push("Add diet & lifestyle");
  if (!p.family?.father_occupation && !p.family?.family_type) t.push("Add family details");
  if (!p.career?.education_level_id) t.push("Add education");
  if (!p.career?.occupation_id) t.push("Add occupation");
  if (p.career?.annual_income_band == null) t.push("Add income range");
  t.push("Upload photos (coming soon)");
  return t;
}

export default function Home() {
  const me = useQuery({
    queryKey: ["profile", "me"],
    queryFn: () => api<MyProfile>("/profiles/me"),
    retry: false,
  });
  const religions = useReligions();
  const communities = useCommunities(me.data?.religion_id);
  const subs = useSubCommunities(me.data?.community_id);
  const tongues = useMotherTongues();
  const cities = useCities();
  const edu = useEducationLevels();
  const occ = useOccupations();

  if (me.error instanceof ApiError && me.error.status === 404) return <Navigate to="/register" replace />;

  if (!me.data)
    return (
      <AppShell>
        {me.error ? <p className="text-red-700">{me.error.message}</p> : <p className="text-gray-500">Loading…</p>}
      </AppShell>
    );

  const p = me.data;
  const city = cities.data?.find((c) => c.id === p.city_id);
  const status = STATUS[p.status];
  const missing = todo(p);

  return (
    <AppShell>
      <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
        {/* Left: summary */}
        <aside className="space-y-6">
          <Card className="text-center">
            <div className="mx-auto grid h-24 w-24 place-items-center rounded-full bg-brand-50 text-3xl font-semibold text-brand-700">
              {p.first_name[0]}
              {p.last_name?.[0] ?? ""}
            </div>
            <h1 className="mt-4 text-xl font-semibold text-gray-900">
              {p.first_name} {p.last_name}
            </h1>
            <p className="text-sm text-gray-600">
              {p.age} yrs{p.height_cm ? ` · ${heightLabel(p.height_cm)?.split(" (")[0]}` : ""}
              {city ? ` · ${city.name}` : ""}
            </p>
            <p className="mt-1 text-sm text-gray-600">
              {[nameOf(religions.data, p.religion_id), nameOf(communities.data, p.community_id)]
                .filter(Boolean)
                .join(" · ")}
            </p>
            <div className="mt-3 flex flex-wrap justify-center gap-2">
              <Badge tone={status.tone}>{status.label}</Badge>
              <Badge>ID {p.public_id}</Badge>
              <Badge tone="green">✓ Mobile verified</Badge>
            </div>
          </Card>

          <Card>
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-gray-900">Profile completeness</h2>
              <span className="text-sm font-semibold text-brand-700">{p.completeness}%</span>
            </div>
            <div className="mt-3">
              <Progress value={p.completeness} />
            </div>
            <p className="mt-3 text-xs text-gray-500">Complete profiles get up to 3× more responses.</p>
            <ul className="mt-3 space-y-2 text-sm">
              {missing.map((m) => (
                <li key={m} className="flex items-center gap-2 text-gray-700">
                  <span className="h-1.5 w-1.5 rounded-full bg-brand-600" />
                  {m}
                </li>
              ))}
            </ul>
          </Card>

          {p.status === "pending_review" && (
            <Card className="bg-gray-50">
              <p className="text-sm text-gray-600">
                <strong className="text-gray-900">What happens next?</strong> Our team reviews every
                profile to keep the platform safe. Once approved, your profile will appear in searches.
              </p>
            </Card>
          )}
        </aside>

        {/* Right: details */}
        <div className="space-y-6">
          {p.candidate_consent_pending && <ConsentCard profile={p} />}

          <Card className="border-dashed">
            <h2 className="text-base font-semibold text-gray-900">Photos</h2>
            <p className="mt-1 text-sm text-gray-500">
              Photo upload with privacy controls is coming next. Profiles with photos get far more interest.
            </p>
          </Card>

          <Section
            key={`basic-${p.religion_id}-${p.community_id}-${p.city_id}-${p.height_cm}`}
            title="Basic details"
            initial={{
              first_name: p.first_name,
              last_name: p.last_name ?? "",
              marital_status: p.marital_status as string,
              height_cm: p.height_cm,
              religion_id: p.religion_id as number | null,
              community_id: p.community_id,
              sub_community_id: p.sub_community_id,
              mother_tongue_id: p.mother_tongue_id,
              city_id: p.city_id,
            }}
            empty={false}
            view={
              <Facts
                items={[
                  ["Name", `${p.first_name} ${p.last_name ?? ""}`],
                  ["Date of birth", new Date(p.dob).toLocaleDateString("en-IN", { day: "numeric", month: "long", year: "numeric" })],
                  ["Gender", p.gender === "female" ? "Female" : "Male"],
                  ["Marital status", MARITAL[p.marital_status]],
                  ["Height", heightLabel(p.height_cm)],
                  ["Religion", nameOf(religions.data, p.religion_id)],
                  ["Community", nameOf(communities.data, p.community_id)],
                  ["Sub-community", nameOf(subs.data, p.sub_community_id)],
                  ["Mother tongue", nameOf(tongues.data, p.mother_tongue_id)],
                  ["City", city ? `${city.name}, ${city.state}` : undefined],
                ]}
              />
            }
            form={(v, set) => <BasicForm v={v} set={set} />}
            toPayload={(v) => ({ ...v, last_name: toStr(v.last_name) })}
          />

          <Section
            title="About & lifestyle"
            initial={{ about_me: p.about_me ?? "", diet: p.diet ?? "", smoke: p.smoke ?? "", drink: p.drink ?? "" }}
            empty={!p.about_me && !p.diet}
            view={
              <div className="space-y-4">
                {p.about_me && <p className="whitespace-pre-line text-sm text-gray-700">{p.about_me}</p>}
                <Facts
                  items={[
                    ["Diet", lbl(DIET, p.diet)],
                    ["Smoking", lbl(HABIT, p.smoke)],
                    ["Drinking", lbl(HABIT, p.drink)],
                  ]}
                />
              </div>
            }
            form={(v, set) => (
              <>
                <Field label="About me" hint="Personality, interests, what you're looking for. Don't include phone numbers, emails or links.">
                  <Textarea maxLength={1000} value={v.about_me} onChange={(e) => set({ about_me: e.target.value })} />
                </Field>
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field label="Diet">
                    <Select value={v.diet} onChange={(e) => set({ diet: e.target.value })} options={options(DIET)} />
                  </Field>
                  <Field label="Smoking">
                    <Select value={v.smoke} onChange={(e) => set({ smoke: e.target.value })} options={options(HABIT)} />
                  </Field>
                  <Field label="Drinking">
                    <Select value={v.drink} onChange={(e) => set({ drink: e.target.value })} options={options(HABIT)} />
                  </Field>
                </div>
              </>
            )}
            toPayload={(v) => ({
              about_me: toStr(v.about_me),
              diet: toStr(v.diet),
              smoke: toStr(v.smoke),
              drink: toStr(v.drink),
            })}
          />

          <Section
            title="Education & career"
            initial={blankCareer(p.career)}
            empty={!p.career}
            view={
              <Facts
                items={[
                  ["Highest education", nameOf(edu.data, p.career?.education_level_id)],
                  ["Degree / specialisation", p.career?.education_detail],
                  ["College", p.career?.college],
                  ["Occupation", nameOf(occ.data, p.career?.occupation_id)],
                  ["Employed in", lbl(EMPLOYED_IN, p.career?.employed_in)],
                  ["Employer", p.career?.employer],
                  ["Annual income", p.career?.annual_income_band != null ? INCOME_BANDS[p.career.annual_income_band] : undefined],
                ]}
              />
            }
            form={(v, set) => (
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Highest education">
                  <Select
                    value={v.education_level_id ?? ""}
                    onChange={(e) => set({ education_level_id: toNum(e.target.value) })}
                    options={(edu.data ?? []).map((o) => ({ value: o.id, label: o.name }))}
                  />
                </Field>
                <Field label="Degree / specialisation" optional>
                  <Input value={v.education_detail ?? ""} placeholder="e.g. B.Tech Computer Science" onChange={(e) => set({ education_detail: e.target.value })} />
                </Field>
                <Field label="College" optional>
                  <Input value={v.college ?? ""} onChange={(e) => set({ college: e.target.value })} />
                </Field>
                <Field label="Occupation">
                  <Select
                    value={v.occupation_id ?? ""}
                    onChange={(e) => set({ occupation_id: toNum(e.target.value) })}
                    options={(occ.data ?? []).map((o) => ({ value: o.id, label: o.name }))}
                  />
                </Field>
                <Field label="Employed in">
                  <Select value={v.employed_in ?? ""} onChange={(e) => set({ employed_in: (toStr(e.target.value) as Career["employed_in"]) })} options={options(EMPLOYED_IN)} />
                </Field>
                <Field label="Employer" optional hint="Hidden from other members by default">
                  <Input value={v.employer ?? ""} onChange={(e) => set({ employer: e.target.value })} />
                </Field>
                <Field label="Annual income">
                  <Select
                    value={v.annual_income_band ?? ""}
                    onChange={(e) => set({ annual_income_band: toNum(e.target.value) })}
                    options={INCOME_BANDS.map((l, i) => ({ value: i, label: l }))}
                  />
                </Field>
              </div>
            )}
            toPayload={(v) => ({
              career: {
                ...v,
                education_detail: toStr(v.education_detail ?? ""),
                college: toStr(v.college ?? ""),
                employer: toStr(v.employer ?? ""),
              },
            })}
          />

          <Section
            title="Family"
            initial={blankFamily(p.family)}
            empty={!p.family}
            view={
              <Facts
                items={[
                  ["Father", p.family?.father_occupation],
                  ["Mother", p.family?.mother_occupation],
                  ["Brothers", p.family?.brothers != null ? `${p.family.brothers} (${p.family.brothers_married ?? 0} married)` : undefined],
                  ["Sisters", p.family?.sisters != null ? `${p.family.sisters} (${p.family.sisters_married ?? 0} married)` : undefined],
                  ["Family type", lbl(FAMILY_TYPE, p.family?.family_type)],
                  ["Family status", lbl(FAMILY_STATUS, p.family?.family_status)],
                  ["Family values", lbl(FAMILY_VALUES, p.family?.family_values)],
                  ["Native place", p.family?.native_place],
                ]}
              />
            }
            form={(v, set) => {
              const count = (k: keyof Family, label: string) => (
                <Field label={label}>
                  <Select
                    value={(v[k] as number | null) ?? ""}
                    onChange={(e) => set({ [k]: toNum(e.target.value) } as Partial<Family>)}
                    options={[0, 1, 2, 3, 4, 5].map((n) => ({ value: n, label: String(n) }))}
                  />
                </Field>
              );
              return (
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Father's occupation">
                    <Input value={v.father_occupation ?? ""} placeholder="e.g. Retired govt. officer" onChange={(e) => set({ father_occupation: e.target.value })} />
                  </Field>
                  <Field label="Mother's occupation">
                    <Input value={v.mother_occupation ?? ""} placeholder="e.g. Homemaker" onChange={(e) => set({ mother_occupation: e.target.value })} />
                  </Field>
                  {count("brothers", "Brothers")}
                  {count("brothers_married", "of which married")}
                  {count("sisters", "Sisters")}
                  {count("sisters_married", "of which married")}
                  <Field label="Family type">
                    <Select value={v.family_type ?? ""} onChange={(e) => set({ family_type: toStr(e.target.value) as Family["family_type"] })} options={options(FAMILY_TYPE)} />
                  </Field>
                  <Field label="Family status">
                    <Select value={v.family_status ?? ""} onChange={(e) => set({ family_status: toStr(e.target.value) as Family["family_status"] })} options={options(FAMILY_STATUS)} />
                  </Field>
                  <Field label="Family values">
                    <Select value={v.family_values ?? ""} onChange={(e) => set({ family_values: toStr(e.target.value) as Family["family_values"] })} options={options(FAMILY_VALUES)} />
                  </Field>
                  <Field label="Native place" optional>
                    <Input value={v.native_place ?? ""} onChange={(e) => set({ native_place: e.target.value })} />
                  </Field>
                </div>
              );
            }}
            toPayload={(v) => ({
              family: {
                ...v,
                father_occupation: toStr(v.father_occupation ?? ""),
                mother_occupation: toStr(v.mother_occupation ?? ""),
                native_place: toStr(v.native_place ?? ""),
              },
            })}
          />

          <Section
            title="Horoscope"
            subtitle="Optional"
            initial={blankHoroscope(p.horoscope)}
            empty={!p.horoscope}
            view={
              <Facts
                items={[
                  ["Rashi", p.horoscope?.rashi],
                  ["Nakshatra", p.horoscope?.nakshatra],
                  ["Manglik", lbl(MANGLIK, p.horoscope?.manglik)],
                  ["Time of birth", p.horoscope?.birth_time?.slice(0, 5)],
                  ["Place of birth", p.horoscope?.birth_place],
                  ["Gotra", p.horoscope?.gotra],
                  ["Visible to", p.horoscope ? VISIBLE_TO[p.horoscope.visible_to] : undefined],
                ]}
              />
            }
            form={(v, set) => (
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Rashi (moon sign)">
                  <Select value={v.rashi ?? ""} onChange={(e) => set({ rashi: toStr(e.target.value) })} options={RASHIS.map((r) => ({ value: r, label: r }))} />
                </Field>
                <Field label="Nakshatra">
                  <Select value={v.nakshatra ?? ""} onChange={(e) => set({ nakshatra: toStr(e.target.value) })} options={NAKSHATRAS.map((r) => ({ value: r, label: r }))} />
                </Field>
                <Field label="Manglik">
                  <Select value={v.manglik ?? ""} onChange={(e) => set({ manglik: toStr(e.target.value) as Horoscope["manglik"] })} options={options(MANGLIK)} />
                </Field>
                <Field label="Time of birth" optional>
                  <Input type="time" value={v.birth_time?.slice(0, 5) ?? ""} onChange={(e) => set({ birth_time: toStr(e.target.value) })} />
                </Field>
                <Field label="Place of birth" optional>
                  <Input value={v.birth_place ?? ""} onChange={(e) => set({ birth_place: e.target.value })} />
                </Field>
                <Field label="Gotra" optional>
                  <Input value={v.gotra ?? ""} onChange={(e) => set({ gotra: e.target.value })} />
                </Field>
                <Field label="Who can see my horoscope">
                  <Select
                    value={v.visible_to}
                    placeholder="Only people whose interest I accept"
                    onChange={(e) => set({ visible_to: (e.target.value || "accepted") as Horoscope["visible_to"] })}
                    options={options(VISIBLE_TO).filter((o) => o.value !== "accepted")}
                  />
                </Field>
              </div>
            )}
            toPayload={(v) => ({
              horoscope: {
                ...v,
                birth_place: toStr(v.birth_place ?? ""),
                gotra: toStr(v.gotra ?? ""),
              },
            })}
          />
        </div>
      </div>
    </AppShell>
  );
}

function blankCareer(c: Career | null): Career {
  return {
    education_level_id: null, education_detail: null, college: null, occupation_id: null,
    employer: null, employed_in: null, annual_income_band: null, ...(c ?? {}),
  };
}
function blankFamily(f: Family | null): Family {
  return {
    father_occupation: null, mother_occupation: null, brothers: null, brothers_married: null,
    sisters: null, sisters_married: null, family_type: null, family_status: null,
    family_values: null, native_place: null, ...(f ?? {}),
  };
}
function blankHoroscope(h: Horoscope | null): Horoscope {
  return {
    rashi: null, nakshatra: null, manglik: null, birth_time: null, birth_place: null, gotra: null,
    visible_to: "accepted", ...(h ?? {}),
  };
}

interface BasicValues {
  first_name: string;
  last_name: string;
  marital_status: string;
  height_cm: number | null;
  religion_id: number | null;
  community_id: number | null;
  sub_community_id: number | null;
  mother_tongue_id: number | null;
  city_id: number | null;
}

function BasicForm({ v, set }: { v: BasicValues; set: (p: Partial<BasicValues>) => void }) {
  const religions = useReligions();
  const communities = useCommunities(v.religion_id);
  const subs = useSubCommunities(v.community_id);
  const tongues = useMotherTongues();
  const cities = useCities();
  const opts = (l?: { id: number; name: string }[]) => (l ?? []).map((o) => ({ value: o.id, label: o.name }));
  return (
    <>
      <p className="rounded-lg bg-gray-50 p-3 text-xs text-gray-600">
        Gender and date of birth can't be changed here. Contact support if they're wrong.
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="First name">
          <Input value={v.first_name} onChange={(e) => set({ first_name: e.target.value })} />
        </Field>
        <Field label="Last name" optional>
          <Input value={v.last_name} onChange={(e) => set({ last_name: e.target.value })} />
        </Field>
        <Field label="Marital status">
          <Select value={v.marital_status} placeholder="" onChange={(e) => set({ marital_status: e.target.value })} options={options(MARITAL)} />
        </Field>
        <Field label="Height">
          <Select
            value={v.height_cm ?? ""}
            onChange={(e) => set({ height_cm: toNum(e.target.value) })}
            options={Array.from({ length: 31 }, (_, i) => {
              const cm = Math.round((54 + i) * 2.54);
              return { value: cm, label: heightLabel(cm)! };
            })}
          />
        </Field>
        <Field label="Religion">
          <Select value={v.religion_id ?? ""} onChange={(e) => set({ religion_id: toNum(e.target.value), community_id: null, sub_community_id: null })} options={opts(religions.data)} />
        </Field>
        <Field label="Community">
          <Select value={v.community_id ?? ""} onChange={(e) => set({ community_id: toNum(e.target.value), sub_community_id: null })} options={opts(communities.data)} />
        </Field>
        {(subs.data?.length ?? 0) > 0 && (
          <Field label="Sub-community" optional>
            <Select value={v.sub_community_id ?? ""} onChange={(e) => set({ sub_community_id: toNum(e.target.value) })} options={opts(subs.data)} />
          </Field>
        )}
        <Field label="Mother tongue">
          <Select value={v.mother_tongue_id ?? ""} onChange={(e) => set({ mother_tongue_id: toNum(e.target.value) })} options={opts(tongues.data)} />
        </Field>
        <Field label="City">
          <Select value={v.city_id ?? ""} onChange={(e) => set({ city_id: toNum(e.target.value) })} options={(cities.data ?? []).map((c) => ({ value: c.id, label: `${c.name}, ${c.state}` }))} />
        </Field>
      </div>
    </>
  );
}
