import { Logger } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import * as jwt from 'jsonwebtoken';

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  /** FCM data payload: `{type, bookingId?}` (api.md "التنبيهات"). Values are strings. */
  data: Record<string, string>;
  highPriority: boolean;
}

export type SendResult = 'ok' | 'invalid_token' | 'error';

/** Push transport (design §8, ق12: FCM only). */
export interface Notifier {
  readonly enabled: boolean;
  send(msg: PushMessage): Promise<SendResult>;
}

export const NOTIFIER = Symbol('NOTIFIER');

/** Used when no FCM credentials are configured: nothing is sent; notifications are still recorded. */
export class DisabledNotifier implements Notifier {
  readonly enabled = false;
  async send(): Promise<SendResult> {
    return 'error';
  }
}

/** In-memory transport for tests. Tokens starting with "invalid" are rejected as unregistered. */
export class FakeNotifier implements Notifier {
  readonly enabled = true;
  readonly sent: PushMessage[] = [];

  async send(msg: PushMessage): Promise<SendResult> {
    if (msg.token.startsWith('invalid')) return 'invalid_token';
    this.sent.push(msg);
    return 'ok';
  }

  clear(): void {
    this.sent.length = 0;
  }
}

export interface FcmCredentials {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

/**
 * Credentials from the environment: FCM_SERVICE_ACCOUNT_FILE (service-account JSON path) or
 * FCM_PROJECT_ID + FCM_CLIENT_EMAIL + FCM_PRIVATE_KEY (\n-escaped). Null when not configured.
 */
export function fcmCredentialsFromEnv(env: NodeJS.ProcessEnv = process.env): FcmCredentials | null {
  if (env.FCM_SERVICE_ACCOUNT_FILE) {
    const j = JSON.parse(readFileSync(env.FCM_SERVICE_ACCOUNT_FILE, 'utf8')) as { project_id: string; client_email: string; private_key: string };
    return { projectId: j.project_id, clientEmail: j.client_email, privateKey: j.private_key };
  }
  if (env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY) {
    return { projectId: env.FCM_PROJECT_ID, clientEmail: env.FCM_CLIENT_EMAIL, privateKey: env.FCM_PRIVATE_KEY.replace(/\\n/g, '\n') };
  }
  return null;
}

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/** Firebase Cloud Messaging HTTP v1 with a service-account OAuth token (RS256 JWT bearer grant). */
export class FcmNotifier implements Notifier {
  readonly enabled = true;
  private readonly logger = new Logger('FCM');
  private access: { token: string; expires: number } | null = null;

  constructor(
    private readonly creds: FcmCredentials,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  private async accessToken(): Promise<string> {
    const now = Date.now();
    if (this.access && this.access.expires - 60_000 > now) return this.access.token;
    const assertion = jwt.sign({ scope: SCOPE }, this.creds.privateKey, {
      algorithm: 'RS256',
      issuer: this.creds.clientEmail,
      audience: TOKEN_URL,
      expiresIn: 3600,
    });
    const res = await this.fetchImpl(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
    });
    if (!res.ok) throw new Error(`FCM OAuth failed: HTTP ${res.status}`);
    const j = (await res.json()) as { access_token: string; expires_in: number };
    this.access = { token: j.access_token, expires: now + j.expires_in * 1000 };
    return j.access_token;
  }

  async send(msg: PushMessage): Promise<SendResult> {
    try {
      const token = await this.accessToken();
      const res = await this.fetchImpl(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(this.creds.projectId)}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: msg.token,
            notification: { title: msg.title, body: msg.body },
            data: msg.data,
            android: { priority: msg.highPriority ? 'HIGH' : 'NORMAL' },
          },
        }),
      });
      if (res.ok) return 'ok';
      if (res.status === 404 || res.status === 400) {
        const text = await res.text();
        if (/UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT/.test(text)) return 'invalid_token';
      }
      this.logger.warn(`FCM send failed: HTTP ${res.status}`);
      return 'error';
    } catch (e) {
      this.logger.warn(`FCM send error: ${(e as Error).message}`);
      return 'error';
    }
  }
}
