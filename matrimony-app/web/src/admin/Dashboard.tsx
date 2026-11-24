import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Flag, Image, UserCheck } from "lucide-react";
import { Link } from "react-router-dom";
import AdminLayout from "./AdminLayout";
import type { Stats } from "./types";
import { PageHead, Panel, aapi, useStaff } from "./ui";

/** Headline numbers are stat tiles (not charts): label, value in text ink, short context. */
function Tile({ label, value, note }: { label: string; value?: number; note?: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-5">
      <p className="text-sm font-medium text-slate-500">{label}</p>
      <p className="mt-2 text-3xl font-semibold tabular-nums tracking-tight text-slate-900">{value?.toLocaleString("en-IN") ?? "—"}</p>
      {note && <p className="mt-1 text-xs text-slate-500">{note}</p>}
    </div>
  );
}

function Queue({ to, icon: Icon, label, count, text }: { to: string; icon: typeof Flag; label: string; count?: number; text: string }) {
  const has = !!count;
  return (
    <Link to={to} className="group flex items-center gap-4 rounded-xl border border-slate-200 bg-white p-5 transition hover:border-slate-300 hover:shadow-sm">
      <span className={`grid h-11 w-11 place-items-center rounded-lg ${has ? "bg-amber-50 text-amber-700" : "bg-slate-100 text-slate-500"}`}>
        <Icon className="h-5 w-5" />
      </span>
      <div className="flex-1">
        <p className="text-sm font-semibold text-slate-900">
          {label} <span className="ml-1 tabular-nums">{count ?? "—"}</span>
        </p>
        <p className="text-xs text-slate-500">{has ? text : "All clear"}</p>
      </div>
      <ArrowRight className="h-4 w-4 text-slate-400 transition group-hover:translate-x-0.5 group-hover:text-slate-700" />
    </Link>
  );
}

export default function Dashboard() {
  const me = useStaff();
  const s = useQuery({ queryKey: ["admin", "stats"], queryFn: () => aapi<Stats>("/admin/stats"), refetchInterval: 60_000 });
  const d = s.data;
  return (
    <AdminLayout>
      <PageHead title={`Good ${new Date().getHours() < 12 ? "morning" : new Date().getHours() < 17 ? "afternoon" : "evening"}, ${me.data?.name?.split(" ")[0] ?? ""}`} sub="Here's what needs attention today." />

      <div className="grid gap-4 md:grid-cols-3">
        <Queue to="/admin/profiles?status=pending_review" icon={UserCheck} label="Profiles to review" count={d?.profiles_pending} text="Oldest first — approve or ask for changes" />
        <Queue to="/admin/photos" icon={Image} label="Photos to review" count={d?.photos_pending} text="Check for real, appropriate photos" />
        <Queue to="/admin/reports" icon={Flag} label="Open reports" count={d?.reports_open} text="Safety first — handle these quickly" />
      </div>

      <h2 className="mb-3 mt-8 text-sm font-semibold text-slate-900">Members</h2>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Tile label="Total profiles" value={d?.members_total} />
        <Tile label="Live profiles" value={d?.profiles_live} note="Visible in matches" />
        <Tile label="New today" value={d?.signups_today} note={`${d?.signups_7d ?? "—"} in the last 7 days`} />
        <Tile label="Premium members" value={d?.premium_members} />
      </div>

      <h2 className="mb-3 mt-8 text-sm font-semibold text-slate-900">Activity today</h2>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Tile label="Interests sent" value={d?.interests_today} />
        <Tile label="Messages sent" value={d?.messages_today} />
      </div>

      <Panel title="Moderation guidelines" className="mt-8">
        <ul className="grid gap-3 p-5 text-sm text-slate-600 md:grid-cols-2">
          <li>• <strong className="text-slate-800">Approve</strong> only real, complete profiles with no contact details in the text.</li>
          <li>• <strong className="text-slate-800">Ask for changes</strong> with a clear, polite reason — the member sees it.</li>
          <li>• <strong className="text-slate-800">Money requests and dowry</strong> are suspend-first; admins decide bans.</li>
          <li>• <strong className="text-slate-800">Reveal a phone</strong> only when needed, with a reason — it's logged.</li>
        </ul>
      </Panel>
    </AdminLayout>
  );
}
