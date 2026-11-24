import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Check, X } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { mediaUrl } from "../api/client";
import AdminLayout from "./AdminLayout";
import type { PhotoQueueItem } from "./types";
import { PageHead, Seg, Status, aapi, when } from "./ui";

const REJECT_REASONS = ["Not a real person / stock photo", "Face not visible", "Group photo", "Inappropriate", "Contains contact details", "Duplicate of another profile"];

export default function PhotosPage() {
  const qc = useQueryClient();
  const [status, setStatus] = useState<"pending" | "approved" | "rejected">("pending");
  const list = useQuery({ queryKey: ["admin", "photos", status], queryFn: () => aapi<PhotoQueueItem[]>(`/admin/photos?status=${status}`) });
  const [rejecting, setRejecting] = useState<string | null>(null);
  const act = useMutation({
    mutationFn: ({ id, action, reason }: { id: string; action: "approve" | "reject"; reason?: string }) =>
      aapi(`/admin/photos/${id}/moderate`, { method: "POST", body: JSON.stringify({ action, reason: reason ?? null }) }),
    onSuccess: () => { setRejecting(null); qc.invalidateQueries({ queryKey: ["admin"] }); },
  });

  return (
    <AdminLayout>
      <PageHead title="Photos" sub="Every photo is checked before other members can see it.">
        <Seg value={status} onChange={setStatus} options={[{ value: "pending", label: "To review" }, { value: "approved", label: "Approved" }, { value: "rejected", label: "Rejected" }]} />
      </PageHead>
      {list.data?.length === 0 && <p className="rounded-3xl border-2 border-dashed border-brand-100 bg-white/70 p-12 text-center text-sm text-muted">{status === "pending" ? "No photos waiting — all caught up." : "Nothing here."}</p>}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-6">
        {list.data?.map((ph) => (
          <figure key={ph.id} className="overflow-hidden rounded-3xl bg-white shadow-soft ring-1 ring-line/70 transition hover:-translate-y-0.5 hover:shadow-xl">
            <img src={mediaUrl(ph.url)} alt="" className="aspect-[3/4] w-full object-cover" />
            <figcaption className="space-y-2 p-3">
              <Link to={`/admin/profiles/${ph.profile.public_id}`} className="block truncate text-sm font-semibold text-ink hover:underline">
                {ph.profile.name}, {ph.profile.age}
              </Link>
              <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted">
                <Status s={ph.status} /> {ph.is_primary && <span>Main</span>} · {when(ph.created_at)}
              </div>
              {ph.duplicate && <p className="flex items-center gap-1 text-xs font-semibold text-red-700"><AlertTriangle className="h-3.5 w-3.5" /> Also on another profile</p>}
              {ph.status === "pending" && rejecting !== ph.id && (
                <div className="flex gap-2">
                  <button onClick={() => act.mutate({ id: ph.id, action: "approve" })} className="flex flex-1 items-center justify-center gap-1 rounded-full bg-emerald-600 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700"><Check className="h-3.5 w-3.5" /> Approve</button>
                  <button onClick={() => setRejecting(ph.id)} className="flex flex-1 items-center justify-center gap-1 rounded-full border border-line py-1.5 text-xs font-semibold text-red-700 hover:bg-red-50"><X className="h-3.5 w-3.5" /> Reject</button>
                </div>
              )}
              {rejecting === ph.id && (
                <div className="space-y-1">
                  {REJECT_REASONS.map((r) => (
                    <button key={r} onClick={() => act.mutate({ id: ph.id, action: "reject", reason: r })} className="block w-full rounded-md px-2 py-1 text-left text-xs text-ink/85 hover:bg-red-50 hover:text-red-800">{r}</button>
                  ))}
                  <button onClick={() => setRejecting(null)} className="w-full pt-1 text-xs text-muted/70">Cancel</button>
                </div>
              )}
            </figcaption>
          </figure>
        ))}
      </div>
    </AdminLayout>
  );
}
