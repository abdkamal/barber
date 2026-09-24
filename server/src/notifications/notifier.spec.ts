import { generateKeyPairSync } from 'node:crypto';
import * as jwt from 'jsonwebtoken';
import { formatArabicDuration } from '../scheduling/time';
import { FakeNotifier, FcmNotifier, fcmCredentialsFromEnv } from './notifier';
import { Texts } from './texts';

describe('notifications', () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  const creds = { projectId: 'saloni-test', clientEmail: 'push@saloni-test.iam.gserviceaccount.com', privateKey: pem };

  function fakeFetch(responses: Array<{ status: number; body: unknown }>) {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const f = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      const r = responses.shift() ?? { status: 200, body: {} };
      return new Response(typeof r.body === 'string' ? r.body : JSON.stringify(r.body), { status: r.status });
    }) as unknown as typeof fetch;
    return { f, calls };
  }

  it('FCM HTTP v1: OAuth with a signed service-account assertion, then messages:send (token cached)', async () => {
    const { f, calls } = fakeFetch([
      { status: 200, body: { access_token: 'ya29.token', expires_in: 3600 } },
      { status: 200, body: { name: 'projects/saloni-test/messages/1' } },
      { status: 200, body: { name: 'projects/saloni-test/messages/2' } },
    ]);
    const n = new FcmNotifier(creds, f);
    const msg = { token: 'device-token', title: 'اقترب دورك', body: 'نص', data: { type: 'called', bookingId: 'b1' }, highPriority: true };
    expect(await n.send(msg)).toBe('ok');
    expect(await n.send(msg)).toBe('ok');
    expect(calls).toHaveLength(3);
    const form = new URLSearchParams(String(calls[0]!.init.body));
    expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    const claims = jwt.verify(form.get('assertion')!, publicKey.export({ type: 'spki', format: 'pem' }).toString(), { algorithms: ['RS256'] }) as jwt.JwtPayload;
    expect(claims).toMatchObject({ iss: creds.clientEmail, aud: 'https://oauth2.googleapis.com/token', scope: 'https://www.googleapis.com/auth/firebase.messaging' });
    expect(calls[1]!.url).toBe('https://fcm.googleapis.com/v1/projects/saloni-test/messages:send');
    expect((calls[1]!.init.headers as Record<string, string>).Authorization).toBe('Bearer ya29.token');
    const body = JSON.parse(String(calls[1]!.init.body));
    expect(body.message).toEqual({
      token: 'device-token',
      notification: { title: 'اقترب دورك', body: 'نص' },
      data: { type: 'called', bookingId: 'b1' },
      android: { priority: 'HIGH' },
    });
  });

  it('reports unregistered tokens and transient errors', async () => {
    const { f } = fakeFetch([
      { status: 200, body: { access_token: 't', expires_in: 3600 } },
      { status: 404, body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } },
      { status: 503, body: 'unavailable' },
    ]);
    const n = new FcmNotifier(creds, f);
    const msg = { token: 'x', title: 't', body: 'b', data: { type: 'called' }, highPriority: false };
    expect(await n.send(msg)).toBe('invalid_token');
    expect(await n.send(msg)).toBe('error');
  });

  it('credentials come from the environment; absent → disabled', () => {
    expect(fcmCredentialsFromEnv({})).toBeNull();
    expect(fcmCredentialsFromEnv({ FCM_PROJECT_ID: 'p', FCM_CLIENT_EMAIL: 'e', FCM_PRIVATE_KEY: 'a\\nb' })).toEqual({ projectId: 'p', clientEmail: 'e', privateKey: 'a\nb' });
  });

  it('fake notifier records messages and rejects "invalid" tokens', async () => {
    const f = new FakeNotifier();
    expect(await f.send({ token: 'invalid-1', title: '', body: '', data: {}, highPriority: false })).toBe('invalid_token');
    expect(await f.send({ token: 'ok', title: 't', body: 'b', data: {}, highPriority: false })).toBe('ok');
    expect(f.sent).toHaveLength(1);
  });

  it('Arabic texts follow design §8', () => {
    const tz = 'Asia/Riyadh';
    const t = Date.parse('2026-03-05T13:30:00Z');
    expect(Texts.bookingConfirmed('أحمد', t, tz).body).toMatch(/^تم حجز دورك عند أحمد — الوقت المتوقع /);
    expect(Texts.called('أحمد', t, tz).body).toMatch(/^اقترب دورك عند أحمد — يُتوقع أن تبدأ خدمتك نحو /);
    expect(Texts.etaChanged(t, 40 * 60_000, 'سبب', tz).body).toMatch(/\(تأخر .+\) — السبب: سبب$/);
    expect(Texts.etaChanged(t, -40 * 60_000, 'سبب', tz).body).toContain('تقدّم');
    expect(Texts.noShow().body).toBe('سُجّل حجزك اليوم كـ«لم يحضر»');
    expect(Texts.cancelledClosing('انتهى الدوام').body).toBe('نعتذر، أُلغي حجزك لتجاوز وقت الإغلاق — انتهى الدوام');
    expect(Texts.overrun('خالد').body).toBe('تجاوزت خدمة خالد مدتها المقدرة — لا تنسَ الضغط على «إنهاء»');
    expect(formatArabicDuration(60 * 60_000)).toBe('ساعة');
    expect(formatArabicDuration(2 * 60_000)).toBe('دقيقتين');
  });
});
