import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, CheckCircle2, X, Clock, Headphones, ImagePlus, Loader2, SendHorizontal, ShieldCheck, ThumbsDown, ThumbsUp, UserRound } from "lucide-react";
import { useLayoutEffect, useRef, useState } from "react";
import { api, mediaUrl } from "../api/client";
import type { SupportMsg, SupportView } from "../api/types";
import { LanguagePicker, TranslateButton } from "./Translatable";
import VoiceRecorder from "./VoiceRecorder";
import { cx } from "./ui";
import { RichText } from "../lib/richtext";

const STATUS = {
  bot: { label: "Assistant", cls: "bg-sky-50 text-sky-700 ring-sky-100", icon: Bot },
  waiting_team: { label: "Waiting for our team", cls: "bg-amber-50 text-amber-800 ring-amber-200", icon: Clock },
  answered: { label: "Team replied", cls: "bg-emerald-50 text-emerald-700 ring-emerald-200", icon: CheckCircle2 },
  closed: { label: "Closed", cls: "bg-sand text-muted ring-line", icon: CheckCircle2 },
} as const;

const time = (iso: string) => new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" });

function Avatar({ who }: { who: "bot" | "staff" }) {
  return who === "bot" ? (
    <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-gradient-to-br from-brand-500 to-brand-800 text-white shadow-sm">
      <Bot className="h-[18px] w-[18px]" />
    </span>
  ) : (
    <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-gradient-to-br from-gold-300 to-gold-500 text-brand-950 shadow-sm">
      <Headphones className="h-[18px] w-[18px]" />
    </span>
  );
}

export const SUPPORT_KEY = ["support"];

export function useSupport(enabled = true, poll = 30_000) {
  return useQuery({ queryKey: SUPPORT_KEY, queryFn: () => api<SupportView>("/support"), refetchInterval: poll, enabled });
}

/** True when the team has replied and the member hasn't opened help since. */
export function hasTeamReply(v?: SupportView) {
  return v?.ticket?.status === "answered" && v.messages.at(-1)?.sender === "staff";
}

