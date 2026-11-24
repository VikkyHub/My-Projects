import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, ArrowLeft, Ban, Check, Eye, PauseCircle, Pencil, RotateCcw, X } from "lucide-react";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { mediaUrl } from "../api/client";
import { Modal } from "../components/Kit";
import { Button, ErrorBox, Field, Textarea, cx } from "../components/ui";
import AdminLayout from "./AdminLayout";
import type { ProfileDetail } from "./types";
import { ACTION_LABEL, Panel, REASON_LABEL, Status, aapi, useStaff, when } from "./ui";

type Act = "approve" | "reject" | "suspend" | "ban" | "reactivate";
const ACT: Record<Act, { title: string; reasonLabel?: string; hint?: string; danger?: boolean }> = {
  approve: { title: "Approve profile" },
  reject: { title: "Ask for changes", reasonLabel: "What should they fix?", hint: "The member sees this message. Be clear and polite." },
  suspend: { title: "Suspend member", reasonLabel: "Reason (internal)", hint: "They're logged out, chats close, and they can't sign in until reactivated.", danger: true },
  ban: { title: "Ban member permanently", reasonLabel: "Reason (internal)", hint: "Permanent. Use for scams, dowry demands, harassment or fake identities.", danger: true },
  reactivate: { title: "Reactivate member" },
};

function KV({ data }: { data: Record<string, string | null | undefined> | null }) {
  if (!data) return <p className="px-5 py-4 text-sm text-slate-400">Not provided</p>;
  // Hide internal ids; show readable labels ("never_married" -> "Never married")
  const rows = Object.entries(data).filter(([k, v]) => v != null && v !== "" && !k.endsWith("_id"));
  const nice = (v: string) => (/^[a-z_]+$/.test(v) ? (v.charAt(0).toUpperCase() + v.slice(1)).replace(/_/g, " ") : v);
  return (
    <dl className="grid gap-x-6 gap-y-3 p-5 text-sm sm:grid-cols-2">
      {rows.map(([k, v]) => (
        <div key={k}>
          <dt className="text-xs capitalize text-slate-500">{k.replace(/_/g, " ")}</dt>
          <dd className="font-medium text-slate-800">{nice(String(v))}</dd>
        </div>
      ))}
    </dl>
  );
}

