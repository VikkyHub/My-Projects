import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Send, ShieldCheck } from "lucide-react";
import { useState } from "react";
import { api } from "../api/client";
import type { MyProfile, OtpSent } from "../api/types";
import { Button, ErrorBox, OtpInput } from "./ui";

export default function ConsentCard({ profile }: { profile: MyProfile }) {
  const qc = useQueryClient();
  const [code, setCode] = useState("");
  const send = useMutation({
    mutationFn: () => api<OtpSent>("/profiles/me/candidate-consent/send", { method: "POST" }),
  });
  const verify = useMutation({
    mutationFn: () =>
      api<MyProfile>("/profiles/me/candidate-consent/verify", { method: "POST", body: JSON.stringify({ code }) }),
    onSuccess: (p) => qc.setQueryData(["profile", "me"], p),
  });

  return (
    <section className="animate-rise overflow-hidden rounded-3xl bg-gradient-to-br from-gold-50 via-white to-brand-50 p-6 shadow-soft ring-1 ring-gold-200 sm:p-7">
      <div className="flex gap-4">
        <span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-gold-400 text-white shadow-md">
          <ShieldCheck className="h-6 w-6" />
        </span>
        <div>
          <h2 className="font-display text-xl font-semibold">One last step: {profile.first_name}'s consent</h2>
          <p className="mt-1 text-sm leading-relaxed text-ink/75">
            The profile stays hidden until {profile.first_name} confirms it with an OTP sent to{" "}
            <strong className="text-ink">{profile.candidate_phone_masked}</strong>. Ask them for the code once it arrives.
          </p>
        </div>
      </div>

      <div className="mt-6 sm:pl-16">
        {!send.isSuccess ? (
          <Button variant="gold" onClick={() => send.mutate()} loading={send.isPending}>
            <Send className="h-4 w-4" /> Send OTP to {profile.first_name}
          </Button>
        ) : (
          <form
            className="max-w-sm space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              verify.mutate();
            }}
          >
            <OtpInput value={code} onChange={setCode} />
            <div className="flex gap-2">
              <Button type="submit" disabled={code.length !== 6} loading={verify.isPending}>
                Confirm consent
              </Button>
              <Button type="button" variant="ghost" onClick={() => send.mutate()} loading={send.isPending}>
                Resend
              </Button>
            </div>
          </form>
        )}
        <div className="mt-4 max-w-sm">
          <ErrorBox message={send.error?.message ?? verify.error?.message} />
        </div>
      </div>
    </section>
  );
}
