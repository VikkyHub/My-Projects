import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Errors } from './errors';

export type Lang = 'en' | 'hi' | 'mr';

export const Language = createParamDecorator((_: unknown, ctx: ExecutionContext): Lang => {
  const h = String(ctx.switchToHttp().getRequest().headers['accept-language'] ?? '').toLowerCase();
  return h.startsWith('hi') ? 'hi' : h.startsWith('mr') ? 'mr' : 'en';
});

/** Picks the translation for `lang`, falling back to English. */
export function t(i18n: unknown, lang: Lang): string {
  const m = (i18n ?? {}) as Record<string, string>;
  return m[lang] || m.en || '';
}

/**
 * Opaque cursor. MVP uses an encoded offset (simple, works with every sort order, fine up to a few
 * thousand rows deep). Swap for keyset cursors per endpoint when lists get long — clients won't notice.
 */
export function decodeCursor(cursor?: string): number {
  if (!cursor) return 0;
  try {
    const { o } = JSON.parse(Buffer.from(cursor, 'base64url').toString()) as { o: number };
    if (Number.isInteger(o) && o >= 0 && o <= 5000) return o;
  } catch { /* fall through */ }
  throw Errors.validation({ cursor: 'invalid cursor' });
}

export function page<T>(rows: T[], offset: number, limit: number) {
  const hasMore = rows.length > limit;
  const data = hasMore ? rows.slice(0, limit) : rows;
  return { data, hasMore, nextCursor: hasMore ? Buffer.from(JSON.stringify({ o: offset + limit })).toString('base64url') : null };
}

export const IST_OFFSET_MINUTES = 330;
/** Calendar date (YYYY-MM-DD) in India for a UTC instant. */
export function istDate(d = new Date()): string {
  return new Date(d.getTime() + IST_OFFSET_MINUTES * 60_000).toISOString().slice(0, 10);
}
/** UTC instant for 00:00 IST on `date`. */
export function istMidnight(date: string): Date {
  return new Date(new Date(`${date}T00:00:00Z`).getTime() - IST_OFFSET_MINUTES * 60_000);
}
export function istTime(d: Date): string {
  return new Date(d.getTime() + IST_OFFSET_MINUTES * 60_000).toISOString().slice(11, 16);
}
