/** Integration tests: real PostgreSQL (+ PgBouncer) from infra/docker-compose.yml. */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['**/*.int-spec.ts'],
  transform: { '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.json' }] },
  globalSetup: '<rootDir>/test/global-setup.ts',
  testTimeout: 60000,
};
