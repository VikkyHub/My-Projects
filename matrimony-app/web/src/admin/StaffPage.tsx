import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Copy, ShieldCheck, ShieldOff, UserPlus } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { Modal } from "../components/Kit";
import { Button, ErrorBox, Field, Input, Select } from "../components/ui";
import AdminLayout from "./AdminLayout";
import type { StaffRow } from "./types";
import { PageHead, Panel, aapi, useStaff, when } from "./ui";

export default function StaffPage() {
  const qc = useQueryClient();
  const me = useStaff();
  const list = useQuery({ queryKey: ["admin", "staff"], queryFn: () => aapi<StaffRow[]>("/admin/staff") });
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ email: "", name: "", role: "moderator" });
  const [issued, setIssued] = useState<{ email: string; password: string } | null>(null);
  const done = () => qc.invalidateQueries({ queryKey: ["admin", "staff"] });

  const create = useMutation({
    mutationFn: () => aapi<{ staff: StaffRow; temporary_password: string }>("/admin/staff", { method: "POST", body: JSON.stringify(form) }),
    onSuccess: (r) => { setOpen(false); setIssued({ email: r.staff.email ?? "", password: r.temporary_password }); setForm({ email: "", name: "", role: "moderator" }); done(); },
  });
  const act = useMutation({
    mutationFn: ({ id, a }: { id: string; a: "disable" | "enable" | "reset" }) => aapi<{ staff: StaffRow; temporary_password: string } | StaffRow>(`/admin/staff/${id}/${a}`, { method: "POST" }),
    onSuccess: (r) => { if ("temporary_password" in r) setIssued({ email: r.staff.email ?? "", password: r.temporary_password }); done(); },
  });

  return (
    <AdminLayout>
      <PageHead title="Staff" sub="Moderators review profiles, photos and reports. Admins can also ban, manage staff and see the audit log.">
        <Button className="" onClick={() => setOpen(true)}><UserPlus className="h-4 w-4" /> Invite staff</Button>
      </PageHead>

      {issued && (
        <div className="mb-6 rounded-3xl bg-gradient-to-br from-gold-50 to-brand-50 p-6 text-sm text-ink shadow-soft ring-1 ring-gold-200">
          <p className="font-semibold">Temporary password for {issued.email} — shown only once</p>
          <div className="mt-2 flex items-center gap-2">
            <code className="select-all rounded-xl bg-white px-3 py-1.5 font-mono text-base ring-1 ring-gold-200">{issued.password}</code>
            <button onClick={() => navigator.clipboard?.writeText(issued.password)} className="rounded-md p-1.5 hover:bg-amber-100" aria-label="Copy"><Copy className="h-4 w-4" /></button>
          </div>
          <p className="mt-2">Share it privately (not by email). On first sign-in at <strong>/admin/login</strong> they set a new password and their authenticator app.</p>
          <button onClick={() => setIssued(null)} className="mt-3 text-xs font-semibold underline">I've shared it — hide</button>
        </div>
      )}

      <Panel>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead>
              <tr className="border-b border-line bg-sand/40 text-left text-xs font-bold uppercase tracking-wider text-muted">
                <th className="px-6 py-3.5">Name</th>
                <th className="px-3 py-3">Role</th>
                <th className="px-3 py-3">Status</th>
                <th className="px-3 py-3">2-step</th>
                <th className="px-3 py-3">Last sign-in</th>
                <th className="px-3 py-3" />
              </tr>
            </thead>
            <tbody>
              {list.data?.map((s) => (
                <tr key={s.id} className="border-b border-line/60 last:border-0">
                  <td className="px-6 py-3.5">
                    <div className="flex items-center gap-3">
                      <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-full font-display text-base font-semibold text-white ${s.role === "admin" ? "bg-gradient-to-br from-brand-500 to-brand-800" : "bg-gradient-to-br from-violet-400 to-violet-700"}`}>
                        {(s.name ?? "?").split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase()}
                      </span>
                      <div>
                        <p className="font-semibold text-ink">{s.name}{s.id === me.data?.id && <span className="ml-1.5 text-xs font-normal text-muted">(you)</span>}</p>
                        <p className="text-xs text-muted">{s.email}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-3 py-4">
                    <span className={`rounded-full px-2.5 py-1 text-xs font-bold capitalize ${s.role === "admin" ? "bg-gold-50 text-gold-600 ring-1 ring-gold-200" : "bg-violet-50 text-violet-700 ring-1 ring-violet-100"}`}>{s.role}</span>
                  </td>
                  <td className="px-3 py-4">
                    {s.status === "active" ? (
                      <span className="inline-flex items-center gap-1 rounded-md bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700 ring-1 ring-emerald-200"><ShieldCheck className="h-3.5 w-3.5" /> Active</span>
                    ) : (
                      <span className="inline-flex items-center gap-1 rounded-md bg-sand px-2 py-0.5 text-xs font-semibold text-ink/75 ring-1 ring-line"><ShieldOff className="h-3.5 w-3.5" /> Disabled</span>
                    )}
                  </td>
                  <td className="px-3 py-4">
                    {s.totp_enabled ? <span className="flex items-center gap-1 text-emerald-700"><ShieldCheck className="h-4 w-4" /> On</span> : <span className="flex items-center gap-1 text-muted"><ShieldOff className="h-4 w-4" /> Not set up</span>}
                  </td>
                  <td className="px-3 py-4 text-muted">{when(s.last_login_at)}</td>
                  <td className="px-3 py-4 text-right">
                    <div className="flex justify-end gap-3">
                      <Link to={`/admin/logs?category=staff&actor=${encodeURIComponent(s.email ?? "")}`} className="text-xs font-semibold text-brand-700 hover:underline">Sign-in history</Link>
                    {s.id !== me.data?.id && (
                      <div className="flex justify-end gap-2">
                        <button onClick={() => confirm(`Reset ${s.name}'s password and authenticator?`) && act.mutate({ id: s.id, a: "reset" })} className="text-xs font-semibold text-ink/75 hover:text-ink">Reset login</button>
                        {s.status === "active" ? (
                          <button onClick={() => confirm(`Disable ${s.name}? They'll be signed out.`) && act.mutate({ id: s.id, a: "disable" })} className="text-xs font-semibold text-red-700">Disable</button>
                        ) : (
                          <button onClick={() => act.mutate({ id: s.id, a: "enable" })} className="text-xs font-semibold text-emerald-700">Enable</button>
                        )}
                      </div>
                    )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Panel>

      <Modal open={open} onClose={() => setOpen(false)} title="Invite staff">
        <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); create.mutate(); }}>
          <Field label="Full name"><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></Field>
          <Field label="Work email"><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required /></Field>
          <Field label="Role">
            <Select value={form.role} placeholder="" onChange={(e) => setForm({ ...form, role: e.target.value })} options={[{ value: "moderator", label: "Moderator — review & moderate" }, { value: "admin", label: "Admin — everything, incl. bans & staff" }]} />
          </Field>
          <ErrorBox message={create.error?.message} />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setOpen(false)}>Cancel</Button>
            <Button type="submit" loading={create.isPending}>Create & get password</Button>
          </div>
        </form>
      </Modal>
    </AdminLayout>
  );
}
