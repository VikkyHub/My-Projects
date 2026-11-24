import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, type LucideIcon } from "lucide-react";
import { useState, type ReactNode } from "react";
import { api } from "../api/client";
import type { MyProfile } from "../api/types";
import { Button, Card, ErrorBox, IconChip, type ChipColor } from "./ui";

/** A profile section with read view + inline edit form that PATCHes /profiles/me. */
export default function Section<T>({
  title,
  subtitle,
  icon,
  color = "brand",
  initial,
  empty,
  view,
  form,
  toPayload,
}: {
  title: string;
  subtitle?: string;
  icon: LucideIcon;
  color?: ChipColor;
  initial: T;
  empty: boolean;
  view: ReactNode;
  form: (value: T, set: (patch: Partial<T>) => void) => ReactNode;
  toPayload: (value: T) => Record<string, unknown>;
}) {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState<T>(initial);

  const save = useMutation({
    mutationFn: () =>
      api<MyProfile>("/profiles/me", { method: "PATCH", body: JSON.stringify(toPayload(value)) }),
    onSuccess: (p) => {
      qc.setQueryData(["profile", "me"], p);
      setEditing(false);
    },
  });

  return (
    <Card className={editing ? "ring-2 ring-brand-200" : undefined}>
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <IconChip icon={icon} color={color} />
          <div>
            <h2 className="font-display text-lg font-semibold">{title}</h2>
            {subtitle && <p className="text-xs font-medium text-muted">{subtitle}</p>}
          </div>
        </div>
        {!editing && (
          <Button
            variant={empty ? "secondary" : "ghost"}
            size="sm"
            onClick={() => {
              setValue(initial);
              save.reset();
              setEditing(true);
            }}
          >
            {empty ? <Plus className="h-4 w-4" /> : <Pencil className="h-3.5 w-3.5" />}
            {empty ? "Add" : "Edit"}
          </Button>
        )}
      </div>

      {editing ? (
        <form
          className="animate-rise mt-6 space-y-5 border-t border-line pt-6"
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate();
          }}
        >
          {form(value, (patch) => setValue((v) => ({ ...v, ...patch })))}
          <ErrorBox message={save.error?.message} />
          <div className="flex justify-end gap-2 pt-1">
            <Button type="button" variant="secondary" onClick={() => setEditing(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={save.isPending}>
              Save
            </Button>
          </div>
        </form>
      ) : empty ? (
        <p className="mt-4 rounded-2xl bg-sand/60 px-4 py-3 text-sm text-muted">
          Not added yet — profiles with this section get more responses.
        </p>
      ) : (
        <div className="mt-5 border-t border-line pt-5">{view}</div>
      )}
    </Card>
  );
}

export function Facts({ items }: { items: [string, ReactNode | null | undefined][] }) {
  const shown = items.filter(([, v]) => v !== null && v !== undefined && v !== "");
  return (
    <dl className="grid gap-x-8 gap-y-4 text-sm sm:grid-cols-2">
      {shown.map(([k, v]) => (
        <div key={k}>
          <dt className="text-xs font-semibold uppercase tracking-wide text-muted">{k}</dt>
          <dd className="mt-0.5 text-[15px] font-medium text-ink">{v}</dd>
        </div>
      ))}
    </dl>
  );
}
