import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { Link } from "react-router-dom";
import AdminLayout from "./AdminLayout";
import type { ActionRow } from "./types";
import { ACTION_LABEL, PageHead, Panel, aapi, when } from "./ui";

export default function AuditPage() {
  const [page, setPage] = useState(1);
  const list = useQuery({ queryKey: ["admin", "audit", page], queryFn: () => aapi<ActionRow[]>(`/admin/audit?page=${page}`) });
  return (
    <AdminLayout>
      <PageHead title="Audit log" sub="Every staff action, newest first. This record can't be edited." />
      <Panel>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[680px] text-sm">
            <thead>
              <tr className="border-b border-slate-100 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                <th className="px-5 py-3">When</th>
                <th className="px-3 py-3">Staff</th>
                <th className="px-3 py-3">Action</th>
                <th className="px-3 py-3">Target</th>
                <th className="px-3 py-3">Reason / note</th>
              </tr>
            </thead>
            <tbody>
              {list.data?.map((a) => (
                <tr key={a.id} className="border-b border-slate-50 last:border-0">
                  <td className="whitespace-nowrap px-5 py-2.5 text-slate-500">{when(a.created_at)}</td>
                  <td className="px-3 py-2.5 font-medium text-slate-800">{a.staff}</td>
                  <td className="px-3 py-2.5">{ACTION_LABEL[a.action] ?? a.action}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-slate-600">
                    {a.target_type === "profile" ? <Link to={`/admin/profiles/${a.target_id}`} className="hover:underline">{a.target_id}</Link> : `${a.target_type}`}
                  </td>
                  <td className="max-w-xs truncate px-3 py-2.5 text-slate-600" title={a.reason ?? ""}>{a.reason ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="flex justify-between border-t border-slate-100 px-5 py-3 text-sm">
          <button disabled={page === 1} onClick={() => setPage(page - 1)} className="font-medium text-slate-600 disabled:opacity-40">← Newer</button>
          <button disabled={(list.data?.length ?? 0) < 50} onClick={() => setPage(page + 1)} className="font-medium text-slate-600 disabled:opacity-40">Older →</button>
        </div>
      </Panel>
    </AdminLayout>
  );
}
