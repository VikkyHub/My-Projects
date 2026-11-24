import { Crown, EyeOff, MessageCircle, Phone, ShieldAlert, Sparkles, Users } from "lucide-react";
import { Card, IconChip } from "./ui";

const PERKS = [
  { icon: Phone, text: "View verified contact numbers" },
  { icon: MessageCircle, text: "Chat with people you match" },
  { icon: Sparkles, text: "Stand out in search results" },
];

const TIPS = [
  { icon: ShieldAlert, text: "Never send money or share OTPs, bank or card details." },
  { icon: Users, text: "Meet first in a public place, and tell family where you'll be." },
  { icon: EyeOff, text: "Keep your address and workplace private until you trust someone." },
];

export default function SideRail() {
  return (
    <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-1">
      <section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-gold-100 via-gold-50 to-white p-6 shadow-soft ring-1 ring-gold-200">
        <div className="pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-gold-300/40 blur-2xl" />
        <span className="relative grid h-11 w-11 place-items-center rounded-2xl bg-gradient-to-br from-gold-300 to-gold-500 text-white shadow-md">
          <Crown className="h-5 w-5" />
        </span>
        <h3 className="relative mt-4 font-display text-xl font-semibold">Go Premium</h3>
        <p className="relative mt-1 text-sm text-ink/70">Connect faster with the people you like.</p>
        <ul className="relative mt-4 space-y-3">
          {PERKS.map(({ icon: Icon, text }) => (
            <li key={text} className="flex items-center gap-3 text-sm font-medium text-ink">
              <Icon className="h-4 w-4 shrink-0 text-gold-500" />
              {text}
            </li>
          ))}
        </ul>
        <button
          disabled
          title="Plans launch soon"
          className="relative mt-5 w-full cursor-not-allowed rounded-full bg-gradient-to-r from-gold-300 to-gold-400 py-2.5 text-sm font-semibold text-brand-950 opacity-80"
        >
          Plans coming soon
        </button>
      </section>

      <Card>
        <div className="flex items-center gap-3">
          <IconChip icon={ShieldAlert} color="teal" />
          <h3 className="font-display text-lg font-semibold">Stay safe</h3>
        </div>
        <ul className="mt-4 space-y-4">
          {TIPS.map(({ icon: Icon, text }) => (
            <li key={text} className="flex gap-3 text-sm leading-relaxed text-ink/80">
              <Icon className="mt-0.5 h-4 w-4 shrink-0 text-teal-600" />
              {text}
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
