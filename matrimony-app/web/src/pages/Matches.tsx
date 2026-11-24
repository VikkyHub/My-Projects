import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Search, SlidersHorizontal, Sparkles, Users } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { api } from "../api/client";
import type { MaritalStatus, MatchPage, Option, Preferences } from "../api/types";
import AppShell from "../components/AppShell";
import { ChipSelect, Empty, Modal, Tabs } from "../components/Kit";
import MatchCard from "../components/MatchCard";
import { Button, ErrorBox, Field, Select, toNum } from "../components/ui";
import { DIET, HEIGHTS, INCOME_BANDS, MARITAL, options } from "../lib/labels";
import { useCommunities, useMotherTongues, useReligions } from "../lib/master";

type Mode = "recommended" | "all";
interface Filters {
  age_min: string;
  age_max: string;
  religion_id: string;
  community_id: string;
  mother_tongue_id: string;
  state_id: string;
  with_photo: boolean;
}
const NO_FILTERS: Filters = { age_min: "", age_max: "", religion_id: "", community_id: "", mother_tongue_id: "", state_id: "", with_photo: false };
const AGES = Array.from({ length: 43 }, (_, i) => ({ value: 18 + i, label: String(18 + i) }));

function useStates() {
  return useQuery({ queryKey: ["master", "states"], queryFn: () => api<Option[]>("/master/states"), staleTime: 3600_000 });
}

export default function Matches() {
  const [mode, setMode] = useState<Mode>("recommended");
  const [filters, setFilters] = useState<Filters>(NO_FILTERS);
  const [prefsOpen, setPrefsOpen] = useState(false);
  const religions = useReligions();
  const communities = useCommunities(toNum(filters.religion_id));
  const tongues = useMotherTongues();
  const states = useStates();

  const params = useMemo(() => {
    const q = new URLSearchParams({ mode });
    for (const [k, v] of Object.entries(filters)) if (v !== "" && v !== false) q.set(k, String(v));
    return q;
  }, [mode, filters]);

  const list = useInfiniteQuery({
    queryKey: ["matches", params.toString()],
    queryFn: ({ pageParam }) => {
      const q = new URLSearchParams(params);
      if (pageParam) q.set("cursor", pageParam);
      return api<MatchPage>(`/matches?${q}`);
    },
    initialPageParam: "",
    getNextPageParam: (last) => last.next_cursor ?? undefined,
  });
  const items = list.data?.pages.flatMap((p) => p.items) ?? [];
  const set = (k: keyof Filters, v: string | boolean) => setFilters((f) => ({ ...f, [k]: v, ...(k === "religion_id" ? { community_id: "" } : {}) }));
  const activeFilters = Object.entries(filters).filter(([, v]) => v !== "" && v !== false).length;

  return (
    <AppShell>
      {/* Header */}
      <section className="hero-rani relative overflow-hidden rounded-[2rem] px-6 py-8 text-white shadow-soft sm:px-10 sm:py-10">
        <div className="relative flex flex-col gap-6 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-gold-200">Discover</p>
            <h1 className="mt-2 font-display text-3xl font-semibold text-white sm:text-4xl">Your matches</h1>
            <p className="mt-2 max-w-lg text-white/75">
              {mode === "recommended"
                ? "People who fit what you're looking for — and who'd be happy to hear from you."
                : "Everyone on the platform, filtered your way."}
            </p>
          </div>
          <Button variant="gold" onClick={() => setPrefsOpen(true)}>
            <SlidersHorizontal className="h-4 w-4" /> Partner preferences
          </Button>
        </div>
      </section>

      <div className="mt-6 flex flex-col gap-4 lg:flex-row lg:items-center">
        <div className="lg:w-96">
          <Tabs
            value={mode}
            onChange={setMode}
            tabs={[
              { value: "recommended", label: "Recommended", icon: Sparkles },
              { value: "all", label: "Search all", icon: Search },
            ]}
          />
        </div>
        {/* Quick filters */}
        <div className="flex flex-1 flex-wrap items-center gap-2">
          <div className="flex items-center gap-1 rounded-full bg-white px-3 py-1.5 shadow-soft ring-1 ring-line/70">
            <span className="text-xs font-semibold text-muted">Age</span>
            <select aria-label="Minimum age" className="bg-transparent text-sm font-semibold outline-none" value={filters.age_min} onChange={(e) => set("age_min", e.target.value)}>
              <option value="">Min</option>
              {AGES.map((a) => <option key={a.value} value={a.value}>{a.label}</option>)}
            </select>
            <span className="text-muted">–</span>
            <select aria-label="Maximum age" className="bg-transparent text-sm font-semibold outline-none" value={filters.age_max} onChange={(e) => set("age_max", e.target.value)}>
              <option value="">Max</option>
              {AGES.map((a) => <option key={a.value} value={a.value}>{a.label}</option>)}
            </select>
          </div>
          <FilterPill label="Religion" value={filters.religion_id} onChange={(v) => set("religion_id", v)} options={religions.data} />
          {filters.religion_id && <FilterPill label="Community" value={filters.community_id} onChange={(v) => set("community_id", v)} options={communities.data} />}
          <FilterPill label="Mother tongue" value={filters.mother_tongue_id} onChange={(v) => set("mother_tongue_id", v)} options={tongues.data} />
          <FilterPill label="State" value={filters.state_id} onChange={(v) => set("state_id", v)} options={states.data} />
          <label className="flex cursor-pointer items-center gap-2 rounded-full bg-white px-3.5 py-2 text-sm font-semibold shadow-soft ring-1 ring-line/70">
            <input type="checkbox" className="accent-brand-600" checked={filters.with_photo} onChange={(e) => set("with_photo", e.target.checked)} /> With photo
          </label>
          {activeFilters > 0 && (
            <button className="text-sm font-semibold text-brand-700 hover:underline" onClick={() => setFilters(NO_FILTERS)}>
              Clear ({activeFilters})
            </button>
          )}
        </div>
      </div>

      <div className="mt-6">
        {list.isPending ? (
          <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="h-[26rem] animate-pulse rounded-3xl bg-white/70" />
            ))}
          </div>
        ) : list.error ? (
          <ErrorBox message={list.error.message} />
        ) : items.length === 0 ? (
          <Empty
            icon={Users}
            title={mode === "recommended" ? "No recommended matches yet" : "No one matches these filters"}
            text={
              mode === "recommended"
                ? "Recommendations check preferences both ways. Try widening your partner preferences, or search everyone."
                : "Try removing a filter or two."
            }
            action={
              mode === "recommended" ? (
                <Button variant="secondary" onClick={() => setMode("all")}>
                  <Search className="h-4 w-4" /> Search all profiles
                </Button>
              ) : (
                <Button variant="secondary" onClick={() => setFilters(NO_FILTERS)}>Clear filters</Button>
              )
            }
          />
        ) : (
          <>
            <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
              {items.map((p) => (
                <MatchCard key={p.public_id} p={p} />
              ))}
            </div>
            {list.hasNextPage && (
              <div className="mt-8 flex justify-center">
                <Button variant="secondary" size="lg" loading={list.isFetchingNextPage} onClick={() => list.fetchNextPage()}>
                  Show more matches
                </Button>
              </div>
            )}
          </>
        )}
      </div>

      <PreferencesModal open={prefsOpen} onClose={() => setPrefsOpen(false)} />
    </AppShell>
  );
}

