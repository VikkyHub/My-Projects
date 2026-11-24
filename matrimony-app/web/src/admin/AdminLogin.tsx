import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, KeyRound, Shield, Smartphone } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { admin } from "../api/client";
import { Button, ErrorBox, Field, Input, OtpInput } from "../components/ui";
import type { StaffMe } from "./types";
import { aapi } from "./ui";

interface LoginOut {
  step: "totp" | "enroll";
  ticket: string;
  must_change_password: boolean;
  otpauth_uri: string | null;
  secret: string | null;
}

export default function AdminLogin() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [params] = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [newPw, setNewPw] = useState("");
  const [newPw2, setNewPw2] = useState("");
  const [step, setStep] = useState<LoginOut | null>(null);
  const [qr, setQr] = useState<string | null>(null);

  useEffect(() => {
    if (step?.otpauth_uri) QRCode.toDataURL(step.otpauth_uri, { margin: 1, width: 200 }).then(setQr);
  }, [step]);

  const login = useMutation({
    mutationFn: () => aapi<LoginOut>("/admin/auth/login", { method: "POST", body: JSON.stringify({ email, password }) }),
    onSuccess: (r) => {
      setStep(r);
      setCode("");
      setPassword("");
    },
  });
  const verify = useMutation({
    mutationFn: () => {
      if (step?.must_change_password && newPw !== newPw2) throw new Error("The two new passwords don't match");
      return aapi<{ access_token: string; refresh_token: string; expires_in: number; staff: StaffMe }>("/admin/auth/verify", {
        method: "POST",
        body: JSON.stringify({ ticket: step!.ticket, code, new_password: step?.must_change_password ? newPw : null }),
      });
    },
    onSuccess: (r) => {
      admin.setTokens(r);
      qc.setQueryData(["admin", "me"], r.staff);
      navigate("/admin", { replace: true });
    },
  });

  return (
    <main className="grid min-h-screen place-items-center bg-slate-100 px-4 py-10 font-sans">
      <div className="w-full max-w-md">
        <div className="mb-6 flex items-center justify-center gap-2.5">
          <span className="grid h-10 w-10 place-items-center rounded-xl bg-slate-900 text-white">
            <Shield className="h-5 w-5" />
          </span>
          <div>
            <p className="font-semibold text-slate-900">Matrimony</p>
            <p className="text-xs uppercase tracking-wider text-slate-500">Staff sign-in</p>
          </div>
        </div>

        <div className="rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
          {params.get("expired") && !step && (
            <p className="mb-5 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">Your session ended. Please sign in again.</p>
          )}

          {!step && (
            <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); login.mutate(); }}>
              <div>
                <h1 className="text-xl font-semibold text-slate-900">Sign in</h1>
                <p className="mt-1 text-sm text-slate-500">For moderators and admins only. Members log in with their mobile number.</p>
              </div>
              <Field label="Work email">
                <Input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus />
              </Field>
              <Field label="Password">
                <Input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
              </Field>
              <ErrorBox message={login.error?.message} />
              <Button className="w-full !bg-none !bg-slate-900 !shadow-none hover:!bg-slate-800" size="lg" loading={login.isPending}>
                <KeyRound className="h-4 w-4" /> Continue
              </Button>
            </form>
          )}

          {step && (
            <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); verify.mutate(); }}>
              <button type="button" onClick={() => setStep(null)} className="flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900">
                <ArrowLeft className="h-4 w-4" /> Back
              </button>

              {step.step === "enroll" ? (
                <div>
                  <h1 className="text-xl font-semibold text-slate-900">Set up 2-step sign-in</h1>
                  <ol className="mt-3 list-decimal space-y-1.5 pl-5 text-sm text-slate-600">
                    <li>Open <strong>Google Authenticator</strong> or <strong>Microsoft Authenticator</strong> on your phone.</li>
                    <li>Tap <strong>+</strong> and scan this code.</li>
                    <li>Enter the 6-digit code the app shows.</li>
                  </ol>
                  <div className="mt-4 flex flex-col items-center rounded-xl bg-slate-50 p-4">
                    {qr ? <img src={qr} alt="QR code for authenticator app" className="h-44 w-44 rounded-lg bg-white p-2" /> : <div className="h-44 w-44 animate-pulse rounded-lg bg-slate-200" />}
                    <p className="mt-3 text-center text-xs text-slate-500">
                      Can't scan? Enter this key manually:
                      <br />
                      <code className="mt-1 inline-block select-all break-all rounded bg-white px-2 py-1 font-mono text-[13px] text-slate-800 ring-1 ring-slate-200">{step.secret}</code>
                    </p>
                  </div>
                </div>
              ) : (
                <div>
                  <h1 className="flex items-center gap-2 text-xl font-semibold text-slate-900"><Smartphone className="h-5 w-5" /> Enter your code</h1>
                  <p className="mt-1 text-sm text-slate-500">Open your authenticator app and enter the current 6-digit code.</p>
                </div>
              )}

              <OtpInput value={code} onChange={setCode} />

              {step.must_change_password && (
                <div className="space-y-4 rounded-xl bg-slate-50 p-4">
                  <p className="text-sm font-medium text-slate-700">You're using a temporary password. Choose a new one.</p>
                  <Field label="New password" hint="At least 10 characters, with letters and numbers">
                    <Input type="password" autoComplete="new-password" value={newPw} onChange={(e) => setNewPw(e.target.value)} required />
                  </Field>
                  <Field label="Repeat new password">
                    <Input type="password" autoComplete="new-password" value={newPw2} onChange={(e) => setNewPw2(e.target.value)} required />
                  </Field>
                </div>
              )}

              <ErrorBox message={verify.error?.message} />
              <Button className="w-full !bg-none !bg-slate-900 !shadow-none hover:!bg-slate-800" size="lg" disabled={code.length !== 6} loading={verify.isPending}>
                Verify & sign in
              </Button>
            </form>
          )}
        </div>
        <p className="mt-6 text-center text-xs text-slate-500">All staff actions are recorded in the audit log.</p>
      </div>
    </main>
  );
}