/** The help chat. `compact` = floating panel version (with a close button). */
export default function HelpChat({ compact = false, onClose }: { compact?: boolean; onClose?: () => void }) {
  const qc = useQueryClient();
  const key = SUPPORT_KEY;
  const q = useSupport();
  const [text, setText] = useState("");
  const photoInput = useRef<HTMLInputElement>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const set = (v: SupportView) => qc.setQueryData(key, v);

  const send = useMutation({
    mutationFn: (p: { body?: string; intent?: string }) =>
      api<SupportView>("/support/messages", { method: "POST", body: JSON.stringify({ body: p.body ?? "", intent: p.intent ?? null }) }),
    onSuccess: (v) => { setText(""); set(v); },
  });
  const escalate = useMutation({ mutationFn: () => api<SupportView>("/support/escalate", { method: "POST" }), onSuccess: set });
  const feedback = useMutation({
    mutationFn: (p: { message_id: number; helpful: boolean }) => api<SupportView>("/support/feedback", { method: "POST", body: JSON.stringify(p) }),
    onSuccess: set,
  });
  const upload = useMutation({
    mutationFn: async (p: { kind: "photo" | "voice"; file: Blob; name: string; seconds?: number }) => {
      const fd = new FormData();
      fd.append("kind", p.kind);
      if (p.seconds) fd.append("duration_s", String(p.seconds));
      fd.append("file", p.file, p.name);
      return api<SupportView>("/support/attachments", { method: "POST", body: fd });
    },
    onSuccess: set,
  });
  const close = useMutation({ mutationFn: () => api<SupportView>("/support/close", { method: "POST" }), onSuccess: set });

  const v = q.data;
  const msgs = v?.messages ?? [];
  const status = v?.ticket?.status ?? "bot";
  const st = STATUS[status];
  const busy = send.isPending || upload.isPending || escalate.isPending || feedback.isPending;
  const error = (send.error ?? upload.error ?? escalate.error)?.message;
  const lastBot = [...msgs].reverse().find((m) => m.sender !== "member");

  useLayoutEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [msgs.length, busy]);

  return (
      <div
        className={cx(
          "flex flex-col overflow-hidden bg-white",
          compact
            ? "h-full"
            : "mx-auto h-[calc(100vh-10rem)] min-h-[34rem] max-w-4xl rounded-[2rem] shadow-soft ring-1 ring-line/70 md:h-[calc(100vh-8.5rem)]",
        )}
      >
        {/* Header */}
        <header className={cx("hero-rani relative flex flex-wrap items-center text-white", compact ? "gap-3 px-4 py-3" : "gap-4 px-5 py-4 sm:px-6")}>
          <span className={cx("grid place-items-center rounded-2xl bg-white/15 ring-1 ring-white/25", compact ? "h-10 w-10" : "h-12 w-12")}>
            <Bot className={cx("text-gold-200", compact ? "h-5 w-5" : "h-6 w-6")} />
          </span>
          <div className="min-w-0 flex-1">
            <h1 className={cx("font-display font-semibold text-white", compact ? "text-lg" : "text-xl")}>Help & support</h1>
            {compact ? (
              <span className={cx("mt-0.5 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold ring-1", st.cls)}>
                <st.icon className="h-3 w-3" /> {st.label}
              </span>
            ) : (
              <p className="text-sm text-white/75">Instant answers from our assistant — and real people when you need them.</p>
            )}
          </div>
          <div className="flex items-center gap-2">
            {!compact && (
              <span className={cx("inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold ring-1", st.cls)}>
                <st.icon className="h-3.5 w-3.5" /> {st.label}
              </span>
            )}
            <LanguagePicker />
            {onClose && (
              <button onClick={onClose} aria-label="Close help" className="grid h-9 w-9 place-items-center rounded-full bg-white/15 text-white ring-1 ring-white/25 transition hover:bg-white/25">
                <X className="h-5 w-5" />
              </button>
            )}
          </div>
        </header>

        {/* Thread */}
        <div className="pattern-soft flex-1 overflow-y-auto px-4 py-5 sm:px-6">
          <div className="mx-auto mb-5 flex max-w-lg items-start gap-2.5 rounded-2xl bg-teal-50 px-4 py-3 text-xs leading-relaxed text-teal-900 ring-1 ring-teal-100">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-teal-600" />
            Our team will never ask for your OTP, password or payment details here.
          </div>

          {/* Welcome (always shown first) */}
          <BotBubble who="bot" name="Assistant">
            <RichText text={v?.welcome ?? "Hi! How can I help you today?"} />
          </BotBubble>
          {msgs.length === 0 && v && <Chips items={v.suggestions} onPick={(k) => send.mutate({ intent: k })} disabled={busy} />}

          {msgs.map((m) => (
            <Message
              key={m.id}
              m={m}
              last={m.id === lastBot?.id}
              busy={busy}
              onChip={(k) => (k === "talk" ? escalate.mutate() : send.mutate({ intent: k }))}
              onFeedback={(helpful) => feedback.mutate({ message_id: m.id, helpful })}
            />
          ))}
          {busy && (
            <div className="mb-3 flex items-center gap-2 pl-11 text-xs text-muted">
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> {upload.isPending ? "Uploading…" : "Typing…"}
            </div>
          )}
          {status === "waiting_team" && (
            <p className="mx-auto my-4 flex max-w-md items-center justify-center gap-2 rounded-full bg-amber-50 px-4 py-2 text-center text-xs font-semibold text-amber-900 ring-1 ring-amber-200">
              <Clock className="h-3.5 w-3.5" /> A team member will reply here — you'll see it as soon as they do.
            </p>
          )}
          <div ref={bottom} />
        </div>

        {/* Composer */}
        {error && <p className="bg-red-50 px-5 py-2 text-sm text-red-700">{error}</p>}
        <form
          className="flex items-end gap-2 border-t border-line bg-white p-3 sm:p-4"
          onSubmit={(e) => {
            e.preventDefault();
            if (text.trim()) send.mutate({ body: text.trim() });
          }}
        >
          <button type="button" onClick={() => photoInput.current?.click()} disabled={busy} aria-label="Send a photo or screenshot" title="Send a photo or screenshot"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full text-brand-600 ring-1 ring-line transition hover:bg-brand-50 disabled:opacity-40">
            <ImagePlus className="h-5 w-5" />
          </button>
          <input ref={photoInput} type="file" accept="image/jpeg,image/png,image/webp" hidden
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) upload.mutate({ kind: "photo", file: f, name: f.name });
              e.target.value = "";
            }} />
          <VoiceRecorder disabled={busy} onSend={(blob, seconds) => upload.mutate({ kind: "voice", file: blob, name: blob.type.includes("mp4") ? "voice.m4a" : "voice.webm", seconds })} />
          <textarea
            rows={1}
            value={text}
            maxLength={2000}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                if (text.trim()) send.mutate({ body: text.trim() });
              }
            }}
            placeholder="Type your question…"
            className="max-h-32 min-h-11 flex-1 resize-none rounded-3xl bg-sand/60 px-5 py-3 text-[15px] outline-none ring-1 ring-transparent focus:bg-white focus:ring-brand-400"
          />
          <button type="submit" disabled={!text.trim() || busy} aria-label="Send"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-gradient-to-br from-brand-600 to-brand-700 text-white shadow-glow transition hover:scale-105 disabled:opacity-40 disabled:shadow-none">
            <SendHorizontal className="h-5 w-5" />
          </button>
        </form>
        <div className="flex items-center justify-between gap-3 bg-white px-5 pb-3 text-xs text-muted">
          <span className={compact ? "hidden" : ""}>Photos, screenshots and voice notes go to our team.</span>
          {status !== "waiting_team" ? (
            <button onClick={() => escalate.mutate()} disabled={busy} className="inline-flex items-center gap-1 font-semibold text-brand-700 hover:underline">
              <UserRound className="h-3.5 w-3.5" /> Talk to a person
            </button>
          ) : (
            v?.ticket && <button onClick={() => close.mutate()} className="font-semibold text-muted hover:text-ink">My problem is solved — close</button>
          )}
        </div>
      </div>
  );
}

