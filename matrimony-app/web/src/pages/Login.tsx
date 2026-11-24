import { useMutation } from "@tanstack/react-query";
import { ArrowLeft, ArrowRight, BadgeCheck, EyeOff, HeartHandshake, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, setTokens } from "../api/client";
import type { LoginResponse, OtpSent } from "../api/types";
import { Logo } from "../components/AppShell";
import { Button, ErrorBox, OtpInput, PhoneInput } from "../components/ui";

const PROMISES = [
  { icon: BadgeCheck, title: "Verified & reviewed", text: "Every profile is mobile-verified and checked by our team." },
  { icon: EyeOff, title: "You control privacy", text: "Choose who sees your photos and contact details." },
  { icon: HeartHandshake, title: "Mutual interest first", text: "Chat opens only when both sides say yes." },
];

export default function Login() {
  const navigate = useNavigate();
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [resendIn, setResendIn] = useState(0);

  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [resendIn]);

  const send = useMutation({
    mutationFn: () => api<OtpSent>("/auth/otp/send", { method: "POST", body: JSON.stringify({ phone }) }),
    onSuccess: (r) => {
      setStep("code");
      setCode("");
      setResendIn(r.resend_after);
    },
  });

  const verify = useMutation({
    mutationFn: () =>
      api<LoginResponse>("/auth/otp/verify", { method: "POST", body: JSON.stringify({ phone, code }) }),
    onSuccess: (r) => {
      setTokens(r);
      navigate(r.has_profile ? "/" : "/register", { replace: true });
    },
  });

  // Auto-submit once all 6 digits are in
  useEffect(() => {
    if (step === "code" && code.length === 6 && !verify.isPending && !verify.isError) verify.mutate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code]);

  const error = step === "phone" ? send.error?.message : (verify.error ?? send.error)?.message;

  return (
    <main className="grid min-h-screen lg:grid-cols-[1.1fr_1fr]">
      {/* Hero */}
      <section className="hero-rani relative hidden overflow-hidden p-12 text-white lg:flex lg:flex-col lg:justify-between">
        <div className="pointer-events-none absolute -right-24 -top-24 h-96 w-96 rounded-full bg-gold-400/25 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-32 -left-20 h-96 w-96 rounded-full bg-brand-400/30 blur-3xl" />

        <Logo light />

        <div className="relative max-w-lg">
          <p className="mb-4 inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-gold-200 ring-1 ring-white/15">
            <span className="h-1.5 w-1.5 rounded-full bg-gold-300" /> Trusted matchmaking
          </p>
          <h1 className="font-display text-5xl font-semibold leading-[1.1] text-white">
            Where families meet, <span className="italic text-gold-300">and forever</span> begins.
          </h1>
          <p className="mt-5 text-lg text-white/75">
            A safe, private and respectful place to find your life partner — for you, or for someone you love.
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
          <ShieldCheck className="h-4 w-4" /> Your data is protected under India's DPDP Act
        </p>
      </section>

      {/* Form */}
      <section className="pattern-soft flex flex-col items-center justify-center px-5 py-10">
        <div className="mb-8 lg:hidden">
          <Logo />
        </div>

        <div className="animate-rise w-full max-w-md rounded-[2rem] bg-white p-8 shadow-soft ring-1 ring-line/70 sm:p-10">
          {step === "phone" ? (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                send.mutate();
              }}
            >
              <h2 className="font-display text-3xl font-semibold">Welcome</h2>
              <p className="mt-2 text-muted">Log in or create your profile with your mobile number.</p>

              <div className="mt-8">
                <label className="mb-2 block text-sm font-semibold">Mobile number</label>
                <PhoneInput value={phone} onChange={setPhone} autoFocus />
              </div>

              <Button size="lg" className="mt-6 w-full" disabled={phone.length !== 10} loading={send.isPending}>
                Get OTP <ArrowRight className="h-4 w-4" />
              </Button>
            </form>
          ) : (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                verify.mutate();
              }}
            >
              <button
                type="button"
                onClick={() => {
                  setStep("phone");
                  verify.reset();
                }}
                className="mb-6 flex items-center gap-1.5 text-sm font-semibold text-muted hover:text-brand-700"
              >
                <ArrowLeft className="h-4 w-4" /> Change number
              </button>
              <h2 className="font-display text-3xl font-semibold">Enter the code</h2>
              <p className="mt-2 text-muted">
                We sent a 6-digit code to <span className="font-semibold text-ink">+91 {phone}</span>
              </p>

              <div className="mt-8">
                <OtpInput
                  value={code}
                  onChange={(v) => {
                    if (verify.isError) verify.reset();
                    setCode(v);
                  }}
                />
              </div>

              <Button size="lg" className="mt-6 w-full" disabled={code.length !== 6} loading={verify.isPending}>
                Verify & continue
              </Button>

              <p className="mt-5 text-center text-sm text-muted">
                Didn't get it?{" "}
                <button
                  type="button"
                  className="font-semibold text-brand-700 hover:underline disabled:font-normal disabled:text-muted disabled:no-underline"
                  disabled={resendIn > 0 || send.isPending}
                  onClick={() => send.mutate()}
                >
                  {resendIn > 0 ? `Resend in ${resendIn}s` : "Resend OTP"}
                </button>
              </p>
            </form>
          )}

          <div className="mt-6">
            <ErrorBox message={error} />
          </div>

          <p className="mt-8 border-t border-line pt-6 text-center text-xs leading-relaxed text-muted">
            By continuing you agree to our{" "}
            <a href="#" className="font-semibold text-ink hover:text-brand-700">Terms</a> and{" "}
            <a href="#" className="font-semibold text-ink hover:text-brand-700">Privacy Policy</a>.
          </p>
        </div>
      </section>
    </main>
  );
}
