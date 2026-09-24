import { generateResetCode, hashResetCode, normalizeResetCode, resetCodeMatches } from './reset-codes';

describe('reset codes', () => {
  const pepper = 'p'.repeat(40);
  const salon = '11111111-1111-1111-1111-111111111111';
  it('generates readable codes', () => {
    const c = generateResetCode();
    expect(c).toMatch(/^[A-HJKMNP-Z2-9]{5}-[A-HJKMNP-Z2-9]{5}$/);
    expect(new Set(Array.from({ length: 50 }, generateResetCode)).size).toBe(50);
  });
  it('matches case/format-insensitively and is bound to the salon', () => {
    const c = generateResetCode();
    const h = hashResetCode(pepper, salon, c);
    expect(resetCodeMatches(pepper, salon, c.toLowerCase().replace('-', ' '), h)).toBe(true);
    expect(resetCodeMatches(pepper, '22222222-2222-2222-2222-222222222222', c, h)).toBe(false);
    expect(resetCodeMatches(pepper, salon, 'AAAAA-AAAAA', h)).toBe(false);
    expect(normalizeResetCode('ab-cd e')).toBe('ABCDE');
  });
});
