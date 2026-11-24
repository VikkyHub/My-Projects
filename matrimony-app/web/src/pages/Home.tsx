import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { ApiError, api, logout } from "../api/client";
import type { MyProfile } from "../api/types";

export default function Home() {
  const navigate = useNavigate();
  const me = useQuery({
    queryKey: ["profile", "me"],
    queryFn: () => api<MyProfile>("/profiles/me"),
    retry: false,
  });

  const noProfile = me.error instanceof ApiError && me.error.status === 404;

  return (
    <main className="mx-auto max-w-2xl px-4 py-10">
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-brand-700">Matrimony</h1>
        <button
          className="text-sm text-gray-600 underline"
          onClick={async () => {
            await logout();
            navigate("/login", { replace: true });
          }}
        >
          Log out
        </button>
      </header>

      <section className="mt-8 rounded-2xl border border-gray-200 p-6">
        {me.isPending && <p>Loading…</p>}
        {noProfile && (
          <p>
            You're logged in. <strong>Next (week 2):</strong> the multi-step registration form
            that calls <code>POST /profiles</code>.
          </p>
        )}
        {me.data && (
          <div className="space-y-1">
            <p className="text-lg font-medium">
              {me.data.first_name} {me.data.last_name} · {me.data.age}
            </p>
            <p className="text-sm text-gray-600">
              ID {me.data.public_id} · status: {me.data.status} · {me.data.completeness}% complete
            </p>
            {me.data.candidate_consent_pending && (
              <p className="text-sm text-amber-700">
                Waiting for the candidate to confirm with an OTP on {me.data.candidate_phone_masked}.
              </p>
            )}
          </div>
        )}
        {me.error && !noProfile && <p className="text-red-700">{me.error.message}</p>}
      </section>
    </main>
  );
}
