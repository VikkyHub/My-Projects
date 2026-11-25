import { Mic, Send, Square, Trash2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { cx } from "./ui";

const MAX_SECONDS = 120;

function pickMime(): string {
  for (const m of ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"])
    if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(m)) return m;
  return "";
}

/** Tap to record, tap to stop, then send or discard. */
export default function VoiceRecorder({ onSend, disabled }: { onSend: (blob: Blob, seconds: number) => void; disabled?: boolean }) {
  const [state, setState] = useState<"idle" | "recording" | "ready">("idle");
  const [secs, setSecs] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const rec = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const blob = useRef<Blob | null>(null);
  const url = useRef<string | null>(null);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  const cleanup = () => {
    if (timer.current) clearInterval(timer.current);
    rec.current?.stream.getTracks().forEach((t) => t.stop());
  };
  useEffect(() => () => { cleanup(); if (url.current) URL.revokeObjectURL(url.current); }, []);

  const start = async () => {
    setError(null);
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined")
      return setError("Voice notes aren't supported in this browser");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mime = pickMime();
      const r = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      chunks.current = [];
      r.ondataavailable = (e) => e.data.size && chunks.current.push(e.data);
      r.onstop = () => {
        blob.current = new Blob(chunks.current, { type: r.mimeType || "audio/webm" });
        if (url.current) URL.revokeObjectURL(url.current);
        url.current = URL.createObjectURL(blob.current);
        setState("ready");
        cleanup();
      };
      rec.current = r;
      r.start();
      setSecs(0);
      setState("recording");
      timer.current = setInterval(() => setSecs((s) => {
        if (s + 1 >= MAX_SECONDS) r.stop();
        return s + 1;
      }), 1000);
    } catch {
      setError("Microphone permission was blocked. Allow it in the browser's address bar.");
    }
  };

  const mmss = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`;

  if (state === "idle")
    return (
      <div className="relative">
        <button type="button" onClick={start} disabled={disabled} aria-label="Record a voice note" title="Record a voice note"
          className="grid h-11 w-11 shrink-0 place-items-center rounded-full text-brand-600 ring-1 ring-line transition hover:bg-brand-50 disabled:opacity-40">
          <Mic className="h-5 w-5" />
        </button>
        {error && <p className="absolute bottom-14 left-0 w-64 rounded-xl bg-white p-2 text-xs text-red-700 shadow-lg ring-1 ring-red-100">{error}</p>}
      </div>
    );

  return (
    <div className="flex flex-1 items-center gap-2 rounded-full bg-brand-50 py-1.5 pl-4 pr-1.5 ring-1 ring-brand-100">
      {state === "recording" ? (
        <>
          <span className="h-2.5 w-2.5 animate-pulse rounded-full bg-red-500" />
          <span className="font-mono text-sm font-semibold text-brand-800">{mmss}</span>
          <span className="flex-1 text-xs text-muted">Recording… (max 2 min)</span>
          <button type="button" onClick={() => rec.current?.stop()} aria-label="Stop recording"
            className="grid h-9 w-9 place-items-center rounded-full bg-white text-red-600 shadow ring-1 ring-red-100"><Square className="h-4 w-4 fill-current" /></button>
        </>
      ) : (
        <>
          <audio src={url.current ?? undefined} controls className="h-9 min-w-0 flex-1" />
          <button type="button" onClick={() => setState("idle")} aria-label="Discard voice note"
            className="grid h-9 w-9 place-items-center rounded-full text-muted hover:bg-white"><Trash2 className="h-4 w-4" /></button>
          <button type="button" aria-label="Send voice note"
            onClick={() => { if (blob.current) onSend(blob.current, Math.max(1, secs)); setState("idle"); }}
            className={cx("grid h-9 w-9 place-items-center rounded-full bg-gradient-to-br from-brand-600 to-brand-700 text-white shadow-glow")}>
            <Send className="h-4 w-4" /></button>
        </>
      )}
    </div>
  );
}
