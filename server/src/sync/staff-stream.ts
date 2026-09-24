import { Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import type { IncomingMessage, Server } from 'node:http';
import type { Duplex } from 'node:stream';
import * as jwt from 'jsonwebtoken';
import { WebSocket, WebSocketServer } from 'ws';
import { AuthService } from '../auth/auth.service';
import type { Principal } from '../auth/principal';
import { ChangeBus, type ChangeSignal } from '../scheduling/change-bus';
import { Clock } from '../scheduling/clock';
import { currentSeq } from '../scheduling/rows';

export const STREAM_PATH = '/v1/staff/stream';
const REVALIDATE_MS = 60_000;

interface Client {
  ws: WebSocket;
  token: string;
  principal: Principal;
  alive: boolean;
  expiry?: NodeJS.Timeout;
}

/**
 * WS /v1/staff/stream — pushes committed change-feed sequence numbers to staff devices
 * (design §6.3); the device then pulls `GET /sync?since=`. Authenticated with the same access
 * token as REST (Authorization header, or `access_token` query for clients that cannot set headers).
 * Rooms are per salon (from the verified token only) and per barber; managers get the whole salon.
 * The socket is closed when the token expires or the session/account is revoked.
 */
@Injectable()
export class StaffStream implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger('StaffStream');
  private readonly wss = new WebSocketServer({ noServer: true, maxPayload: 4096 });
  private readonly clients = new Set<Client>();
  private unsubscribe?: () => void;
  private timer?: NodeJS.Timeout;
  private server?: Server;
  private readonly onUpgradeBound = (req: IncomingMessage, socket: Duplex, head: Buffer) => void this.onUpgrade(req, socket, head);

  constructor(
    private readonly adapterHost: HttpAdapterHost,
    private readonly auth: AuthService,
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

  private async onUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (url.pathname !== STREAM_PATH) return this.reject(socket, 404, 'Not Found');
    const header = req.headers.authorization;
    const m = typeof header === 'string' ? /^Bearer ([A-Za-z0-9._~+/=-]+)$/.exec(header) : null;
    const token = m?.[1] ?? url.searchParams.get('access_token') ?? '';
    let principal: Principal | null = null;
    try {
      const r = token ? await this.auth.authenticate(token) : null;
      principal = r && (r.principal.role === 'barber' || r.principal.role === 'manager') ? r.principal : null;
      if (r && !principal) return this.reject(socket, 403, 'Forbidden');
      if (!r) return this.reject(socket, 401, 'Unauthorized');
      this.wss.handleUpgrade(req, socket, head, (ws) => void this.onConnection(ws, token, principal!, r.tenant.db));
    } catch (e) {
      this.logger.warn(`upgrade failed: ${(e as Error).message}`);
      this.reject(socket, 500, 'Internal Server Error');
    }
  }

  private async onConnection(ws: WebSocket, token: string, principal: Principal, db: Parameters<typeof currentSeq>[0]): Promise<void> {
    const c: Client = { ws, token, principal, alive: true };
    this.clients.add(c);
    const exp = (jwt.decode(token) as { exp?: number } | null)?.exp;
    if (exp) {
      c.expiry = setTimeout(() => ws.close(4401, 'token_expired'), Math.max(0, exp * 1000 - Date.now()));
      c.expiry.unref();
    }
    ws.on('pong', () => (c.alive = true));
    ws.on('message', () => undefined); // the stream is server → device only
    ws.on('close', () => {
      if (c.expiry) clearTimeout(c.expiry);
      this.clients.delete(c);
    });
    ws.on('error', () => undefined);
    try {
      ws.send(JSON.stringify({ type: 'hello', seq: await currentSeq(db), serverTime: new Date(this.clock.now()).toISOString() }));
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

  /** Keep-alive pings; drops dead sockets and ones whose session/account is no longer valid. */
  private async housekeeping(): Promise<void> {
    for (const c of [...this.clients]) {
      if (!c.alive) {
        c.ws.terminate();
        continue;
      }
      c.alive = false;
      c.ws.ping();
      const still = await this.auth.authenticate(c.token).catch(() => null);
      if (!still) c.ws.close(4401, 'session_revoked');
    }
  }
}
