import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { api } from "../api/client";
import type { MyProfile, OtpSent } from "../api/types";
import { Button, Card, ErrorBox, Input } from "./ui";

export default function ConsentCard({ profile }: { profile: MyProfile }) {
  const qc = useQueryClient();
  const [code, setCode] = useState("");
  const send = useMutation({
    mutationFn: () => api<OtpSent>("/profiles/me/candidate-consent/send", { method: "POST" }),
  });
  const verify = useMutation({
    mutationFn: () =>
      api<MyProfile>("/profiles/me/candidate-consent/verify", {
        method: "POST",
        body: JSON.stringify({ code }),
      }),
    onSuccess: (p) => qc.setQueryData(["profile", "me"], p),
  });

  return (
    <Card className="border-amber-300 bg-amber-50">
      <h2 className="text-base font-semibold text-amber-900">
        Waiting for {profile.first_name}'s confirmation
      </h2>
      <p className="mt-1 text-sm text-amber-900/80">
        This profile is hidden until {profile.first_name} confirms with an OTP sent to{" "}
        <strong>{profile.candidate_phone_masked}</strong>. Ask them for the code when it arrives.
      </p>
      <div className="mt-4 flex flex-col gap-3 sm:flex-row">
        {!send.isSuccess ? (
          <Button onClick={() => send.mutate()} loading={send.isPending}>
            Send OTP to {profile.first_name}
          </Button>
        ) : (
          <form
            className="flex flex-1 flex-col gap-3 sm:flex-row"
            onSubmit={(e) => {
              e.preventDefault();
              verify.mutate();
            }}
          >
            <Input
              className="sm:max-w-48 text-center tracking-[0.4em]"
              inputMode="numeric"
              maxLength={6}
              placeholder="6-digit code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            />
            <Button type="submit" disabled={code.length !== 6} loading={verify.isPending}>
              Confirm
            </Button>
            <Button type="button" variant="ghost" onClick={() => send.mutate()} loading={send.isPending}>
              Resend
            </Button>
          </form>
        )}
      </div>
      <div className="mt-3">
        <ErrorBox message={send.error?.message ?? verify.error?.message} />
      </div>
    </Card>
  );
}
