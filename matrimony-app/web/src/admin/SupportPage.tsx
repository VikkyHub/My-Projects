import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Bot, CheckCircle2, Clock, Headphones, LifeBuoy, SendHorizontal, UserRound } from "lucide-react";
import { useLayoutEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { mediaUrl } from "../api/client";
import type { SupportMsg } from "../api/types";
import { LanguagePicker, TranslateButton } from "../components/Translatable";
import { Button, cx } from "../components/ui";
import { RichText } from "../lib/richtext";
import AdminLayout from "./AdminLayout";
import { PageHead, Seg, aapi, when } from "./ui";

type Status = "waiting_team" | "answered" | "bot" | "closed";
interface Row {
  id: string;
  status: Status;
  subject: string | null;
  topic: string | null;
  member: { public_id: string | null; name: string; phone: string | null; status: string | null; chat_muted_until: string | null };
  last_message: string | null;
  last_message_at: string | null;
  escalated_at: string | null;
  unread: number;
  urgent: boolean;
}
interface Detail {
  ticket: Row;
  messages: SupportMsg[];
}

const CANNED = [
  "Thanks for reaching out! I'm looking into this now.",
  "Could you share a screenshot of what you see? It'll help us fix this faster.",
  "This is fixed now — please refresh the app and try again.",
  "Your profile has been reviewed and is now live. Good luck!",
];

export default function SupportPage() {
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const status = (params.get("status") as Status) || "waiting_team";
  const sel = params.get("t");
  const list = useQuery({ queryKey: ["admin", "support", status], queryFn: () => aapi<Row[]>(`/admin/support?status=${status}`), refetchInterval: 15_000 });
  const detail = useQuery({ queryKey: ["admin", "support-ticket", sel], queryFn: () => aapi<Detail>(`/admin/support/${sel}`), enabled: !!sel, refetchInterval: 10_000 });
  const [reply, setReply] = useState("");
  const bottom = useRef<HTMLDivElement>(null);
  const done = (d: Detail) => {
    qc.setQueryData(["admin", "support-ticket", sel], d);
    qc.invalidateQueries({ queryKey: ["admin", "support"] });
    qc.invalidateQueries({ queryKey: ["admin", "stats"] });
  };
  const send = useMutation({
    mutationFn: (close: boolean) => aapi<Detail>(`/admin/support/${sel}/reply`, { method: "POST", body: JSON.stringify({ body: reply.trim(), close }) }),
    onSuccess: (d) => { setReply(""); done(d); },
  });
  const close = useMutation({ mutationFn: () => aapi<Detail>(`/admin/support/${sel}/close`, { method: "POST" }), onSuccess: done });

  useLayoutEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [detail.data?.messages.length]);

  const d = detail.data;
  return (
    <AdminLayout>
      <PageHead title="Support inbox" sub="Questions the assistant couldn't answer, and members who asked for a person. Oldest first.">
        <LanguagePicker />
      </PageHead>
      <Seg value={status} onChange={(v) => setParams({ status: v })}
        options={[{ value: "waiting_team", label: "Waiting for us" }, { value: "answered", label: "Replied" }, { value: "bot", label: "Assistant only" }, { value: "closed", label: "Closed" }]} />

      <div className="mt-5 grid gap-5 xl:grid-cols-[380px_1fr]">
        {/* list */}
        <section className="overflow-hidden rounded-3xl bg-white shadow-soft ring-1 ring-line/70">
          {list.data?.length === 0 && <p className="p-10 text-center text-sm text-muted">{status === "waiting_team" ? "No one is waiting — all caught up." : "Nothing here."}</p>}
          <ul className="max-h-[70vh] divide-y divide-line overflow-y-auto">
            {list.data?.map((r) => (
              <li key={r.id}>
                <button onClick={() => setParams({ status, t: r.id })}
                  className={cx("w-full px-5 py-4 text-left transition hover:bg-brand-50/40", sel === r.id && "bg-brand-50/70")}>
                  <div className="flex items-center justify-between gap-2">
                    <p className={cx("truncate", r.unread ? "font-bold" : "font-semibold")}>{r.member.name}</p>
                    <span className="shrink-0 text-xs text-muted">{when(r.last_message_at)}</span>
                  </div>
                  <p className="truncate text-sm text-muted">{r.last_message ?? r.subject}</p>
                  <div className="mt-1.5 flex flex-wrap gap-1.5">
                    {r.urgent && <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2 py-0.5 text-[11px] font-bold text-red-700 ring-1 ring-red-200"><AlertTriangle className="h-3 w-3" /> Urgent</span>}
                    {r.topic && <span className="rounded-full bg-sand px-2 py-0.5 text-[11px] font-semibold text-muted">{r.topic}</span>}
                    {r.unread > 0 && <span className="rounded-full bg-brand-600 px-2 py-0.5 text-[11px] font-bold text-white">{r.unread} new</span>}
                  </div>
                </button>
              </li>
            ))}
          </ul>
        </section>

        {/* thread */}
        <section className="flex min-h-[32rem] flex-col overflow-hidden rounded-3xl bg-white shadow-soft ring-1 ring-line/70">
          {!d ? (
            <div className="grid flex-1 place-items-center p-10 text-center">
              <div>
                <span className="mx-auto grid h-16 w-16 place-items-center rounded-3xl bg-gradient-to-br from-brand-500 to-brand-800 text-white shadow-glow"><LifeBuoy className="h-8 w-8" /></span>
                <p className="mt-4 font-display text-xl font-semibold">Pick a conversation</p>
                <p className="mt-1 text-sm text-muted">Translate buttons help with messages in other languages.</p>
              </div>
            </div>
          ) : (
            <>
              <header className="flex flex-wrap items-center gap-3 border-b border-line px-6 py-4">
                <div className="min-w-0 flex-1">
                  <p className="font-display text-lg font-semibold">{d.ticket.member.name}</p>
                  <p className="text-xs text-muted">
                    {d.ticket.member.public_id ? <Link to={`/admin/profiles/${d.ticket.member.public_id}`} className="font-semibold text-brand-700 hover:underline">{d.ticket.member.public_id}</Link> : "No profile yet"}
                    {" · "}{d.ticket.member.phone}
                    {d.ticket.member.chat_muted_until && new Date(d.ticket.member.chat_muted_until) > new Date() && <span className="ml-2 font-semibold text-red-700">· Chat muted until {when(d.ticket.member.chat_muted_until)}</span>}
                  </p>
                </div>
                {d.ticket.status !== "closed" && <Button size="sm" variant="secondary" loading={close.isPending} onClick={() => close.mutate()}><CheckCircle2 className="h-4 w-4" /> Close</Button>}
              </header>
              <div className="pattern-soft flex-1 space-y-3 overflow-y-auto px-6 py-5">
                {d.messages.map((m) => <Msg key={m.id} m={m} />)}
                <div ref={bottom} />
              </div>
              {d.ticket.status !== "closed" ? (
                <div className="border-t border-line p-4">
                  <div className="mb-2 flex flex-wrap gap-1.5">
                    {CANNED.map((c) => (
                      <button key={c} onClick={() => setReply(c)} className="rounded-full bg-sand/70 px-3 py-1 text-xs font-medium text-ink/80 hover:bg-brand-50">{c.length > 42 ? c.slice(0, 40) + "…" : c}</button>
                    ))}
                  </div>
                  <form className="flex items-end gap-2" onSubmit={(e) => { e.preventDefault(); if (reply.trim()) send.mutate(false); }}>
                    <textarea rows={2} value={reply} onChange={(e) => setReply(e.target.value)} placeholder={`Reply to ${d.ticket.member.name.split(" ")[0]}…`}
                      className="min-h-12 flex-1 resize-none rounded-3xl bg-sand/60 px-5 py-3 text-[15px] outline-none focus:bg-white focus:ring-2 focus:ring-brand-400" />
                    <div className="flex flex-col gap-1.5">
                      <Button type="submit" size="sm" disabled={!reply.trim()} loading={send.isPending && !send.variables}><SendHorizontal className="h-4 w-4" /> Reply</Button>
                      <Button type="button" size="sm" variant="secondary" disabled={!reply.trim()} onClick={() => send.mutate(true)}>Reply & close</Button>
                    </div>
                  </form>
                  {send.error && <p className="mt-2 text-sm text-red-700">{send.error.message}</p>}
                </div>
              ) : (
                <p className="border-t border-line bg-sand/40 p-4 text-center text-sm text-muted">This conversation is closed. If the member writes again, a new one opens.</p>
              )}
            </>
          )}
        </section>
      </div>
    </AdminLayout>
  );
}

function Msg({ m }: { m: SupportMsg }) {
  const member = m.sender === "member";
  const Icon = m.sender === "bot" ? Bot : m.sender === "staff" ? Headphones : UserRound;
  return (
    <div className={cx("flex items-end gap-2", member ? "justify-start" : "justify-end")}>
      {member && <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-sand text-muted"><UserRound className="h-4 w-4" /></span>}
      <div className={cx("max-w-[78%] rounded-3xl px-4 py-2.5 text-sm shadow-sm",
        member ? "rounded-bl-lg bg-white ring-1 ring-line" : m.sender === "bot" ? "rounded-br-lg bg-sky-50 ring-1 ring-sky-100" : "rounded-br-lg bg-gold-50 ring-1 ring-gold-200")}>
        <p className="mb-1 flex items-center gap-1 text-[11px] font-bold uppercase tracking-wider text-muted">
          {!member && <Icon className="h-3 w-3" />}{member ? "Member" : m.sender === "bot" ? "Assistant" : m.staff_name}
          <span className="ml-auto font-normal normal-case tracking-normal">{when(m.created_at)}</span>
        </p>
        {m.kind === "photo" && m.media_url ? (
          <a href={mediaUrl(m.media_url)} target="_blank" rel="noreferrer"><img src={mediaUrl(m.media_url)} alt="Member's screenshot" className="max-h-72 rounded-2xl" /></a>
        ) : m.kind === "voice" && m.media_url ? (
          <div className="flex items-center gap-2"><audio src={mediaUrl(m.media_url)} controls preload="metadata" className="h-10 w-64" /><span className="text-xs text-muted">{m.duration_s}s</span></div>
        ) : (
          <>
            <div className="leading-relaxed"><RichText text={m.body ?? ""} /></div>
            {member && m.body && <TranslateButton text={m.body} />}
          </>
        )}
        {m.meta?.helpful === false && <p className="mt-1 flex items-center gap-1 text-[11px] font-semibold text-amber-800"><Clock className="h-3 w-3" /> Member said this didn't help</p>}
      </div>
    </div>
  );
}