export default function ProfileDetailPage() {
  const { publicId = "" } = useParams();
  const qc = useQueryClient();
  const me = useStaff();
  const key = ["admin", "profile", publicId];
  const q = useQuery({ queryKey: key, queryFn: () => aapi<ProfileDetail>(`/admin/profiles/${publicId}`) });
  const [act, setAct] = useState<Act | null>(null);
  const [reason, setReason] = useState("");
  const [revealOpen, setRevealOpen] = useState(false);
  const [phone, setPhone] = useState<string | null>(null);
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["admin"] });
  };

  const moderate = useMutation({
    mutationFn: () => aapi(`/admin/profiles/${publicId}/moderate`, { method: "POST", body: JSON.stringify({ action: act, reason: reason || null }) }),
    onSuccess: () => { setAct(null); setReason(""); refresh(); },
  });
  const photo = useMutation({
    mutationFn: ({ id, action, reason: r }: { id: string; action: "approve" | "reject"; reason?: string }) =>
      aapi(`/admin/photos/${id}/moderate`, { method: "POST", body: JSON.stringify({ action, reason: r ?? null }) }),
    onSuccess: refresh,
  });
  const reveal = useMutation({
    mutationFn: () => aapi<{ phone: string }>(`/admin/profiles/${publicId}/reveal-phone`, { method: "POST", body: JSON.stringify({ reason }) }),
    onSuccess: (r) => { setPhone(r.phone); setRevealOpen(false); setReason(""); refresh(); },
  });

  const p = q.data;
  const isAdmin = me.data?.role === "admin";
  const locked = p && p.account_status !== "active";

  return (
    <AdminLayout>
      <Link to="/admin/profiles" className="mb-4 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900">
        <ArrowLeft className="h-4 w-4" /> Profiles
      </Link>
      {q.error && <ErrorBox message={q.error.message} />}
      {p && (
        <>
          <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
            <div>
              <div className="flex flex-wrap items-center gap-3">
                <h1 className="text-2xl font-semibold tracking-tight">{p.name}</h1>
                <Status s={locked ? p.account_status : p.status} />
                {p.is_premium && <span className="rounded-md bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-800 ring-1 ring-amber-200">Premium</span>}
              </div>
              <p className="mt-1 text-sm text-slate-500">
                {p.public_id} · {p.gender === "female" ? "Female" : "Male"}, {p.age} · created by {p.created_by} · joined {when(p.created_at)}
              </p>
              {p.moderation_note && (
                <p className="mt-2 flex items-start gap-1.5 text-sm text-orange-800"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> Note to member: {p.moderation_note}</p>
              )}
            </div>
            <div className="flex flex-wrap gap-2">
              {!locked && p.status !== "active" && (
                <Button size="sm" className="!bg-none !bg-emerald-600 !shadow-none hover:!bg-emerald-700" onClick={() => setAct("approve")} disabled={p.consent_pending}>
                  <Check className="h-4 w-4" /> Approve
                </Button>
              )}
              {!locked && p.status !== "rejected" && (
                <Button size="sm" variant="secondary" onClick={() => setAct("reject")}><Pencil className="h-4 w-4" /> Ask for changes</Button>
              )}
              {!locked && <Button size="sm" variant="secondary" onClick={() => setAct("suspend")}><PauseCircle className="h-4 w-4" /> Suspend</Button>}
              {isAdmin && p.account_status !== "banned" && (
                <Button size="sm" variant="secondary" className="!text-red-700" onClick={() => setAct("ban")}><Ban className="h-4 w-4" /> Ban</Button>
              )}
              {locked && (p.account_status !== "banned" || isAdmin) && (
                <Button size="sm" variant="secondary" onClick={() => setAct("reactivate")}><RotateCcw className="h-4 w-4" /> Reactivate</Button>
              )}
            </div>
          </div>
          {p.consent_pending && <p className="mb-4 rounded-lg bg-slate-100 px-4 py-2.5 text-sm text-slate-600">The candidate hasn't confirmed consent yet, so this profile can't be approved.</p>}

          <div className="grid gap-6 xl:grid-cols-[1fr_380px]">
            <div className="space-y-6">
              <Panel title={`Photos (${p.photos.length})`}>
                {p.photos.length === 0 ? (
                  <p className="px-5 py-4 text-sm text-slate-400">No photos uploaded</p>
                ) : (
                  <div className="grid grid-cols-2 gap-4 p-5 sm:grid-cols-3 lg:grid-cols-4">
                    {p.photos.map((ph) => (
                      <figure key={ph.id} className="overflow-hidden rounded-lg border border-slate-200">
                        <img src={mediaUrl(ph.url)} alt="" className={cx("aspect-[3/4] w-full object-cover", ph.status === "rejected" && "opacity-40 grayscale")} />
                        <figcaption className="space-y-2 p-2">
                          <div className="flex flex-wrap gap-1">
                            <Status s={ph.status} />
                            {ph.is_primary && <span className="rounded-md bg-slate-100 px-1.5 py-0.5 text-xs font-medium text-slate-600">Main</span>}
                          </div>
                          {ph.duplicate && <p className="flex items-center gap-1 text-xs font-medium text-red-700"><AlertTriangle className="h-3.5 w-3.5" /> Same photo on another profile</p>}
                          {ph.status === "pending" && (
                            <div className="flex gap-1.5">
                              <button onClick={() => photo.mutate({ id: ph.id, action: "approve" })} className="flex flex-1 items-center justify-center gap-1 rounded-md bg-emerald-600 py-1 text-xs font-semibold text-white hover:bg-emerald-700"><Check className="h-3.5 w-3.5" /> OK</button>
                              <button onClick={() => { const r = prompt("Why reject this photo? (e.g. not a real person, group photo, obscene)"); if (r) photo.mutate({ id: ph.id, action: "reject", reason: r }); }} className="flex flex-1 items-center justify-center gap-1 rounded-md border border-slate-200 py-1 text-xs font-semibold text-red-700 hover:bg-red-50"><X className="h-3.5 w-3.5" /> Reject</button>
                            </div>
                          )}
                        </figcaption>
                      </figure>
                    ))}
                  </div>
                )}
              </Panel>

              <Panel title="About">
                <p className="whitespace-pre-line px-5 py-4 text-sm text-slate-700">{p.about_me || <span className="text-slate-400">Not written</span>}</p>
                <KV data={{ date_of_birth: p.dob, height: p.height_cm ? `${p.height_cm} cm` : null, marital_status: p.marital_status, religion: p.religion, community: p.community, mother_tongue: p.mother_tongue, city: p.city, completeness: `${p.completeness}%` }} />
              </Panel>
              <Panel title="Career"><KV data={p.career} /></Panel>
              <Panel title="Family"><KV data={p.family} /></Panel>
              {p.horoscope && <Panel title="Horoscope"><KV data={p.horoscope} /></Panel>}
            </div>

            <div className="space-y-6">
              <Panel title="Contact">
                <div className="flex items-center justify-between gap-3 px-5 py-4">
                  <span className="font-mono text-sm text-slate-800">{phone ?? p.phone_masked ?? "—"}</span>
                  {!phone && p.phone_masked && (
                    <Button size="sm" variant="secondary" onClick={() => setRevealOpen(true)}><Eye className="h-4 w-4" /> Reveal</Button>
                  )}
                </div>
                <p className="border-t border-slate-100 px-5 py-2.5 text-xs text-slate-500">Revealing a number is logged with your reason.</p>
              </Panel>

              <Panel title={`Reports (${p.reports.length})`}>
                {p.reports.length === 0 ? (
                  <p className="px-5 py-4 text-sm text-slate-400">No reports</p>
                ) : (
                  <ul className="divide-y divide-slate-100">
                    {p.reports.map((r) => (
                      <li key={r.id} className="px-5 py-3 text-sm">
                        <div className="flex items-center justify-between gap-2">
                          <span className="font-semibold text-slate-800">{REASON_LABEL[r.reason] ?? r.reason}</span>
                          <Status s={r.status} />
                        </div>
                        {r.details && <p className="mt-1 text-slate-600">{r.details}</p>}
                        {r.message && <p className="mt-1.5 rounded-md bg-red-50 px-2.5 py-1.5 text-xs text-red-900">Message: “{r.message}”</p>}
                        <p className="mt-1 text-xs text-slate-500">by {r.reporter.name} · {when(r.created_at)}</p>
                      </li>
                    ))}
                  </ul>
                )}
              </Panel>

              <Panel title="Moderation history">
                {p.history.length === 0 ? (
                  <p className="px-5 py-4 text-sm text-slate-400">No actions yet</p>
                ) : (
                  <ol className="space-y-3 px-5 py-4">
                    {p.history.map((h) => (
                      <li key={h.id} className="text-sm">
                        <p className="font-medium text-slate-800">{ACTION_LABEL[h.action] ?? h.action}</p>
                        <p className="text-xs text-slate-500">{h.staff} · {when(h.created_at)}</p>
                        {h.reason && <p className="mt-0.5 text-xs text-slate-600">“{h.reason}”</p>}
                      </li>
                    ))}
                  </ol>
                )}
              </Panel>
            </div>
          </div>

          <Modal open={!!act} onClose={() => { setAct(null); moderate.reset(); }} title={act ? ACT[act].title : ""}>
            {act && (
              <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); moderate.mutate(); }}>
                {ACT[act].hint && <p className="text-sm text-slate-600">{ACT[act].hint}</p>}
                {ACT[act].reasonLabel && (
                  <Field label={ACT[act].reasonLabel!}>
                    <Textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} required autoFocus />
                  </Field>
                )}
                {!ACT[act].reasonLabel && <p className="text-sm text-slate-600">{act === "approve" ? `${p.name} will appear in matches right away.` : `${p.name} will be able to sign in and appear in matches again.`}</p>}
                <ErrorBox message={moderate.error?.message} />
                <div className="flex justify-end gap-2">
                  <Button type="button" variant="secondary" onClick={() => setAct(null)}>Cancel</Button>
                  <Button type="submit" loading={moderate.isPending} className={ACT[act].danger ? "!bg-none !bg-red-600 !shadow-none hover:!bg-red-700" : "!bg-none !bg-slate-900 !shadow-none hover:!bg-slate-800"}>
                    {ACT[act].title}
                  </Button>
                </div>
              </form>
            )}
          </Modal>

          <Modal open={revealOpen} onClose={() => setRevealOpen(false)} title="Reveal phone number">
            <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); reveal.mutate(); }}>
              <p className="text-sm text-slate-600">This is recorded in the audit log. Only reveal numbers when you need to contact the member about safety or verification.</p>
              <Field label="Why do you need it?">
                <Textarea value={reason} onChange={(e) => setReason(e.target.value)} minLength={5} required autoFocus placeholder="e.g. Verifying identity after a fake-profile report" />
              </Field>
              <ErrorBox message={reveal.error?.message} />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="secondary" onClick={() => setRevealOpen(false)}>Cancel</Button>
                <Button type="submit" loading={reveal.isPending} className="!bg-none !bg-slate-900 !shadow-none hover:!bg-slate-800">Reveal</Button>
              </div>
            </form>
          </Modal>
        </>
      )}
    </AdminLayout>
  );
}