function FilterPill({ label, value, onChange, options: opts }: { label: string; value: string; onChange: (v: string) => void; options?: Option[] }) {
  return (
    <select
      aria-label={label}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className={`cursor-pointer rounded-full px-3.5 py-2 text-sm font-semibold shadow-soft ring-1 outline-none ${value ? "bg-brand-50 text-brand-700 ring-brand-300" : "bg-white text-ink ring-line/70"}`}
    >
      <option value="">{label}: Any</option>
      {(opts ?? []).map((o) => (
        <option key={o.id} value={o.id}>
          {o.name}
        </option>
      ))}
    </select>
  );
}

const EMPTY_PREFS: Preferences = {
  age_min: null, age_max: null, height_min_cm: null, height_max_cm: null, marital_statuses: null,
  religion_ids: null, community_ids: null, mother_tongue_ids: null, state_ids: null,
  min_education_rank: null, min_income_band: null, diets: null,
};

function PreferencesModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const current = useQuery({ queryKey: ["preferences"], queryFn: () => api<Preferences>("/profiles/me/preferences"), enabled: open });
  const [v, setV] = useState<Preferences>(EMPTY_PREFS);
  useEffect(() => {
    if (current.data) setV({ ...EMPTY_PREFS, ...current.data });
  }, [current.data]);
  const religions = useReligions();
  const primaryReligion = v.religion_ids?.length === 1 ? v.religion_ids[0] : null;
  const communities = useCommunities(primaryReligion);
  const tongues = useMotherTongues();
  const states = useStates();
  const edu = useQuery({
    queryKey: ["master", "education-ranks"],
    queryFn: () => api<(Option & { rank: number })[]>("/master/education-levels"),
    staleTime: 3600_000,
  });
  const set = (patch: Partial<Preferences>) => setV((s) => ({ ...s, ...patch }));
  const opts = (l?: Option[]) => (l ?? []).map((o) => ({ value: o.id, label: o.name }));

  const save = useMutation({
    mutationFn: () => api<Preferences>("/profiles/me/preferences", { method: "PUT", body: JSON.stringify(v) }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["preferences"] });
      qc.invalidateQueries({ queryKey: ["matches"] });
      onClose();
    },
  });

  return (
    <Modal open={open} onClose={onClose} title="Partner preferences" wide>
      <p className="-mt-1 mb-6 text-sm text-muted">Recommended matches use these, and only show people whose own preferences fit you too.</p>
      <div className="space-y-6">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Age">
            <div className="flex items-center gap-2">
              <Select placeholder="Min" value={v.age_min ?? ""} onChange={(e) => set({ age_min: toNum(e.target.value) })} options={AGES} />
              <span className="text-muted">to</span>
              <Select placeholder="Max" value={v.age_max ?? ""} onChange={(e) => set({ age_max: toNum(e.target.value) })} options={AGES} />
            </div>
          </Field>
          <Field label="Height">
            <div className="flex items-center gap-2">
              <Select placeholder="Min" value={v.height_min_cm ?? ""} onChange={(e) => set({ height_min_cm: toNum(e.target.value) })} options={HEIGHTS.map((h) => ({ value: h.cm, label: h.label }))} />
              <span className="text-muted">to</span>
              <Select placeholder="Max" value={v.height_max_cm ?? ""} onChange={(e) => set({ height_max_cm: toNum(e.target.value) })} options={HEIGHTS.map((h) => ({ value: h.cm, label: h.label }))} />
            </div>
          </Field>
        </div>
        <Field label="Marital status">
          <ChipSelect options={options(MARITAL) as { value: MaritalStatus; label: string }[]} value={v.marital_statuses ?? []} onChange={(x) => set({ marital_statuses: x })} />
        </Field>
        <Field label="Religion">
          <ChipSelect options={opts(religions.data)} value={v.religion_ids ?? []} onChange={(x) => set({ religion_ids: x, community_ids: null })} />
        </Field>
        {primaryReligion && (communities.data?.length ?? 0) > 0 && (
          <Field label="Community">
            <ChipSelect options={opts(communities.data)} value={v.community_ids ?? []} onChange={(x) => set({ community_ids: x })} />
          </Field>
        )}
        <Field label="Mother tongue">
          <ChipSelect options={opts(tongues.data)} value={v.mother_tongue_ids ?? []} onChange={(x) => set({ mother_tongue_ids: x })} />
        </Field>
        <Field label="Lives in (state)">
          <ChipSelect options={opts(states.data)} value={v.state_ids ?? []} onChange={(x) => set({ state_ids: x })} />
        </Field>
        <Field label="Diet">
          <ChipSelect options={options(DIET)} value={v.diets ?? []} onChange={(x) => set({ diets: x })} />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Minimum education">
            <Select
              placeholder="Any"
              value={v.min_education_rank ?? ""}
              onChange={(e) => set({ min_education_rank: toNum(e.target.value) })}
              options={EDU_RANKS.filter((r) => edu.data?.some((e) => e.rank === r.value))}
            />
          </Field>
          <Field label="Minimum income">
            <Select placeholder="Any" value={v.min_income_band ?? ""} onChange={(e) => set({ min_income_band: toNum(e.target.value) })} options={INCOME_BANDS.map((l, i) => ({ value: i, label: l })).slice(1)} />
          </Field>
        </div>
        <ErrorBox message={save.error?.message} />
        <div className="flex justify-between gap-3 border-t border-line pt-5">
          <Button variant="ghost" onClick={() => setV(EMPTY_PREFS)}>Reset to any</Button>
          <Button onClick={() => save.mutate()} loading={save.isPending}>Save preferences</Button>
        </div>
      </div>
    </Modal>
  );
}

const EDU_RANKS = [
  { value: 2, label: "Diploma or above" },
  { value: 3, label: "Bachelor's or above" },
  { value: 4, label: "Master's / professional or above" },
  { value: 5, label: "Doctorate" },
];