function BotBubble({ who, name, children, t }: { who: "bot" | "staff"; name: string; children: React.ReactNode; t?: string }) {
  return (
    <div className="mb-3 flex items-end gap-2">
      <Avatar who={who} />
      <div className={cx("max-w-[85%] rounded-3xl rounded-bl-lg px-4 py-3 text-[15px] leading-relaxed shadow-sm sm:max-w-[70%]",
        who === "bot" ? "bg-white text-ink ring-1 ring-line" : "bg-gold-50 text-ink ring-1 ring-gold-200")}>
        <p className="mb-1 text-[11px] font-bold uppercase tracking-wider text-muted">{name}</p>
        {children}
        {t && <p className="mt-1 text-right text-[11px] text-muted">{time(t)}</p>}
      </div>
    </div>
  );
}

function Chips({ items, onPick, disabled }: { items: { key: string; title: string }[]; onPick: (k: string) => void; disabled?: boolean }) {
  return (
    <div className="mb-4 flex flex-wrap gap-2 pl-11">
      {items.map((c) => (
        <button key={c.key} disabled={disabled} onClick={() => onPick(c.key)}
          className="rounded-full bg-white px-3.5 py-1.5 text-sm font-semibold text-brand-700 shadow-sm ring-1 ring-brand-200 transition hover:bg-brand-50 disabled:opacity-50">
          {c.title}
        </button>
      ))}
    </div>
  );
}

function Media({ m, dark }: { m: SupportMsg; dark?: boolean }) {
  if (m.kind === "photo" && m.media_url)
    return (
      <a href={mediaUrl(m.media_url)} target="_blank" rel="noreferrer">
        <img src={mediaUrl(m.media_url)} alt="Shared screenshot" className="max-h-64 rounded-2xl object-cover" />
      </a>
    );
  if (m.kind === "voice" && m.media_url)
    return (
      <div className="flex items-center gap-2">
        <audio src={mediaUrl(m.media_url)} controls preload="metadata" className="h-10 w-60 max-w-full" />
        {m.duration_s && <span className={cx("text-xs", dark ? "text-white/80" : "text-muted")}>{m.duration_s}s</span>}
      </div>
    );
  return null;
}

function Message({ m, last, busy, onChip, onFeedback }: { m: SupportMsg; last: boolean; busy: boolean; onChip: (k: string) => void; onFeedback: (helpful: boolean) => void }) {
  if (m.sender === "member")
    return (
      <div className="mb-3 flex justify-end">
        <div className="max-w-[85%] rounded-3xl rounded-br-lg bg-gradient-to-br from-brand-600 to-brand-700 px-4 py-2.5 text-[15px] text-white shadow-sm sm:max-w-[70%]">
          {m.kind === "text" ? <p className="whitespace-pre-wrap break-words">{m.body}</p> : <Media m={m} dark />}
          <p className="mt-1 text-right text-[11px] text-white/70">{time(m.created_at)}</p>
        </div>
      </div>
    );
  const who = m.sender === "staff" ? "staff" : "bot";
  return (
    <>
      <BotBubble who={who} name={who === "staff" ? `${m.staff_name ?? "Support team"} · Support team` : "Assistant"} t={m.created_at}>
        {m.kind === "text" ? <RichText text={m.body ?? ""} /> : <Media m={m} />}
        {m.kind === "text" && m.body && <TranslateButton text={m.body} />}
        {m.meta?.ask_feedback && last && (
          <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-line pt-2.5 text-xs">
            <span className="text-muted">Did this help?</span>
            <button disabled={busy} onClick={() => onFeedback(true)} className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 font-semibold text-emerald-700 ring-1 ring-emerald-200 hover:bg-emerald-50"><ThumbsUp className="h-3.5 w-3.5" /> Yes</button>
            <button disabled={busy} onClick={() => onFeedback(false)} className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 font-semibold text-brand-700 ring-1 ring-brand-200 hover:bg-brand-50"><ThumbsDown className="h-3.5 w-3.5" /> No, talk to a person</button>
          </div>
        )}
      </BotBubble>
      {last && !!m.meta?.suggestions?.length && <Chips items={m.meta.suggestions} onPick={onChip} disabled={busy} />}
    </>
  );
}
