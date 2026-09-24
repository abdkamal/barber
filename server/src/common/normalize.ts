/** Input normalisation helpers shared by auth and provisioning. Pure functions. */

const ARABIC_INDIC = '٠١٢٣٤٥٦٧٨٩';
const EASTERN_ARABIC_INDIC = '۰۱۲۳۴۵۶۷۸۹';

export function toAsciiDigits(s: string): string {
  return s.replace(/[٠-٩۰-۹]/g, (ch) => {
    const a = ARABIC_INDIC.indexOf(ch);
    return String(a >= 0 ? a : EASTERN_ARABIC_INDIC.indexOf(ch));
  });
}

/**
 * Normalises a phone number: Arabic-Indic digits → ASCII, strips spaces / dashes / dots / parentheses,
 * "00" international prefix → "+". Returns null when the result is not 7–15 digits (optionally with "+").
 * No country-specific rewriting (the salon's customers are local; numbers are compared as typed).
 */
export function normalizePhone(input: string): string | null {
  let s = toAsciiDigits(input.trim()).replace(/[\s\-.()‎‏‪-‮]/g, '');
  if (s.startsWith('00')) s = '+' + s.slice(2);
  return /^\+?\d{7,15}$/.test(s) ? s : null;
}

/**
 * An international number in E.164 form for WhatsApp links (wa.me needs the country code): same clean-up as
 * normalizePhone, then "+" (or "00") followed by 8–15 digits, the first not 0. Any country code is accepted —
 * nothing is prefixed or rewritten. Returns null otherwise (e.g. a local number without its country code).
 */
export function normalizeInternationalPhone(input: string): string | null {
  const s = normalizePhone(input);
  return s !== null && /^\+[1-9]\d{7,14}$/.test(s) ? s : null;
}

export function normalizeUsername(input: string): string {
  return input.trim().toLowerCase();
}

export const USERNAME_RE = /^[a-z0-9][a-z0-9._-]{2,31}$/;

export function normalizeSalonCode(input: string): string {
  return toAsciiDigits(input.trim()).toUpperCase();
}

export const SALON_CODE_RE = /^[A-Z]{2,6}-\d{2,4}$/;
