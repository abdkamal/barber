import { sniffImageKind, splitStoredPath } from './image-storage.service';

describe('sniffImageKind', () => {
  it('recognises JPEG, PNG and WebP magic bytes', () => {
    expect(sniffImageKind(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).toBe('jpeg');
    expect(sniffImageKind(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe('png');
    const webp = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP')]);
    expect(sniffImageKind(webp)).toBe('webp');
  });

  it('rejects SVG, plain text and truncated/garbage buffers', () => {
    expect(sniffImageKind(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>'))).toBeNull();
    expect(sniffImageKind(Buffer.from('hello world'))).toBeNull();
    expect(sniffImageKind(Buffer.alloc(0))).toBeNull();
    expect(sniffImageKind(Buffer.from([0xff, 0xd8]))).toBeNull(); // too short for the JPEG marker
  });
});

describe('splitStoredPath', () => {
  const salonId = '11111111-1111-4111-8111-111111111111';
  it('parses a well-formed stored path', () => {
    const filename = 'a'.repeat(32) + '.jpg';
    expect(splitStoredPath(`${salonId}/${filename}`)).toEqual({ salonId, filename });
  });
  it('rejects path traversal and malformed names', () => {
    expect(splitStoredPath(`${salonId}/../../etc/passwd`)).toBeNull();
    expect(splitStoredPath(`not-a-uuid/${'a'.repeat(32)}.jpg`)).toBeNull();
    expect(splitStoredPath(`${salonId}/short.jpg`)).toBeNull();
    expect(splitStoredPath(`${salonId}/${'a'.repeat(32)}.exe`)).toBeNull();
  });
});
