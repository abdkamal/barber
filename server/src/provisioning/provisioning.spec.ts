import { isValidCurrency, isValidTimezone } from './provisioning.service';

describe('salon registration currency/timezone (ق34، ق41)', () => {
  it('accepts every currency offered by the staff app, including the shekel (ILS)', () => {
    for (const c of ['SAR', 'AED', 'KWD', 'QAR', 'BHD', 'OMR', 'JOD', 'EGP', 'ILS', 'USD']) expect(isValidCurrency(c)).toBe(true);
    expect(isValidCurrency('XXY')).toBe(false);
    expect(isValidCurrency('ils')).toBe(false); // the service upper-cases before validating
  });
  it('accepts every salon region offered at registration', () => {
    for (const tz of [
      'Asia/Riyadh', 'Asia/Dubai', 'Asia/Kuwait', 'Asia/Qatar', 'Asia/Bahrain', 'Asia/Muscat',
      'Asia/Amman', 'Asia/Hebron', 'Asia/Gaza', 'Asia/Jerusalem', 'Africa/Cairo',
    ]) expect(isValidTimezone(tz)).toBe(true);
    expect(isValidTimezone('Mars/Olympus')).toBe(false);
  });
});
