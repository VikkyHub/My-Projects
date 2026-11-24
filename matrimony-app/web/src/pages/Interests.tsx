import { useQuery } from "@tanstack/react-query";
import { Check, Clock, Heart, Inbox, MessageCircle, Send, Sparkles, X } from "lucide-react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { api } from "../api/client";
import type { InterestItem, ProfileCard } from "../api/types";
import AppShell from "../components/AppShell";
import Avatar from "../components/Avatar";
import { Empty, Tabs } from "../components/Kit";
import MatchCard from "../components/MatchCard";
import { Badge, Button, ErrorBox } from "../components/ui";
import { heightLabel } from "../lib/labels";
import { timeAgo, useCounts, useRespond } from "../lib/social";

type Box = "received" | "sent" | "accepted" | "shortlist";

export default function Interests() {
  const [params, setParams] = useSearchParams();
  const box = (params.get("tab") as Box) || "received";
  const counts = useCounts();
  const list = useQuery({
    queryKey: ["interests", box],
    queryFn: () => api<InterestItem[]>(`/interests?box=${box}`),
    enabled: box !== "shortlist",
  });
  const short = useQuery({
    queryKey: ["shortlist"],
    queryFn: () => api<ProfileCard[]>("/shortlist"),
    enabled: box === "shortlist",
  });

  return (
    <AppShell>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="font-display text-3xl font-semibold sm:text-4xl">Interests</h1>
          <p className="mt-1 text-muted">People who want to connect with you, and those you've reached out to.</p>
        </div>
        {counts.data && (
          <p className="text-sm text-muted">
            <span className="font-semibold text-ink">{Math.max(0, counts.data.daily_limit - counts.data.sent_today)}</span> of{" "}
            {counts.data.daily_limit} interests left today
          </p>
        )}
      </div>

      <div className="mt-6 max-w-3xl">
        <Tabs
          value={box}
          onChange={(v) => setParams({ tab: v })}
          tabs={[
            { value: "received", label: "Received", icon: Inbox, count: counts.data?.received_pending },
            { value: "sent", label: "Sent", icon: Send },
            { value: "accepted", label: "Connected", icon: Check },
            { value: "shortlist", label: "Shortlisted", icon: Heart },
          ]}
        />
      </div>

      <div className="mt-6">
        {box === "shortlist" ? (
          short.isPending ? (
            <Skeleton />
          ) : short.data?.length ? (
            <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
              {short.data.map((p) => <MatchCard key={p.public_id} p={p} />)}
            </div>
          ) : (
            <Empty icon={Heart} title="No one shortlisted yet" text="Tap the heart on any profile to save it here for later." action={<Link to="/matches"><Button variant="secondary">Browse matches</Button></Link>} />
          )
        ) : list.isPending ? (
          <Skeleton />
        ) : list.error ? (
          <ErrorBox message={list.error.message} />
        ) : list.data?.length ? (
          <div className="grid gap-4 xl:grid-cols-2">
            {list.data.map((i) => <InterestRow key={i.id} i={i} />)}
          </div>
        ) : (
          <Empty
            icon={box === "received" ? Inbox : box === "sent" ? Send : Sparkles}
            title={{ received: "No new interests", sent: "You haven't sent any interests", accepted: "No connections yet" }[box]}
            text={{
              received: "When someone sends you an interest, it shows up here. A complete profile with photos gets noticed more.",
              sent: "Find someone you like in Matches and send an interest — it's the first step.",
              accepted: "When an interest is accepted, you're connected and can start chatting.",
            }[box]}
            action={<Link to="/matches"><Button variant="secondary"><Sparkles className="h-4 w-4" /> See matches</Button></Link>}
          />
        )}
      </div>
    </AppShell>
  );
}

function Skeleton() {
  return (
    <div className="grid gap-4 xl:grid-cols-2">
      {Array.from({ length: 4 }).map((_, i) => <div key={i} className="h-36 animate-pulse rounded-3xl bg-white/70" />)}
    </div>
  );
}

function InterestRow({ i }: { i: InterestItem }) {
  const p = i.profile;
  const respond = useRespond();
  const navigate = useNavigate();
  return (
    <article className="animate-rise flex gap-4 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 sm:gap-5 sm:p-5">
      <Link to={`/p/${p.public_id}`}>
        <Avatar name={p.name} seed={p.public_id} photo={p.photo_url} locked={p.photo_locked} premium={p.is_premium} rounded="rounded-2xl" className="h-28 w-24 sm:h-32 sm:w-28" text="text-3xl" />
      </Link>
      <div className="flex min-w-0 flex-1 flex-col">
        <div className="flex items-start justify-between gap-2">
          <Link to={`/p/${p.public_id}`} className="min-w-0">
            <h3 className="truncate font-display text-lg font-semibold hover:text-brand-700">{p.name}, {p.age}</h3>
          </Link>
          <span className="shrink-0 text-xs text-muted">{timeAgo(i.responded_at ?? i.created_at)}</span>
        </div>
        <p className="truncate text-sm text-muted">
          {[heightLabel(p.height_cm)?.split(" (")[0], p.community, p.city].filter(Boolean).join(" · ")}
        </p>
        <p className="truncate text-sm text-muted">{[p.occupation, p.education].filter(Boolean).join(" · ")}</p>
        {i.note && <p className="mt-2 line-clamp-2 text-sm italic text-ink/80">“{i.note}”</p>}

        <div className="mt-auto flex flex-wrap items-center gap-2 pt-3">
          {i.status === "pending" && i.direction === "received" && (
            <>
              <Button size="sm" loading={respond.isPending && respond.variables?.action === "accept"} onClick={() => respond.mutate({ id: i.id, action: "accept" })}>
                <Check className="h-4 w-4" /> Accept
              </Button>
              <Button size="sm" variant="secondary" onClick={() => respond.mutate({ id: i.id, action: "decline" })}>
                <X className="h-4 w-4" /> Decline
              </Button>
            </>
          )}
          {i.status === "pending" && i.direction === "sent" && (
            <>
              <Badge tone="amber" icon={Clock}>Awaiting reply</Badge>
              <Button size="sm" variant="ghost" onClick={() => respond.mutate({ id: i.id, action: "withdraw" })}>Withdraw</Button>
            </>
          )}
          {i.status === "declined" && <Badge tone="gray">Not interested</Badge>}
          {i.status === "accepted" && (
            <>
              <Badge tone="green" icon={Check}>Connected</Badge>
              <Button size="sm" onClick={() => navigate(`/messages/${p.conversation_id ?? ""}`)}>
                <MessageCircle className="h-4 w-4" /> Message
              </Button>
            </>
          )}
        </div>
        {respond.error && <p className="mt-2 text-xs text-red-600">{respond.error.message}</p>}
      </div>
    </article>
  );
}
