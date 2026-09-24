import { Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import type { IncomingMessage, Server } from 'node:http';
import type { Duplex } from 'node:stream';
import * as jwt from 'jsonwebtoken';
import { WebSocket, WebSocketServer } from 'ws';
import { AuthService } from '../auth/auth.service';
import type { Principal } from '../auth/principal';
import { TokenService } from '../auth/tokens';
import { ChangeBus, type ChangeSignal } from '../scheduling/change-bus';
import { Clock } from '../scheduling/clock';
import { currentSeq } from '../scheduling/rows';
import type { TenantContext } from '../tenancy/tenant-context';
import { TenantResolver } from '../tenancy/tenant-resolver.service';

export const STREAM_PATH = '/v1/staff/stream';
/** Sub-protocol the server selects; a client may also offer `bearer.<access token>` to authenticate. */
export const STREAM_PROTOCOL = 'saloni.v1';
const BEARER_PROTOCOL_PREFIX = 'bearer.';
const REVALIDATE_MS = 60_000;
/** An unauthenticated socket must send `{type: "auth", token}` within this time. */
const AUTH_TIMEOUT_MS = 10_000;
/** Review L6: sockets per signed-in staff account; the oldest is closed beyond this. */
export const MAX_CONNECTIONS_PER_PRINCIPAL = 3;

interface Client {
  ws: WebSocket;
  principal: Principal;
  /** Token version and role at authentication (re-checked in batches). */
  tv: number;
  alive: boolean;
  openedAt: number;
  expiry?: NodeJS.Timeout;
}

/**
 * WS /v1/staff/stream — pushes committed change-feed sequence numbers to staff devices
 * (design §6.3); the device then pulls `GET /sync?since=`. Review L6: the access token is never
 * taken from the URL (it would end up in proxy logs). It comes from the `Authorization` header,
 * from a `bearer.<token>` entry of `Sec-WebSocket-Protocol` (the server answers `saloni.v1`), or
 * from a first message `{type: "auth", token}` sent within 10 s. Rooms are per salon (from the
 * verified token only) and per barber; managers get the whole salon. At most 3 sockets per
 * account. Sessions are re-validated every minute in one query per salon; the socket is closed
 * (4401) when the token expires or the session/account is revoked.
 */
@Injectable()
export class StaffStream implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger('StaffStream');
  private readonly wss = new WebSocketServer({
    noServer: true,
    maxPayload: 4096,
    // Never echo the bearer entry back; select our protocol name when offered.
    handleProtocols: (protocols) => (protocols.has(STREAM_PROTOCOL) ? STREAM_PROTOCOL : false),
  });
  private readonly clients = new Set<Client>();
  private unsubscribe?: () => void;
  private timer?: NodeJS.Timeout;
  private server?: Server;
  private readonly onUpgradeBound = (req: IncomingMessage, socket: Duplex, head: Buffer) => void this.onUpgrade(req, socket, head);

  constructor(
    private readonly adapterHost: HttpAdapterHost,
    private readonly auth: AuthService,
    private readonly tokens: TokenService,
    private readonly resolver: TenantResolver,
    private readonly bus: ChangeBus,
    private readonly clock: Clock,
  ) {}

  onApplicationBootstrap(): void {
    this.server = this.adapterHost.httpAdapter?.getHttpServer() as Server | undefined;
    this.server?.on('upgrade', this.onUpgradeBound);
    this.unsubscribe = this.bus.subscribe((s) => this.onSignal(s));
    this.timer = setInterval(() => void this.housekeeping(), REVALIDATE_MS);
    this.timer.unref();
  }

  onApplicationShutdown(): void {
    this.server?.off('upgrade', this.onUpgradeBound);
    this.unsubscribe?.();
    if (this.timer) clearInterval(this.timer);
    for (const c of this.clients) c.ws.terminate();
    this.clients.clear();
    this.wss.close();
  }

  connectionCount(): number {
    return this.clients.size;
  }

  private reject(socket: Duplex, status: number, text: string): void {
    socket.write(`HTTP/1.1 ${status} ${text}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
    socket.destroy();
  }

  private static tokenFrom(req: IncomingMessage): string | null {
    const header = req.headers.authorization;
    const m = typeof header === 'string' ? /^Bearer ([A-Za-z0-9._~+/=-]+)$/.exec(header) : null;
    if (m) return m[1]!;
    const protos = String(req.headers['sec-websocket-protocol'] ?? '')
      .split(',')
      .map((p) => p.trim());
    const bearer = protos.find((p) => p.startsWith(BEARER_PROTOCOL_PREFIX));
    return bearer ? bearer.slice(BEARER_PROTOCOL_PREFIX.length) || null : null;
  }

  private async onUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (url.pathname !== STREAM_PATH) return this.reject(socket, 404, 'Not Found');
    const token = StaffStream.tokenFrom(req);
    try {
      if (!token) {
        // No credentials in the handshake: accept and wait for the first message to authenticate.
        this.wss.handleUpgrade(req, socket, head, (ws) => this.awaitAuthMessage(ws));
        return;
      }
      const r = await this.check(token);
      if (r === 'forbidden') return this.reject(socket, 403, 'Forbidden');
      if (!r) return this.reject(socket, 401, 'Unauthorized');
      this.wss.handleUpgrade(req, socket, head, (ws) => void this.onConnection(ws, token, r.principal, r.tenant));
    } catch (e) {
      this.logger.warn(`upgrade failed: ${(e as Error).message}`);
      this.reject(socket, 500, 'Internal Server Error');
    }
  }

  private async check(token: string): Promise<{ principal: Principal; tenant: TenantContext } | 'forbidden' | null> {
    const r = await this.auth.authenticate(token);
    if (!r) return null;
    if (r.principal.role !== 'barber' && r.principal.role !== 'manager') return 'forbidden';
    return r;
  }

  private awaitAuthMessage(ws: WebSocket): void {
    const timer = setTimeout(() => ws.close(4401, 'auth_timeout'), AUTH_TIMEOUT_MS);
    timer.unref();
    ws.once('message', (raw) => {
      clearTimeout(timer);
      void (async () => {
        let token = '';
        try {
          const msg = JSON.parse(String(raw)) as { type?: unknown; token?: unknown };
          if (msg.type === 'auth' && typeof msg.token === 'string') token = msg.token;
        } catch {
          /* not JSON */
        }
        const r = token ? await this.check(token).catch(() => null) : null;
        if (!r) return ws.close(4401, 'unauthorized');
        if (r === 'forbidden') return ws.close(4403, 'forbidden');
        await this.onConnection(ws, token, r.principal, r.tenant);
      })();
    });
    ws.on('error', () => undefined);
  }

  private async onConnection(ws: WebSocket, token: string, principal: Principal, tenant: TenantContext): Promise<void> {
    const claims = this.tokens.verifyAccess(token);
    const c: Client = { ws, principal, tv: claims?.tv ?? -1, alive: true, openedAt: this.clock.now() };
    // Review L6: cap sockets per account — the oldest one goes.
    const mine = [...this.clients].filter((x) => x.principal.salonId === principal.salonId && x.principal.subjectId === principal.subjectId);
    mine.sort((a, b) => a.openedAt - b.openedAt);
    while (mine.length >= MAX_CONNECTIONS_PER_PRINCIPAL) {
      const old = mine.shift()!;
      this.clients.delete(old);
      old.ws.close(4408, 'too_many_connections');
    }
    this.clients.add(c);
    const exp = (jwt.decode(token) as { exp?: number } | null)?.exp;
    if (exp) {
      c.expiry = setTimeout(() => ws.close(4401, 'token_expired'), Math.max(0, exp * 1000 - Date.now()));
      c.expiry.unref();
    }
    ws.on('pong', () => (c.alive = true));
    ws.on('message', () => undefined); // after authentication the stream is server → device only
    ws.on('close', () => {
      if (c.expiry) clearTimeout(c.expiry);
      this.clients.delete(c);
    });
    ws.on('error', () => undefined);
    try {
      ws.send(JSON.stringify({ type: 'hello', seq: await currentSeq(tenant.db), serverTime: new Date(this.clock.now()).toISOString() }));
    } catch {
      /* socket already gone */
    }
  }

  private onSignal(s: ChangeSignal): void {
    const msg = JSON.stringify({ type: 'changes', seq: s.seq });
    for (const c of this.clients) {
      if (c.principal.salonId !== s.salonId) continue; // tenant-scoped rooms
      const mine = c.principal.role === 'manager' || s.staffIds.includes('*') || s.staffIds.includes(c.principal.subjectId);
      if (mine && c.ws.readyState === WebSocket.OPEN) c.ws.send(msg);
    }
  }

  /**
   * Keep-alive pings; drops dead sockets. Review L6: sessions and accounts are re-validated in one
   * query per salon (not a full token authentication per socket).
   */
  async housekeeping(): Promise<void> {
    const bySalon = new Map<string, Client[]>();
    for (const c of [...this.clients]) {
      if (!c.alive) {
        c.ws.terminate();
        this.clients.delete(c);
        continue;
      }
      c.alive = false;
      c.ws.ping();
      const list = bySalon.get(c.principal.salonId) ?? [];
      list.push(c);
      bySalon.set(c.principal.salonId, list);
    }
    for (const [salonId, list] of bySalon) {
      try {
        const t = await this.resolver.fromVerifiedToken(salonId);
        if (!t || t.salon.status === 'suspended') {
          for (const c of list) c.ws.close(4401, 'session_revoked');
          continue;
        }
        const { rows } = await t.db.query<{ sess: string; tv: number; role: string }>(
          `SELECT s.id AS sess, st.token_version AS tv, st.role
             FROM sessions s JOIN staff st ON st.id = s.subject_id
            WHERE s.id = ANY($1::uuid[]) AND s.subject_kind = 'staff' AND s.revoked_at IS NULL AND st.active`,
          [list.map((c) => c.principal.sessionId)],
        );
        const ok = new Map(rows.map((r) => [r.sess, r]));
        for (const c of list) {
          const r = ok.get(c.principal.sessionId);
          if (!r || r.tv !== c.tv || r.role !== c.principal.role) c.ws.close(4401, 'session_revoked');
        }
      } catch (e) {
        this.logger.warn(`revalidation failed for ${salonId}: ${(e as Error).message}`);
      }
    }
  }
}
