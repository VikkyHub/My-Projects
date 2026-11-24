import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Crown, Flag, Image, Search } from "lucide-react";
import { useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import AdminLayout from "./AdminLayout";
import type { ProfilePage } from "./types";
import { PageHead, Panel, Seg, Status, aapi, when } from "./ui";

type Tab = "pending_review" | "active" | "rejected" | "suspended" | "draft" | "";

export default function ProfilesPage() {
  const [params, setParams] = useSearchParams();
  const status = (params.get("status") ?? "pending_review") as Tab;
  const page = Number(params.get("page") ?? 1);
  const [q, setQ] = useState(params.get("q") ?? "");
  const query = new URLSearchParams({ page: String(page) });
  if (status) query.set("status", status);
  if (params.get("q")) query.set("q", params.get("q")!);
  const list = useQuery({ queryKey: ["admin", "profiles", query.toString()], queryFn: () => aapi<ProfilePage>(`/admin/profiles?${query}`) });
  const go = (patch: Record<string, string>) => setParams({ status, ...Object.fromEntries(params), page: "1", ...patch });

  return (
    <AdminLayout>
      <PageHead title="Profiles" sub={status === "pending_review" ? "Review queue — oldest first." : "Search and manage member profiles."}>
        <form className="relative" onSubmit={(e) => { e.preventDefault(); go({ q }); }}>
          <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted/70" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name or profile ID" className="w-64 rounded-full border-0 bg-white py-2.5 pl-10 pr-4 shadow-soft ring-1 ring-line/70 focus:ring-2 focus:ring-brand-500 text-sm outline-none focus:border-brand-400" />
        </form>
      </PageHead>

      <div className="mb-4 overflow-x-auto">
        <Seg
          value={status}
          onChange={(v) => setParams({ status: v, page: "1" })}
          options={[
            { value: "pending_review", label: "To review" },
            { value: "active", label: "Live" },
            { value: "rejected", label: "Needs changes" },
            { value: "suspended", label: "Suspended" },
            { value: "draft", label: "Awaiting consent" },
            { value: "", label: "All" },
          ]}
        />
      </div>

      <Panel>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-sm">
            <thead>
              <tr className="border-b border-line bg-sand/40 text-left text-xs font-bold uppercase tracking-wider text-muted">
                <th className="px-6 py-3.5">Member</th>
                <th className="px-3 py-3">Community · City</th>
                <th className="px-3 py-3">Status</th>
                <th className="px-3 py-3">Signals</th>
                <th className="px-3 py-3 text-right">Joined</th>
              </tr>
            </thead>
            <tbody>
              {list.data?.items.map((p) => (
                <tr key={p.public_id} className="border-b border-line/60 last:border-0 hover:bg-brand-50/40">
                  <td className="px-6 py-3.5">
                    <Link to={`/admin/profiles/${p.public_id}`} className="font-medium text-ink hover:underline">{p.name}</Link>
                    <p className="text-xs text-muted">
                      {p.public_id} · {p.gender === "female" ? "F" : "M"}, {p.age} · by {p.created_by}
                    </p>
                  </td>
                  <td className="px-3 py-4 text-ink/75">
                    {[p.community ?? p.religion, p.city].filter(Boolean).join(" · ") || "—"}
                  </td>
                  <td className="px-3 py-4"><Status s={p.account_status !== "active" ? p.account_status : p.status} /></td>
                  <td className="px-3 py-4">
                    <div className="flex flex-wrap items-center gap-2 text-xs text-ink/75">
                      <span title="Profile completeness">{p.completeness}%</span>
                      <span className="flex items-center gap-1" title="Photos (pending)"><Image className="h-3.5 w-3.5" />{p.photos_total}{p.photos_pending ? <span className="font-semibold text-amber-700">({p.photos_pending})</span> : null}</span>
                      {p.reports_open > 0 && <span className="flex items-center gap-1 font-semibold text-red-700"><Flag className="h-3.5 w-3.5" />{p.reports_open}</span>}
                      {p.is_premium && <Crown className="h-3.5 w-3.5 text-amber-600" aria-label="Premium" />}
                    </div>
                  </td>
                  <td className="px-3 py-4 text-right text-xs text-muted">{when(p.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {list.isPending && <p className="p-6 text-sm text-muted">Loading…</p>}
        {list.data?.items.length === 0 && <p className="p-10 text-center text-sm text-muted">{status === "pending_review" ? "Nothing to review — all caught up." : "No profiles found."}</p>}
        {list.data && list.data.pages > 1 && (
          <div className="flex items-center justify-between border-t border-line px-5 py-3 text-sm text-ink/75">
            <span>{list.data.total} profiles · page {list.data.page} of {list.data.pages}</span>
            <div className="flex gap-2">
              <button disabled={page <= 1} onClick={() => go({ page: String(page - 1) })} className="rounded-full border border-line p-1.5 disabled:opacity-40" aria-label="Previous page"><ChevronLeft className="h-4 w-4" /></button>
              <button disabled={page >= list.data.pages} onClick={() => go({ page: String(page + 1) })} className="rounded-full border border-line p-1.5 disabled:opacity-40" aria-label="Next page"><ChevronRight className="h-4 w-4" /></button>
            </div>
          </div>
        )}
      </Panel>
    </AdminLayout>
  );
}
