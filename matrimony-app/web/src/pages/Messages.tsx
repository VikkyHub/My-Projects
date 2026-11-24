import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, ArrowLeft, Check, CheckCheck, Crown, Flag, Lock, MessageCircle, SendHorizontal, ShieldCheck } from "lucide-react";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { api } from "../api/client";
import type { Conversation, Message, MyProfile } from "../api/types";
import AppShell from "../components/AppShell";
import Avatar from "../components/Avatar";
import { Empty } from "../components/Kit";
import { Button, cx } from "../components/ui";
import { onMessage } from "../lib/realtime";
import { timeAgo } from "../lib/social";
import { ReportModal } from "./ProfileView";

export default function Messages() {
  const { convId } = useParams();
  const convs = useQuery({ queryKey: ["conversations"], queryFn: () => api<Conversation[]>("/conversations") });
  const me = useQuery({ queryKey: ["profile", "me"], queryFn: () => api<MyProfile>("/profiles/me") });
  const active = convs.data?.find((c) => c.id === convId);

  return (
    <AppShell>
      <div className="flex h-[calc(100vh-10rem)] min-h-[32rem] overflow-hidden rounded-[2rem] bg-white shadow-soft ring-1 ring-line/70 md:h-[calc(100vh-8.5rem)]">
        {/* Conversation list */}
        <aside className={cx("w-full flex-col border-r border-line md:flex md:w-80 lg:w-96", convId ? "hidden" : "flex")}>
          <div className="border-b border-line px-5 py-5">
            <h1 className="font-display text-2xl font-semibold">Messages</h1>
            <p className="text-sm text-muted">Chats open when an interest is accepted.</p>
          </div>
          <div className="flex-1 overflow-y-auto">
            {convs.isPending &&
              Array.from({ length: 5 }).map((_, i) => <div key={i} className="m-3 h-16 animate-pulse rounded-2xl bg-sand/60" />)}
            {convs.data?.length === 0 && (
              <div className="p-6 text-center text-sm text-muted">
                No conversations yet.{" "}
                <Link to="/interests" className="font-semibold text-brand-700">Check your interests</Link>
              </div>
            )}
            {convs.data?.map((c) => (
              <Link
                key={c.id}
                to={`/messages/${c.id}`}
                className={cx(
                  "flex items-center gap-3 border-l-4 px-4 py-3.5 transition",
                  c.id === convId ? "border-brand-600 bg-brand-50/70" : "border-transparent hover:bg-sand/50",
                )}
              >
                <Avatar name={c.profile.name} seed={c.profile.public_id} photo={c.profile.photo_url} className="h-12 w-12" text="text-base" premium={c.profile.is_premium} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-baseline justify-between gap-2">
                    <p className={cx("truncate", c.unread ? "font-bold" : "font-semibold")}>{c.profile.name}</p>
                    <span className="shrink-0 text-xs text-muted">{timeAgo(c.last_message_at)}</span>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <p className={cx("truncate text-sm", c.unread ? "font-semibold text-ink" : "text-muted")}>
                      {c.last_message ? `${c.last_from_me ? "You: " : ""}${c.last_message}` : c.can_chat ? "Say hello 👋" : c.blocked_reason === "premium_required" ? "Connected · Premium to chat" : "Conversation closed"}
                    </p>
                    {c.unread > 0 && (
                      <span className="grid h-5 min-w-5 place-items-center rounded-full bg-brand-600 px-1.5 text-[11px] font-bold text-white">{c.unread}</span>
                    )}
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </aside>

        {/* Thread */}
        <section className={cx("min-w-0 flex-1 flex-col", convId ? "flex" : "hidden md:flex")}>
          {active && me.data ? (
            <Thread key={active.id} conv={active} myId={me.data.public_id} />
          ) : convId && convs.isSuccess ? (
            <div className="grid flex-1 place-items-center p-6">
              <Empty icon={MessageCircle} title="Conversation not found" text="It may have been closed." />
            </div>
          ) : (
            <div className="pattern-soft grid flex-1 place-items-center p-6">
              <div className="text-center">
                <span className="mx-auto grid h-20 w-20 place-items-center rounded-[1.75rem] bg-gradient-to-br from-brand-500 to-brand-800 text-white shadow-glow">
                  <MessageCircle className="h-9 w-9" />
                </span>
                <h2 className="mt-5 font-display text-2xl font-semibold">Your conversations</h2>
                <p className="mt-2 max-w-xs text-sm text-muted">Choose a chat to start talking. Be yourself — and take things at your own pace.</p>
              </div>
            </div>
          )}
        </section>
      </div>
    </AppShell>
  );
}

function dayLabel(iso: string) {
  const d = new Date(iso);
  const today = new Date();
  const y = new Date();
  y.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString()) return "Today";
  if (d.toDateString() === y.toDateString()) return "Yesterday";
  return d.toLocaleDateString("en-IN", { day: "numeric", month: "long" });
}

function Thread({ conv, myId }: { conv: Conversation; myId: string }) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [text, setText] = useState("");
  const [reporting, setReporting] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);
  const key = ["messages", conv.id];
  const msgs = useQuery({ queryKey: key, queryFn: () => api<Message[]>(`/conversations/${conv.id}/messages`) });

  // Live messages for this conversation
  useEffect(
    () =>
      onMessage((m) => {
        if (m.conversation_id !== conv.id) return;
        qc.setQueryData<Message[]>(key, (old = []) => (old.some((x) => x.id === m.id) ? old : [...old, m]));
        if (m.sender_public_id !== myId) api(`/conversations/${conv.id}/read`, { method: "POST" }).catch(() => undefined);
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [conv.id, myId],
  );

  // Mark as read on open
  useEffect(() => {
    if (conv.unread > 0)
      api(`/conversations/${conv.id}/read`, { method: "POST" }).then(() => {
        qc.invalidateQueries({ queryKey: ["conversations"] });
        qc.invalidateQueries({ queryKey: ["counts"] });
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conv.id]);

  useLayoutEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [msgs.data?.length]);

  const send = useMutation({
    mutationFn: (body: string) => api<Message>(`/conversations/${conv.id}/messages`, { method: "POST", body: JSON.stringify({ body }) }),
    onSuccess: (m) => {
      setText("");
      qc.setQueryData<Message[]>(key, (old = []) => (old.some((x) => x.id === m.id) ? old : [...old, m]));
      qc.invalidateQueries({ queryKey: ["conversations"] });
    },
  });

  const p = conv.profile;
  const list = msgs.data ?? [];
  const theirLastFlag = [...list].reverse().find((m) => m.sender_public_id !== myId && m.flagged);

  return (
    <>
      {/* Header */}
      <header className="flex items-center gap-3 border-b border-line px-4 py-3 sm:px-6">
        <button onClick={() => navigate("/messages")} className="grid h-9 w-9 place-items-center rounded-full hover:bg-sand md:hidden" aria-label="Back">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <Link to={`/p/${p.public_id}`} className="flex min-w-0 flex-1 items-center gap-3">
          <Avatar name={p.name} seed={p.public_id} photo={p.photo_url} className="h-11 w-11" text="text-base" />
          <div className="min-w-0">
            <p className="truncate font-semibold">{p.name}</p>
            <p className="truncate text-xs text-muted">{p.last_active ?? [p.age + " yrs", p.city].filter(Boolean).join(" · ")}</p>
          </div>
        </Link>
        <Button variant="ghost" size="sm" onClick={() => setReporting(true)} aria-label="Report">
          <Flag className="h-4 w-4" />
        </Button>
      </header>

      {/* Body */}
      <div className="pattern-soft flex-1 overflow-y-auto px-4 py-5 sm:px-6">
        <div className="mx-auto mb-5 flex max-w-md items-start gap-2.5 rounded-2xl bg-teal-50 px-4 py-3 text-xs leading-relaxed text-teal-900 ring-1 ring-teal-100">
          <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-teal-600" />
          Never send money or share OTPs, bank details or your address. Meet in a public place and tell family where you'll be.
        </div>
        {list.map((m, idx) => {
          const mine = m.sender_public_id === myId;
          const newDay = idx === 0 || dayLabel(list[idx - 1].created_at) !== dayLabel(m.created_at);
          return (
            <div key={m.id}>
              {newDay && <p className="my-4 text-center text-xs font-semibold uppercase tracking-wider text-muted">{dayLabel(m.created_at)}</p>}
              <div className={cx("mb-2 flex", mine ? "justify-end" : "justify-start")}>
                <div
                  className={cx(
                    "max-w-[80%] rounded-3xl px-4 py-2.5 text-[15px] leading-relaxed shadow-sm sm:max-w-[65%]",
                    mine ? "rounded-br-lg bg-gradient-to-br from-brand-600 to-brand-700 text-white" : "rounded-bl-lg bg-white text-ink ring-1 ring-line",
                  )}
                >
                  <p className="whitespace-pre-wrap break-words">{m.body}</p>
                  <p className={cx("mt-1 flex items-center justify-end gap-1 text-[11px]", mine ? "text-white/70" : "text-muted")}>
                    {new Date(m.created_at).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" })}
                    {mine && (m.read_at ? <CheckCheck className="h-3.5 w-3.5 text-gold-200" /> : <Check className="h-3.5 w-3.5" />)}
                  </p>
                </div>
              </div>
            </div>
          );
        })}
        {list.length === 0 && msgs.isSuccess && conv.can_chat && (
          <p className="mt-10 text-center text-sm text-muted">You're connected with {p.first_name}. Say hello! 👋</p>
        )}
        <div ref={bottom} />
      </div>

      {theirLastFlag && (
        <div className="flex items-start gap-2.5 border-t border-amber-100 bg-amber-50 px-5 py-3 text-sm text-amber-900">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
          <span>
            A message here mentions money or contact details. <strong>Never send money</strong> to someone you haven't met.{" "}
            <button className="font-semibold underline" onClick={() => setReporting(true)}>Report</button>
          </span>
        </div>
      )}

      {/* Composer */}
      {conv.can_chat ? (
        <form
          className="flex items-end gap-2 border-t border-line bg-white p-3 sm:p-4"
          onSubmit={(e) => {
            e.preventDefault();
            if (text.trim()) send.mutate(text.trim());
          }}
        >
          <textarea
            rows={1}
            value={text}
            maxLength={2000}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                if (text.trim()) send.mutate(text.trim());
              }
            }}
            placeholder={`Message ${p.first_name}…`}
            className="max-h-32 min-h-12 flex-1 resize-none rounded-3xl bg-sand/60 px-5 py-3 text-[15px] outline-none ring-1 ring-transparent focus:bg-white focus:ring-brand-400"
          />
          <button
            type="submit"
            disabled={!text.trim() || send.isPending}
            aria-label="Send"
            className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-gradient-to-br from-brand-600 to-brand-700 text-white shadow-glow transition hover:scale-105 disabled:opacity-40 disabled:shadow-none"
          >
            <SendHorizontal className="h-5 w-5" />
          </button>
        </form>
      ) : conv.blocked_reason === "premium_required" ? (
        <div className="border-t border-gold-200 bg-gradient-to-r from-gold-50 to-brand-50 p-5 text-center">
          <p className="flex items-center justify-center gap-2 font-display text-lg font-semibold">
            <Crown className="h-5 w-5 text-gold-500" /> You're connected with {p.first_name}!
          </p>
          <p className="mx-auto mt-1 max-w-md text-sm text-ink/70">Chat unlocks when either of you has a Premium plan. Premium plans are launching soon.</p>
        </div>
      ) : (
        <div className="flex items-center justify-center gap-2 border-t border-line bg-sand/50 p-4 text-sm text-muted">
          <Lock className="h-4 w-4" /> This conversation is closed.
        </div>
      )}
      {send.error && <p className="bg-red-50 px-5 py-2 text-sm text-red-700">{send.error.message}</p>}

      <ReportModal open={reporting} onClose={() => setReporting(false)} publicId={p.public_id} name={p.first_name} />
    </>
  );
}
