/** Integration tests: real PostgreSQL (+ PgBouncer) from infra/docker-compose.yml. */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['**/*.int-spec.ts'],
  // @saloni/engine is consumed from source in tests (ESM-style '.js' specifiers mapped to .ts).
  moduleNameMapper: {
    '^@saloni/engine$': '<rootDir>/../packages/engine/src/index.ts',
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
  transform: { '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.json' }] },
  globalSetup: '<rootDir>/test/global-setup.ts',
  testTimeout: 60000,
};
