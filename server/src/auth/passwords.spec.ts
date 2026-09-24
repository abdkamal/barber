import { PasswordHasher, passwordPolicyError } from './passwords';

describe('password policy', () => {
  it('requires 8 chars for customers and 10 for staff', () => {
    expect(passwordPolicyError('customer', '1234567')).toBe(8);
    expect(passwordPolicyError('customer', '12345678')).toBeNull();
    expect(passwordPolicyError('staff', '123456789')).toBe(10);
    expect(passwordPolicyError('staff', '1234567890')).toBeNull();
  });
  it('counts Arabic characters as characters and rejects blank / huge input', () => {
    expect(passwordPolicyError('customer', 'كلمةسرطو')).toBeNull();
    expect(passwordPolicyError('customer', '          ')).toBe(8);
    expect(passwordPolicyError('customer', 'x'.repeat(129))).toBe(8);
  });
});

describe('PasswordHasher', () => {
  const h = new PasswordHasher({ memoryCost: 4096, timeCost: 2, parallelism: 1 });
  it('hashes with argon2id and verifies', async () => {
    const hash = await h.hash('correct horse');
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(await h.verify(hash, 'correct horse')).toBe(true);
    expect(await h.verify(hash, 'wrong')).toBe(false);
    expect(await h.verify('not-a-hash', 'x')).toBe(false);
    expect(await h.verifyDummy('x')).toBe(false);
  });
});
