import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, ArrowRight, Fingerprint, ScrollText, Shield, ShieldCheck, Smartphone, UserCheck } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { admin } from "../api/client";
import { Logo } from "../components/AppShell";
import { Button, ErrorBox, Field, Input, OtpInput } from "../components/ui";
import type { StaffMe } from "./types";
import { aapi } from "./ui";

const PROMISES = [
  { icon: Fingerprint, title: "2-step sign-in", text: "Password plus a code from your authenticator app." },
  { icon: ShieldCheck, title: "Privacy by default", text: "Phone numbers stay masked unless there's a logged reason." },
  { icon: UserCheck, title: "Fair, careful review", text: "Clear reasons for every decision a member sees." },
];

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
    <main className="grid min-h-screen lg:grid-cols-[1.1fr_1fr]">
      {/* Hero — same look as the member login, staff-specific message */}
      <section className="hero-rani relative hidden overflow-hidden p-12 text-white lg:flex lg:flex-col lg:justify-between">
        <div className="pointer-events-none absolute -right-24 -top-24 h-96 w-96 rounded-full bg-gold-400/25 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-32 -left-20 h-96 w-96 rounded-full bg-brand-400/30 blur-3xl" />
        <Logo light />
        <div className="relative max-w-lg">
          <p className="mb-4 inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-gold-200 ring-1 ring-white/15">
            <span className="h-1.5 w-1.5 rounded-full bg-gold-300" /> Staff portal
          </p>
          <h1 className="font-display text-5xl font-semibold leading-[1.1] text-white">
            Keeping every match <span className="italic text-gold-300">safe and genuine.</span>
          </h1>
          <p className="mt-5 text-lg text-white/75">
            Review profiles, photos and reports so members can trust everyone they meet here.
          </p>
          <div className="mt-10 space-y-4">
            {PROMISES.map(({ icon: Icon, title, text }) => (
              <div key={title} className="flex gap-4 rounded-2xl bg-white/[0.07] p-4 ring-1 ring-white/10 backdrop-blur-sm">
                <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-gold-300/15 text-gold-300">
                  <Icon className="h-5 w-5" />
                </span>
                <div>
                  <p className="font-semibold text-white">{title}</p>
                  <p className="text-sm text-white/65">{text}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
        <p className="relative flex items-center gap-2 text-sm text-white/55">
          <ScrollText className="h-4 w-4" /> All staff actions are recorded in the audit log
        </p>
      </section>

      {/* Form */}
      <section className="pattern-soft flex flex-col items-center justify-center px-5 py-10">
        <div className="mb-8 lg:hidden">
          <Logo />
        </div>
        <div className="animate-rise w-full max-w-md">
        <div className="rounded-[2rem] bg-white p-8 shadow-soft ring-1 ring-line/70 sm:p-10">
          <p className="mb-6 inline-flex items-center gap-1.5 rounded-full bg-brand-50 px-3 py-1 text-xs font-bold uppercase tracking-wider text-brand-700">
            <Shield className="h-3.5 w-3.5" /> Staff sign-in
          </p>
          {params.get("expired") && !step && (
            <p className="mb-5 rounded-2xl bg-gold-50 px-4 py-3 text-sm text-ink ring-1 ring-gold-100">Your session ended. Please sign in again.</p>
          )}

          {!step && (
            <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); login.mutate(); }}>
              <div>
                <h2 className="font-display text-3xl font-semibold">Welcome back</h2>
                <p className="mt-2 text-muted">For moderators and admins only. Members log in with their mobile number.</p>
              </div>
              <Field label="Work email">
                <Input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus />
              </Field>
              <Field label="Password">
                <Input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
              </Field>
              <ErrorBox message={login.error?.message} />
              <Button className="w-full" size="lg" loading={login.isPending}>
                Continue <ArrowRight className="h-4 w-4" />
              </Button>
            </form>
          )}

          {step && (
            <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); verify.mutate(); }}>
              <button type="button" onClick={() => setStep(null)} className="flex items-center gap-1.5 text-sm font-semibold text-muted hover:text-brand-700">
                <ArrowLeft className="h-4 w-4" /> Back
              </button>

              {step.step === "enroll" ? (
                <div>
                  <h2 className="font-display text-3xl font-semibold">Set up 2-step sign-in</h2>
                  <ol className="mt-3 list-decimal space-y-1.5 pl-5 text-sm text-ink/75">
                    <li>Open <strong>Google Authenticator</strong> or <strong>Microsoft Authenticator</strong> on your phone.</li>
                    <li>Tap <strong>+</strong> and scan this code.</li>
                    <li>Enter the 6-digit code the app shows.</li>
                  </ol>
                  <div className="mt-4 flex flex-col items-center rounded-3xl bg-sand/60 p-5">
                    {qr ? <img src={qr} alt="QR code for authenticator app" className="h-44 w-44 rounded-2xl bg-white p-2 shadow-sm" /> : <div className="h-44 w-44 animate-pulse rounded-2xl bg-white" />}
                    <p className="mt-3 text-center text-xs text-muted">
                      Can't scan? Enter this key manually:
                      <br />
                      <code className="mt-1 inline-block select-all break-all rounded-lg bg-white px-2 py-1 font-mono text-[13px] text-ink ring-1 ring-line">{step.secret}</code>
                    </p>
                  </div>
                </div>
              ) : (
                <div>
                  <h2 className="flex items-center gap-2 font-display text-3xl font-semibold"><Smartphone className="h-7 w-7 text-brand-600" /> Enter your code</h2>
                  <p className="mt-2 text-muted">Open your authenticator app and enter the current 6-digit code.</p>
                </div>
              )}

              <OtpInput value={code} onChange={setCode} />

              {step.must_change_password && (
                <div className="space-y-4 rounded-3xl bg-gold-50 p-5 ring-1 ring-gold-100">
                  <p className="text-sm font-semibold text-ink">You're using a temporary password. Choose a new one.</p>
                  <Field label="New password" hint="At least 10 characters, with letters and numbers">
                    <Input type="password" autoComplete="new-password" value={newPw} onChange={(e) => setNewPw(e.target.value)} required />
                  </Field>
                  <Field label="Repeat new password">
                    <Input type="password" autoComplete="new-password" value={newPw2} onChange={(e) => setNewPw2(e.target.value)} required />
                  </Field>
                </div>
              )}

              <ErrorBox message={verify.error?.message} />
              <Button className="w-full" size="lg" disabled={code.length !== 6} loading={verify.isPending}>
                Verify & sign in
              </Button>
            </form>
          )}
          <p className="mt-8 border-t border-line pt-6 text-center text-xs leading-relaxed text-muted">
            Not staff? <a href="/login" className="font-semibold text-brand-700 hover:underline">Member login</a>
          </p>
        </div>
        </div>
      </section>
    </main>
  );
}
