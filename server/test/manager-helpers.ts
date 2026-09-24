import request from 'supertest';
import type TestAgent from 'supertest/lib/agent';
import { PoolManager } from '../src/db/pools';
import { VendorService } from '../src/provisioning/vendor.service';
import { createManagerTestApp } from './manager-app';
import { testConfig, TestContext } from './helpers';

/** A tiny wrapper exposing get/post/put/delete pre-authenticated with a bearer token. */
export function authedAgent(ctx: TestContext, token: string) {
  const withAuth = (method: 'get' | 'post' | 'put' | 'delete') => (url: string) =>
    (ctx.http() as unknown as Record<string, (u: string) => any>)[method]!(url).set('Authorization', `Bearer ${token}`);
  return { get: withAuth('get'), post: withAuth('post'), put: withAuth('put'), delete: withAuth('delete') };
}

export async function startManagerApp(config = testConfig()): Promise<TestContext> {
  const app = await createManagerTestApp(config);
  await app.init();
  const pools = new PoolManager(config);
  return {
    app,
    config,
    http: () => request(app.getHttpServer()) as unknown as TestAgent,
    pools,
    vendor: new VendorService(config, pools),
    close: async () => {
      await app.close();
      await pools.close();
    },
  };
}
