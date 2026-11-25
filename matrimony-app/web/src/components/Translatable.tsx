import { Globe, Languages, Loader2 } from "lucide-react";
import { useState } from "react";
import { LANGUAGES, translate, useTargetLang } from "../lib/translate";
import { cx } from "./ui";

/** "Translate" link under a message; shows the translation inline. */
export function TranslateButton({ text, dark = false }: { text: string; dark?: boolean }) {
  const [lang] = useTargetLang();
  const [state, setState] = useState<{ text: string; lang: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const showing = state && state.lang === lang;
  // Nothing to translate: plain Latin-script text for an English reader
  if (lang === "en" && !/[^\u0000-\u024F\s\p{P}\p{S}]/u.test(text)) return null;

  return (
    <div className="mt-1">
      {showing && (
        <p className={cx("mt-1 border-t pt-1.5 text-[14px] leading-relaxed", dark ? "border-white/25 text-white/95" : "border-line text-ink/90")}>
          {state.text}
        </p>
      )}
      <button
        type="button"
        disabled={busy}
        onClick={async () => {
          if (showing) return setState(null);
          setBusy(true);
          setErr(null);
          try {
            const r = await translate(text, lang);
            setState({ text: r.text, lang });
          } catch (e) {
            setErr(e instanceof Error ? e.message : "Couldn't translate");
          } finally {
            setBusy(false);
          }
        }}
        className={cx("mt-1 inline-flex items-center gap-1 text-[11px] font-semibold", dark ? "text-white/75 hover:text-white" : "text-brand-700 hover:underline")}
      >
        {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <Languages className="h-3 w-3" />}
        {showing ? "Show original" : `Translate to ${LANGUAGES.find((l) => l.code === lang)?.label ?? lang}`}
      </button>
      {err && <p className={cx("mt-1 text-[11px]", dark ? "text-white/80" : "text-red-600")}>{err}</p>}
    </div>
  );
}

/** Small language selector (🌐) for chat headers. */
export function LanguagePicker() {
  const [lang, setLang] = useTargetLang();
  return (
    <label className="flex items-center gap-1.5 rounded-full bg-sand/70 py-1 pl-2.5 pr-1 text-xs font-semibold text-muted" title="Translate messages to">
      <Globe className="h-3.5 w-3.5" />
      <select value={lang} onChange={(e) => setLang(e.target.value)} className="cursor-pointer rounded-full bg-white px-2 py-1 text-ink ring-1 ring-line outline-none" aria-label="Translate messages to">
        {LANGUAGES.map((l) => (
          <option key={l.code} value={l.code}>{l.label}</option>
        ))}
      </select>
    </label>
  );
}
