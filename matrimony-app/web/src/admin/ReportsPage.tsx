import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, MessageSquareWarning } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { Modal } from "../components/Kit";
import { Button, ErrorBox, Field, Textarea } from "../components/ui";
import AdminLayout from "./AdminLayout";
import type { ReportRow } from "./types";
import { PageHead, Panel, REASON_LABEL, Seg, Status, aapi, useStaff, when } from "./ui";

type Act = "dismiss" | "warn" | "suspend" | "ban";
const ACT: Record<Act, { label: string; text: string; note: string }> = {
  dismiss: { label: "Dismiss", text: "No rule was broken. Only this report is closed.", note: "Internal note (optional)" },
  warn: { label: "Warn member", text: "The member sees your note on their profile page. Closes all open reports about them.", note: "Message to the member" },
  suspend: { label: "Suspend", text: "Logs them out, closes chats, blocks sign-in until reactivated.", note: "Reason (internal)" },
  ban: { label: "Ban", text: "Permanent. For scams, dowry demands, harassment, fake identities.", note: "Reason (internal)" },
};

export default function ReportsPage() {
  const qc = useQueryClient();
  const me = useStaff();
  const [status, setStatus] = useState<"open" | "closed">("open");
  const list = useQuery({ queryKey: ["admin", "reports", status], queryFn: () => aapi<ReportRow[]>(`/admin/reports?status=${status}`) });
  const [sel, setSel] = useState<{ r: ReportRow; a: Act } | null>(null);
  const [note, setNote] = useState("");
  const resolve = useMutation({
    mutationFn: () => aapi(`/admin/reports/${sel!.r.id}/resolve`, { method: "POST", body: JSON.stringify({ action: sel!.a, note: note || null }) }),
    onSuccess: () => { setSel(null); setNote(""); qc.invalidateQueries({ queryKey: ["admin"] }); },
  });

  return (
    <AdminLayout>
      <PageHead title="Reports" sub="Members flag profiles and messages here. Oldest first.">
        <Seg value={status} onChange={setStatus} options={[{ value: "open", label: "Open" }, { value: "closed", label: "Resolved" }]} />
      </PageHead>
      {list.data?.length === 0 && <p className="rounded-3xl border-2 border-dashed border-brand-100 bg-white/70 p-12 text-center text-sm text-muted">{status === "open" ? "No open reports." : "No resolved reports yet."}</p>}
      <div className="space-y-4">
        {list.data?.map((r) => (
          <Panel key={r.id}>
            <div className="flex flex-wrap items-start justify-between gap-4 p-5">
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold text-ink">{REASON_LABEL[r.reason] ?? r.reason}</span>
                  <Status s={r.status} />
                  {r.reported_open_reports > 1 && (
                    <span className="flex items-center gap-1 rounded-md bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-700 ring-1 ring-red-200">
                      <AlertTriangle className="h-3.5 w-3.5" /> {r.reported_open_reports} open reports on this member
                    </span>
                  )}
                </div>
                <p className="mt-1 text-sm text-ink/75">
                  <Link to={`/admin/profiles/${r.reported.public_id}`} className="font-semibold text-ink hover:underline">{r.reported.name}</Link>{" "}
                  ({r.reported.public_id}) reported by {r.reporter.name} · {when(r.created_at)}
                </p>
                {r.details && <p className="mt-2 text-sm text-ink/85">“{r.details}”</p>}
                {r.message && (
                  <p className="mt-2 flex items-start gap-2 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-900">
                    <MessageSquareWarning className="mt-0.5 h-4 w-4 shrink-0" /> Reported message: “{r.message}”
                  </p>
                )}
              </div>
              {r.status === "open" && (
                <div className="flex flex-wrap gap-2">
                  {(["dismiss", "warn", "suspend"] as Act[]).map((a) => (
                    <Button key={a} size="sm" variant="secondary" onClick={() => setSel({ r, a })}>{ACT[a].label}</Button>
                  ))}
                  {me.data?.role === "admin" && <Button size="sm" variant="secondary" className="!text-red-700" onClick={() => setSel({ r, a: "ban" })}>Ban</Button>}
                </div>
              )}
            </div>
          </Panel>
        ))}
      </div>

      <Modal open={!!sel} onClose={() => { setSel(null); resolve.reset(); }} title={sel ? `${ACT[sel.a].label}: ${sel.r.reported.name}` : ""}>
        {sel && (
          <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); resolve.mutate(); }}>
            <p className="text-sm text-ink/75">{ACT[sel.a].text}</p>
            <Field label={ACT[sel.a].note}>
              <Textarea value={note} onChange={(e) => setNote(e.target.value)} maxLength={300} required={sel.a !== "dismiss"} />
            </Field>
            <ErrorBox message={resolve.error?.message} />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" onClick={() => setSel(null)}>Cancel</Button>
              <Button type="submit" loading={resolve.isPending} className={sel.a === "ban" || sel.a === "suspend" ? "!bg-none !bg-red-600 !shadow-none" : ""}>
                {ACT[sel.a].label}
              </Button>
            </div>
          </form>
        )}
      </Modal>
    </AdminLayout>
  );
}
