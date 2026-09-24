import { normalizeInternationalPhone, normalizePhone, normalizeSalonCode, normalizeUsername, SALON_CODE_RE, USERNAME_RE } from './normalize';

describe('normalizePhone', () => {
  it('accepts plain and formatted numbers', () => {
    expect(normalizePhone('0501234567')).toBe('0501234567');
    expect(normalizePhone(' 050-123 4567 ')).toBe('0501234567');
    expect(normalizePhone('+966 50 123 4567')).toBe('+966501234567');
    expect(normalizePhone('00966501234567')).toBe('+966501234567');
  });
  it('converts Arabic-Indic digits', () => {
    expect(normalizePhone('٠٥٠١٢٣٤٥٦٧')).toBe('0501234567');
    expect(normalizePhone('۰۵۰۱۲۳۴۵۶۷')).toBe('0501234567');
  });
  it('rejects garbage', () => {
    expect(normalizePhone('abc')).toBeNull();
    expect(normalizePhone('123')).toBeNull();
    expect(normalizePhone('+1234567890123456')).toBeNull();
    expect(normalizePhone('05O1234567')).toBeNull();
  });
});

describe('normalizeInternationalPhone (WhatsApp, any country code)', () => {
  it('accepts any country code with + or 00', () => {
    expect(normalizeInternationalPhone('+970 59 123 4567')).toBe('+970591234567');
    expect(normalizeInternationalPhone('00972-50-123-4567')).toBe('+972501234567');
    expect(normalizeInternationalPhone('+1 (415) 555-0100')).toBe('+14155550100');
    expect(normalizeInternationalPhone('+٩٦٦٥٠١٢٣٤٥٦٧')).toBe('+966501234567');
  });
  it('rejects local numbers and invalid lengths', () => {
    expect(normalizeInternationalPhone('0591234567')).toBeNull();
    expect(normalizeInternationalPhone('+0591234567')).toBeNull();
    expect(normalizeInternationalPhone('+1234567')).toBeNull();
    expect(normalizeInternationalPhone('+1234567890123456')).toBeNull();
  });
});

describe('usernames and salon codes', () => {
  it('normalises', () => {
    expect(normalizeUsername('  Ahmed.B ')).toBe('ahmed.b');
    expect(normalizeSalonCode(' raha-٢٧ ')).toBe('RAHA-27');
  });
  it('validates', () => {
    expect(USERNAME_RE.test('ahmed_1')).toBe(true);
    expect(USERNAME_RE.test('ab')).toBe(false);
    expect(USERNAME_RE.test('a b c')).toBe(false);
    expect(SALON_CODE_RE.test('RAHA-27')).toBe(true);
    expect(SALON_CODE_RE.test('RAHA27')).toBe(false);
  });
});
