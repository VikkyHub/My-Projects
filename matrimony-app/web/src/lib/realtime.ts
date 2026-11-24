import { useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { api, hasSession, wsUrl } from "../api/client";
import type { Message } from "../api/types";

type Listener = (m: Message) => void;
const listeners = new Set<Listener>();

/** Subscribe to live chat messages (used by the open conversation). */
export function onMessage(fn: Listener) {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

/**
 * One WebSocket per tab. Server events just tell us *what changed*; we refetch via
 * React Query, so the REST API stays the single source of truth. Reconnects with backoff.
 */
export function useRealtime() {
  const qc = useQueryClient();
  useEffect(() => {
    if (!hasSession()) return;
    let ws: WebSocket | null = null;
    let stopped = false;
    let retry = 1000;
    let timer: ReturnType<typeof setTimeout>;

    const connect = async () => {
      try {
        const { ticket } = await api<{ ticket: string }>("/auth/ws-ticket", { method: "POST" });
        if (stopped) return;
        ws = new WebSocket(wsUrl(ticket));
        ws.onopen = () => (retry = 1000);
        ws.onmessage = (e) => {
          const ev = JSON.parse(e.data);
          if (ev.type === "ping") return ws?.send("pong");
          if (ev.type === "message") {
            listeners.forEach((l) => l(ev.message));
            qc.invalidateQueries({ queryKey: ["conversations"] });
            qc.invalidateQueries({ queryKey: ["counts"] });
          }
          if (ev.type === "read") {
            qc.invalidateQueries({ queryKey: ["conversations"] });
            qc.invalidateQueries({ queryKey: ["counts"] });
          }
          if (["interest", "interest_accepted", "refresh"].includes(ev.type)) {
            qc.invalidateQueries({ queryKey: ["interests"] });
            qc.invalidateQueries({ queryKey: ["counts"] });
            qc.invalidateQueries({ queryKey: ["conversations"] });
            qc.invalidateQueries({ queryKey: ["matches"] });
          }
        };
        ws.onclose = () => {
          if (!stopped) timer = setTimeout(connect, (retry = Math.min(retry * 2, 30000)));
        };
      } catch {
        if (!stopped) timer = setTimeout(connect, (retry = Math.min(retry * 2, 30000)));
      }
    };
    connect();
    return () => {
      stopped = true;
      clearTimeout(timer);
      ws?.close();
    };
  }, [qc]);
}
