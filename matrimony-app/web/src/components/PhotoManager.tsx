import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, Clock, ImagePlus, Lock, Star, Trash2 } from "lucide-react";
import { useRef } from "react";
import { api, mediaUrl } from "../api/client";
import type { Photo } from "../api/types";
import { Card, ErrorBox, cx } from "./ui";

const MAX = 6;
const VIS = [
  { value: "all", label: "Everyone", hint: "All members can see your photos" },
  { value: "premium", label: "Premium members", hint: "Others see a blurred photo" },
  { value: "accepted", label: "Only connections", hint: "Visible after you accept an interest" },
] as const;

export function usePhotos() {
  return useQuery({ queryKey: ["photos"], queryFn: () => api<Photo[]>("/profiles/me/photos") });
}

export default function PhotoManager() {
  const qc = useQueryClient();
  const input = useRef<HTMLInputElement>(null);
  const photos = usePhotos();
  const settings = useQuery({
    queryKey: ["photo-settings"],
    queryFn: () => api<{ photo_visibility: string }>("/profiles/me/photo-settings"),
  });
  const done = (list: Photo[]) => {
    qc.setQueryData(["photos"], list);
    qc.invalidateQueries({ queryKey: ["profile", "me"] });
  };

  const upload = useMutation({
    mutationFn: async (files: File[]) => {
      let last: Photo[] = [];
      for (const f of files) {
        const fd = new FormData();
        fd.append("file", f);
        last = await api<Photo[]>("/profiles/me/photos", { method: "POST", body: fd });
        done(last);
      }
      return last;
    },
  });
  const remove = useMutation({
    mutationFn: (id: string) => api<Photo[]>(`/profiles/me/photos/${id}`, { method: "DELETE" }),
    onSuccess: done,
  });
  const primary = useMutation({
    mutationFn: (id: string) => api<Photo[]>(`/profiles/me/photos/${id}/primary`, { method: "POST" }),
    onSuccess: done,
  });
  const setVis = useMutation({
    mutationFn: (photo_visibility: string) =>
      api("/profiles/me/photo-settings", { method: "PUT", body: JSON.stringify({ photo_visibility }) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["photo-settings"] }),
  });

  const list = photos.data ?? [];
  const vis = settings.data?.photo_visibility ?? "all";

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <span className="grid h-10 w-10 place-items-center rounded-2xl bg-rose-50 text-rose-500">
            <Camera className="h-5 w-5" />
          </span>
          <div>
            <h2 className="font-display text-lg font-semibold">Photos</h2>
            <p className="text-xs font-medium text-muted">{list.length} of {MAX} · JPG, PNG or WEBP up to 10 MB</p>
          </div>
        </div>
        <label className="flex items-center gap-2 rounded-full bg-sand/70 py-1 pl-3 pr-1 text-sm">
          <Lock className="h-4 w-4 text-muted" />
          <span className="text-muted">Visible to</span>
          <select
            aria-label="Who can see my photos"
            className="cursor-pointer rounded-full bg-white px-3 py-1.5 font-semibold text-ink ring-1 ring-line outline-none"
            value={vis}
            onChange={(e) => setVis.mutate(e.target.value)}
          >
            {VIS.map((v) => (
              <option key={v.value} value={v.value}>{v.label}</option>
            ))}
          </select>
        </label>
      </div>
      <p className="mt-2 text-xs text-muted">{VIS.find((v) => v.value === vis)?.hint}. Location data is removed from every photo.</p>

      <div className="mt-5 grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6">
        {list.map((p) => (
          <div key={p.id} className="group relative aspect-[3/4] overflow-hidden rounded-2xl bg-sand ring-1 ring-line">
            <img src={mediaUrl(p.url)} alt="" className="h-full w-full object-cover" />
            {p.is_primary && (
              <span className="absolute left-2 top-2 flex items-center gap-1 rounded-full bg-gradient-to-r from-gold-300 to-gold-400 px-2 py-0.5 text-[11px] font-bold text-brand-950 shadow">
                <Star className="h-3 w-3 fill-current" /> Main
              </span>
            )}
            {p.status === "pending" && (
              <span className="absolute bottom-2 left-2 flex items-center gap-1 rounded-full bg-white/95 px-2 py-0.5 text-[11px] font-semibold text-amber-800 shadow">
                <Clock className="h-3 w-3" /> In review
              </span>
            )}
            <div className="absolute inset-x-0 bottom-0 flex justify-end gap-1.5 bg-gradient-to-t from-black/60 to-transparent p-2 pt-8 opacity-100 transition sm:opacity-0 sm:group-hover:opacity-100">
              {!p.is_primary && (
                <button
                  onClick={() => primary.mutate(p.id)}
                  className="grid h-8 w-8 place-items-center rounded-full bg-white/95 text-gold-600 shadow hover:bg-white"
                  aria-label="Make main photo"
                  title="Make main photo"
                >
                  <Star className="h-4 w-4" />
                </button>
              )}
              <button
                onClick={() => confirm("Delete this photo?") && remove.mutate(p.id)}
                className="grid h-8 w-8 place-items-center rounded-full bg-white/95 text-red-600 shadow hover:bg-white"
                aria-label="Delete photo"
                title="Delete photo"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          </div>
        ))}
        {list.length < MAX && (
          <button
            type="button"
            onClick={() => input.current?.click()}
            disabled={upload.isPending}
            className={cx(
              "grid aspect-[3/4] place-items-center rounded-2xl border-2 border-dashed border-brand-200 bg-brand-50/50 text-brand-600 transition hover:border-brand-400 hover:bg-brand-50",
              upload.isPending && "animate-pulse",
            )}
          >
            <span className="flex flex-col items-center gap-1.5 text-sm font-semibold">
              <ImagePlus className="h-7 w-7" />
              {upload.isPending ? "Uploading…" : "Add photo"}
            </span>
          </button>
        )}
      </div>
      <input
        ref={input}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        multiple
        hidden
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []).slice(0, MAX - list.length);
          if (files.length) upload.mutate(files);
          e.target.value = "";
        }}
      />
      <div className="mt-3">
        <ErrorBox message={upload.error?.message ?? remove.error?.message} />
      </div>
    </Card>
  );
}
