import { codePrefixFromName, salonCodeCandidate, salonDbName } from './salon-code';
import { SALON_CODE_RE } from '../common/normalize';

describe('salon code generation', () => {
  it('derives letters from Arabic names, skipping generic words and the article', () => {
    expect(codePrefixFromName('صالون الراحة')).toBe('RAHA');
    expect(codePrefixFromName('حلاقة النخبة')).toBe('NKHB');
    expect(codePrefixFromName('صالون')).toBe('SALW'); // only generic words → use them anyway
  });
  it('derives letters from Latin names', () => {
    expect(codePrefixFromName('The Gentlemen Barber')).toBe('GENT');
    expect(codePrefixFromName('Raha Salon')).toBe('RAHA');
  });
  it('falls back when nothing usable remains', () => {
    expect(codePrefixFromName('123 !!')).toBe('SALN');
  });
  it('produces codes matching the public format', () => {
    for (let i = 0; i < 20; i++) {
      const c = salonCodeCandidate('صالون الراحة', i);
      expect(c).toMatch(SALON_CODE_RE);
      expect(c.startsWith('RAHA-')).toBe(true);
    }
    expect(salonCodeCandidate('x y', 0, () => 0)).toBe('XY-10');
    expect(salonCodeCandidate('Raha', 12, () => 0.999)).toBe('RAHA-999');
  });
  it('maps codes to safe database names', () => {
    expect(salonDbName('saloni_salon_', 'RAHA-27')).toBe('saloni_salon_raha_27');
  });
});
