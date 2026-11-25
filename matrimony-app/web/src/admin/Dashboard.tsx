import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Crown, Flag, Heart, Image, LifeBuoy, MessageCircle, Sparkles, UserCheck, UserPlus, Users, type LucideIcon } from "lucide-react";
import { Link } from "react-router-dom";
import { IconChip, type ChipColor } from "../components/ui";
import AdminLayout from "./AdminLayout";
import type { Stats } from "./types";
import { PageHead, Panel, aapi, useStaff } from "./ui";

/** Headline numbers are stat tiles (not charts): label, value in text ink, short context. */
function Tile({ label, value, note, icon: Icon, color }: { label: string; value?: number; note?: string; icon: LucideIcon; color: ChipColor }) {
  return (
    <div className="rounded-3xl bg-white p-6 shadow-soft ring-1 ring-line/70">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-muted">{label}</p>
        <IconChip icon={Icon} color={color} />
      </div>
      <p className="mt-3 font-display text-4xl font-semibold tabular-nums text-ink">{value?.toLocaleString("en-IN") ?? "—"}</p>
      {note && <p className="mt-1 text-xs text-muted">{note}</p>}
    </div>
  );
}

function Queue({ to, icon: Icon, label, count, text }: { to: string; icon: LucideIcon; label: string; count?: number; text: string }) {
  const has = !!count;
  return (
    <Link
      to={to}
      className={`group relative flex items-center gap-4 overflow-hidden rounded-3xl p-6 shadow-soft ring-1 transition hover:-translate-y-0.5 hover:shadow-xl ${
        has ? "bg-gradient-to-br from-brand-50 via-white to-gold-50 ring-brand-100" : "bg-white ring-line/70"
      }`}
    >
      <span className={`grid h-12 w-12 shrink-0 place-items-center rounded-2xl ${has ? "bg-gradient-to-br from-brand-500 to-brand-700 text-white shadow-glow" : "bg-sand text-muted"}`}>
        <Icon className="h-6 w-6" />
      </span>
      <div className="flex-1">
        <p className="font-display text-3xl font-semibold tabular-nums text-ink">{count ?? "—"}</p>
        <p className="text-sm font-semibold text-ink">{label}</p>
        <p className="text-xs text-muted">{has ? text : "All clear — nothing waiting"}</p>
      </div>
      <ArrowRight className="h-5 w-5 text-brand-400 transition group-hover:translate-x-1 group-hover:text-brand-600" />
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

      <div className="grid gap-5 md:grid-cols-2 2xl:grid-cols-4">
        <Queue to="/admin/profiles?status=pending_review" icon={UserCheck} label="Profiles to review" count={d?.profiles_pending} text="Oldest first — approve or ask for changes" />
        <Queue to="/admin/photos" icon={Image} label="Photos to review" count={d?.photos_pending} text="Check for real, appropriate photos" />
        <Queue to="/admin/reports" icon={Flag} label="Open reports" count={d?.reports_open} text="Safety first — handle these quickly" />
        <Queue to="/admin/support" icon={LifeBuoy} label="Help requests" count={d?.support_waiting} text="Members waiting for a person" />
      </div>

      <h2 className="mb-4 mt-10 font-display text-xl font-semibold">Members</h2>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Tile label="Total profiles" value={d?.members_total} icon={Users} color="brand" />
        <Tile label="Live profiles" value={d?.profiles_live} note="Visible in matches" icon={Sparkles} color="teal" />
        <Tile label="New today" value={d?.signups_today} note={`${d?.signups_7d ?? "—"} in the last 7 days`} icon={UserPlus} color="violet" />
        <Tile label="Premium members" value={d?.premium_members} icon={Crown} color="gold" />
      </div>

      <h2 className="mb-4 mt-10 font-display text-xl font-semibold">Activity today</h2>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Tile label="Interests sent" value={d?.interests_today} icon={Heart} color="rose" />
        <Tile label="Messages sent" value={d?.messages_today} icon={MessageCircle} color="sky" />
      </div>

      <Panel title="Moderation guidelines" className="mt-10">
        <ul className="grid gap-3 p-6 text-sm text-ink/75 md:grid-cols-2">
          <li>• <strong className="text-ink">Approve</strong> only real, complete profiles with no contact details in the text.</li>
          <li>• <strong className="text-ink">Ask for changes</strong> with a clear, polite reason — the member sees it.</li>
          <li>• <strong className="text-ink">Money requests and dowry</strong> are suspend-first; admins decide bans.</li>
          <li>• <strong className="text-ink">Reveal a phone</strong> only when needed, with a reason — it's logged.</li>
        </ul>
      </Panel>
    </AdminLayout>
  );
}
