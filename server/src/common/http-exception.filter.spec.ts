import { Logger } from '@nestjs/common';
import type { ArgumentsHost } from '@nestjs/common';
import { Errors } from './errors';
import { AllExceptionsFilter, INTERNAL_CODE, routeOf } from './http-exception.filter';
import { requestIdMiddleware } from './request-id';

function fakeReq(over: Record<string, unknown> = {}) {
  const headers: Record<string, string> = (over.headers as Record<string, string>) ?? {};
  return {
    method: 'POST',
    baseUrl: '',
    originalUrl: '/v1/salons/register?token=secret-token',
    url: '/v1/salons/register?token=secret-token',
    route: { path: '/v1/salons/register' },
    body: { owner: { password: 'P@ssw0rd-secret' } },
    header: (n: string) => headers[n.toLowerCase()] ?? headers[n],
    ...over,
  } as any;
}

function fakeRes() {
  const res: any = { headers: {} as Record<string, string>, statusCode: 0, body: undefined, headersSent: false };
  res.setHeader = (k: string, v: string) => (res.headers[k.toLowerCase()] = v);
  res.status = (s: number) => ((res.statusCode = s), res);
  res.json = (b: unknown) => ((res.body = b), res);
  return res;
}

const host = (req: unknown, res: unknown) =>
  ({ switchToHttp: () => ({ getRequest: () => req, getResponse: () => res }) }) as unknown as ArgumentsHost;

describe('request id + exception filter (phase 11: diagnosable failures)', () => {
  afterEach(() => jest.restoreAllMocks());

  it('generates a request id, or keeps a well-formed incoming one, and echoes it in X-Request-Id', () => {
    const next = jest.fn();
    const req1 = fakeReq();
    const res1 = fakeRes();
    requestIdMiddleware(req1, res1, next);
    expect(req1.requestId).toMatch(/^[0-9a-f-]{36}$/);
    expect(res1.headers['x-request-id']).toBe(req1.requestId);

    const req2 = fakeReq({ headers: { 'x-request-id': 'caddy-1234abcd' } });
    const res2 = fakeRes();
    requestIdMiddleware(req2, res2, next);
    expect(req2.requestId).toBe('caddy-1234abcd');

    const req3 = fakeReq({ headers: { 'x-request-id': 'bad id with spaces\n' } });
    requestIdMiddleware(req3, fakeRes(), next);
    expect(req3.requestId).not.toContain(' ');
    expect(next).toHaveBeenCalledTimes(3);
  });

  it('answers an unhandled error with 500 {code: INTERNAL, requestId} and logs id, route and stack — never secrets', () => {
    const error = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const req = fakeReq({ requestId: 'req-abcdef123456' });
    const res = fakeRes();
    const boom = new TypeError("Cannot read properties of undefined (reading 'x')");
    new AllExceptionsFilter().catch(boom, host(req, res));
    expect(res.statusCode).toBe(500);
    expect(res.body).toEqual({ error: { code: INTERNAL_CODE, message: expect.any(String), requestId: 'req-abcdef123456' } });
    expect(error).toHaveBeenCalledTimes(1);
    const [line, stack] = error.mock.calls[0]! as [string, string];
    expect(line).toContain('req-abcdef123456');
    expect(line).toContain('POST /v1/salons/register');
    expect(line).toContain('TypeError');
    expect(stack).toBe(boom.stack);
    const logged = JSON.stringify(error.mock.calls);
    expect(logged).not.toContain('secret');
  });

  it('logs handled validation errors with their paths (no values) and keeps the body shape', () => {
    const warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const req = fakeReq({ requestId: 'req-000000000001' });
    const res = fakeRes();
    new AllExceptionsFilter().catch(Errors.validation([{ path: 'salon.timezone', code: 'invalid_timezone' }]), host(req, res));
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: { code: 'VALIDATION_FAILED', message: expect.any(String), details: [{ path: 'salon.timezone', code: 'invalid_timezone' }] } });
    expect(warn.mock.calls[0]![0]).toContain('[req-000000000001] POST /v1/salons/register -> 400 VALIDATION_FAILED');
    expect(warn.mock.calls[0]![0]).toContain('salon.timezone');
  });

  it('route falls back to the path without its query string', () => {
    expect(routeOf(fakeReq({ route: undefined }))).toBe('/v1/salons/register');
  });
});
