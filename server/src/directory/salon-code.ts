/**
 * Salon code generation (e.g. "صالون الراحة" → "RAHA-27").
 * Letters are derived from the salon name (Arabic is transliterated), followed by random digits.
 * Uniqueness is guaranteed by the directory's UNIQUE constraint; the caller retries on collision.
 */

const MAP: Record<string, string> = {
  ا: 'A', أ: 'A', إ: 'I', آ: 'A', ٱ: 'A', ب: 'B', ت: 'T', ث: 'TH', ج: 'J', ح: 'H', خ: 'KH', د: 'D', ذ: 'TH',
  ر: 'R', ز: 'Z', س: 'S', ش: 'SH', ص: 'S', ض: 'D', ط: 'T', ظ: 'Z', ع: 'A', غ: 'GH', ف: 'F', ق: 'Q',
  ك: 'K', ل: 'L', م: 'M', ن: 'N', ه: 'H', ة: 'A', و: 'W', ي: 'Y', ى: 'A', ئ: 'Y', ؤ: 'W', ء: '', پ: 'P',
  چ: 'CH', گ: 'G', ک: 'K', ی: 'Y',
};

/** Generic words that say nothing about the salon and are skipped when deriving letters. */
const STOP_WORDS = new Set([
  'صالون', 'صالونات', 'حلاقة', 'حلاق', 'للحلاقة', 'الحلاقة', 'الحلاق', 'مركز', 'محل', 'للرجال', 'رجالي',
  'salon', 'saloon', 'barber', 'barbers', 'barbershop', 'shop', 'the', 'hair', 'studio', 'men',
]);

function stripDiacritics(s: string): string {
  return s.normalize('NFKD').replace(/[ً-ٰٟـ̀-ͯ]/g, '');
}

export function transliterateWord(word: string): string {
  let w = word;
  if (/^[؀-ۿ]/.test(w)) {
    if (w.startsWith('ال') && w.length > 3) w = w.slice(2);
    else if ((w.startsWith('وال') || w.startsWith('بال') || w.startsWith('لل')) && w.length > 4) w = w.slice(w.startsWith('لل') ? 2 : 3);
  }
  let out = '';
  for (const ch of w) {
    if (/[a-z]/i.test(ch)) out += ch.toUpperCase();
    else if (MAP[ch] !== undefined) out += MAP[ch];
  }
  return out;
}

/** 2–4 uppercase ASCII letters derived from the name ("SALN" fallback). */
export function codePrefixFromName(name: string): string {
  const words = stripDiacritics(name)
    .toLowerCase()
    .split(/[^\p{L}]+/u)
    .filter(Boolean);
  const meaningful = words.filter((w) => !STOP_WORDS.has(w));
  let letters = (meaningful.length ? meaningful : words).map(transliterateWord).join('');
  letters = letters.replace(/[^A-Z]/g, '');
  if (letters.length < 2) return 'SALN';
  return letters.slice(0, 4);
}

/** attempt 0..9 → 2 digits (10–99); later attempts → 3 digits (100–999) to escape crowded prefixes. */
export function salonCodeCandidate(name: string, attempt: number, rnd: () => number = Math.random): string {
  const prefix = codePrefixFromName(name);
  const digits = attempt < 10 ? 10 + Math.floor(rnd() * 90) : 100 + Math.floor(rnd() * 900);
  return `${prefix}-${digits}`;
}

/** Database name derived from the code: "RAHA-27" → "<prefix>raha_27". */
export function salonDbName(prefix: string, code: string): string {
  return `${prefix}${code.toLowerCase().replace('-', '_')}`;
}
