/**
 * Message translation.
 * 1. Chrome's built-in on-device Translator + LanguageDetector APIs (Chrome 138+): free,
 *    private — the text never leaves the device. Models download once per language pair.
 * 2. Fallback: POST /translate on our server (only if the server has a provider configured).
 */
import { useEffect, useState } from "react";
import { api } from "../api/client";

export const LANGUAGES = [
  { code: "en", label: "English" },
  { code: "hi", label: "हिन्दी" },
  { code: "ta", label: "தமிழ்" },
  { code: "te", label: "తెలుగు" },
  { code: "kn", label: "ಕನ್ನಡ" },
  { code: "ml", label: "മലയാളം" },
  { code: "mr", label: "मराठी" },
  { code: "bn", label: "বাংলা" },
  { code: "gu", label: "ગુજરાતી" },
  { code: "pa", label: "ਪੰਜਾਬੀ" },
  { code: "ur", label: "اردو" },
];

const KEY = "translate_to";
const listeners = new Set<(l: string) => void>();

function initialLang(): string {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved) return saved;
  } catch {
    /* storage unavailable */
  }
  const nav = (navigator.language || "en").slice(0, 2);
  return LANGUAGES.some((l) => l.code === nav) ? nav : "en";
}

/** The reader's chosen language, shared by every chat on the page. */
export function useTargetLang(): [string, (l: string) => void] {
  const [lang, setLang] = useState(initialLang);
  useEffect(() => {
    const fn = (l: string) => setLang(l);
    listeners.add(fn);
    return () => {
      listeners.delete(fn);
    };
  }, []);
  const set = (l: string) => {
    try {
      localStorage.setItem(KEY, l);
    } catch {
      /* ignore */
    }
    listeners.forEach((f) => f(l));
  };
  return [lang, set];
}

// Script ranges -> language (used when the browser can't detect)
const SCRIPTS: [RegExp, string][] = [
  [/[஀-௿]/, "ta"],
  [/[ఀ-౿]/, "te"],
  [/[ಀ-೿]/, "kn"],
  [/[ഀ-ൿ]/, "ml"],
  [/[ঀ-৿]/, "bn"],
  [/[઀-૿]/, "gu"],
  [/[਀-੿]/, "pa"],
  [/[؀-ۿ]/, "ur"],
  [/[ऀ-ॿ]/, "hi"],
];

/* eslint-disable @typescript-eslint/no-explicit-any */
const g = globalThis as any;
const translators = new Map<string, Promise<any>>();

async function detect(text: string): Promise<string> {
  for (const [re, code] of SCRIPTS) if (re.test(text)) return code;
  if ("LanguageDetector" in g) {
    try {
      const d = await g.LanguageDetector.create();
      const [top] = await d.detect(text);
      if (top?.detectedLanguage && top.confidence > 0.5) return top.detectedLanguage.slice(0, 2);
    } catch {
      /* fall through */
    }
  }
  return "en";
}

export interface Translation {
  text: string;
  from: string;
  onDevice: boolean;
}

export async function translate(text: string, target: string): Promise<Translation> {
  const from = await detect(text);
  if (from === target) return { text, from, onDevice: true };
  if ("Translator" in g) {
    const pair = `${from}>${target}`;
    try {
      const availability = await g.Translator.availability({ sourceLanguage: from, targetLanguage: target });
      if (availability !== "unavailable") {
        if (!translators.has(pair))
          translators.set(pair, g.Translator.create({ sourceLanguage: from, targetLanguage: target }));
        const t = await translators.get(pair)!;
        return { text: await t.translate(text), from, onDevice: true };
      }
    } catch {
      translators.delete(pair);
    }
  }
  const r = await api<{ text: string; source?: string }>("/translate", {
    method: "POST",
    body: JSON.stringify({ text, target }),
  });
  return { text: r.text, from: r.source ?? from, onDevice: false };
}
/* eslint-enable @typescript-eslint/no-explicit-any */
