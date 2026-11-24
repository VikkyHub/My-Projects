import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { api } from "../api/client";
import type { MyProfile } from "../api/types";
import { Button, Card, ErrorBox } from "./ui";

/** A profile section with read view + inline edit form that PATCHes /profiles/me. */
export default function Section<T>({
  title,
  subtitle,
  initial,
  empty,
  view,
  form,
  toPayload,
}: {
  title: string;
  subtitle?: string;
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
    <Card>
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-base font-semibold text-gray-900">{title}</h2>
          {subtitle && <p className="text-sm text-gray-500">{subtitle}</p>}
        </div>
        {!editing && (
          <Button
            variant="ghost"
            className="-mr-2 -mt-1"
            onClick={() => {
              setValue(initial);
              save.reset();
              setEditing(true);
            }}
          >
            {empty ? "Add" : "Edit"}
          </Button>
        )}
      </div>

      {editing ? (
        <form
          className="mt-4 space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate();
          }}
        >
          {form(value, (patch) => setValue((v) => ({ ...v, ...patch })))}
          <ErrorBox message={save.error?.message} />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setEditing(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={save.isPending}>
              Save
            </Button>
          </div>
        </form>
      ) : empty ? (
        <p className="mt-3 text-sm text-gray-400">Not added yet.</p>
      ) : (
        <div className="mt-4">{view}</div>
      )}
    </Card>
  );
}

export function Facts({ items }: { items: [string, ReactNode | null | undefined][] }) {
  const shown = items.filter(([, v]) => v !== null && v !== undefined && v !== "");
  return (
    <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
      {shown.map(([k, v]) => (
        <div key={k}>
          <dt className="text-gray-500">{k}</dt>
          <dd className="font-medium text-gray-900">{v}</dd>
        </div>
      ))}
    </dl>
  );
}
