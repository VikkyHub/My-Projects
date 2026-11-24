import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../api/client";
import type { Counts, ProfileCard } from "../api/types";

export function useCounts() {
  return useQuery({
    queryKey: ["counts"],
    queryFn: () => api<Counts>("/interests/counts"),
    refetchInterval: 60_000,
    retry: false,
  });
}

/** Invalidate everything that shows a member's relationship state. */
export function useRefreshSocial() {
  const qc = useQueryClient();
  return () => {
    for (const k of ["matches", "interests", "counts", "conversations", "shortlist", "public"])
      qc.invalidateQueries({ queryKey: [k] });
  };
}

export function useSendInterest() {
  const refresh = useRefreshSocial();
  return useMutation({
    mutationFn: (public_id: string) =>
      api("/interests", { method: "POST", body: JSON.stringify({ public_id }) }),
    onSuccess: refresh,
  });
}

export function useRespond() {
  const refresh = useRefreshSocial();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: "accept" | "decline" | "withdraw" }) =>
      api<{ status: string; conversation_id?: string }>(`/interests/${id}/${action}`, { method: "POST" }),
    onSuccess: refresh,
  });
}

export function useShortlist() {
  const refresh = useRefreshSocial();
  return useMutation({
    mutationFn: (p: ProfileCard) =>
      api(`/shortlist/${p.public_id}`, { method: p.shortlisted ? "DELETE" : "PUT" }),
    onSuccess: refresh,
  });
}

export function timeAgo(iso: string | null): string {
  if (!iso) return "";
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  if (s < 7 * 86400) return `${Math.floor(s / 86400)}d ago`;
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short" });
}
