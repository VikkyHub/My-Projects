import { useMutation } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, setTokens } from "../api/client";
import { Logo } from "../components/AppShell";
import type { LoginResponse, OtpSent } from "../api/types";

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
    mutationFn: () =>
      api<OtpSent>("/auth/otp/send", { method: "POST", body: JSON.stringify({ phone }) }),
    onSuccess: (r) => {
      setStep("code");
      setResendIn(r.resend_after);
    },
  });

  const verify = useMutation({
    mutationFn: () =>
      api<LoginResponse>("/auth/otp/verify", {
        method: "POST",
        body: JSON.stringify({ phone, code }),
      }),
    onSuccess: (r) => {
      setTokens(r);
      navigate(r.has_profile ? "/" : "/register", { replace: true });
    },
  });

  const error = (step === "phone" ? send.error : verify.error ?? send.error)?.message;

  return (
    <main className="grid min-h-screen lg:grid-cols-2">
      <section className="hidden flex-col justify-between bg-gradient-to-br from-brand-700 to-brand-600 p-12 text-white lg:flex">
        <span className="flex items-center gap-2 text-lg font-semibold">
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-white text-brand-700">♥</span>
          Matrimony
        </span>
        <div>
          <h2 className="text-4xl font-semibold leading-tight">
            Find a life partner,
            <br />
            the trusted way.
          </h2>
          <ul className="mt-8 space-y-4 text-white/90">
            <li>✓ Every profile verified by mobile, and reviewed by our team</li>
            <li>✓ You control who sees your photos and contact details</li>
            <li>✓ Chat only opens when both sides are interested</li>
          </ul>
        </div>
        <p className="text-sm text-white/60">Made in India · Your data stays protected under the DPDP Act</p>
      </section>
      <div className="flex items-center justify-center bg-brand-50 px-4 py-10 lg:bg-white">
      <div className="w-full max-w-sm rounded-2xl bg-white p-8 shadow-sm lg:shadow-none">
        <div className="mb-6 lg:hidden">
          <Logo />
        </div>
        <h1 className="text-2xl font-semibold text-brand-700">Welcome</h1>
        <p className="mt-1 text-sm text-gray-600">Log in or register with your mobile number.</p>

        {step === "phone" ? (
          <form
            className="mt-6 space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              send.mutate();
            }}
          >
            <label className="block text-sm font-medium text-gray-700">
              Mobile number
              <div className="mt-1 flex rounded-lg border border-gray-300 focus-within:ring-2 focus-within:ring-brand-600">
                <span className="px-3 py-2 text-gray-500">+91</span>
                <input
                  className="w-full rounded-r-lg py-2 pr-3 outline-none"
                  inputMode="numeric"
                  autoComplete="tel-national"
                  maxLength={10}
                  value={phone}
                  onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
                  placeholder="98765 43210"
                  required
                />
              </div>
            </label>
            <button
              className="w-full rounded-lg bg-brand-600 py-2.5 font-medium text-white hover:bg-brand-700 disabled:opacity-50"
              disabled={phone.length !== 10 || send.isPending}
            >
              {send.isPending ? "Sending…" : "Send OTP"}
            </button>
          </form>
        ) : (
          <form
            className="mt-6 space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              verify.mutate();
            }}
          >
            <p className="text-sm text-gray-600">
              Enter the 6-digit code sent to +91 {phone}.{" "}
              <button type="button" className="text-brand-600 underline" onClick={() => setStep("phone")}>
                Change
              </button>
            </p>
            <input
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-center text-xl tracking-[0.5em] outline-none focus:ring-2 focus:ring-brand-600"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              autoFocus
              required
            />
            <button
              className="w-full rounded-lg bg-brand-600 py-2.5 font-medium text-white hover:bg-brand-700 disabled:opacity-50"
              disabled={code.length !== 6 || verify.isPending}
            >
              {verify.isPending ? "Verifying…" : "Verify & continue"}
            </button>
            <button
              type="button"
              className="w-full text-sm text-gray-600 disabled:opacity-50"
              disabled={resendIn > 0 || send.isPending}
              onClick={() => send.mutate()}
            >
              {resendIn > 0 ? `Resend OTP in ${resendIn}s` : "Resend OTP"}
            </button>
          </form>
        )}

        {error && (
          <p role="alert" className="mt-4 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
            {error}
          </p>
        )}
        <p className="mt-6 text-xs text-gray-500">
          By continuing you agree to our Terms of Use and Privacy Policy.
        </p>
      </div>
      </div>
    </main>
  );
}
