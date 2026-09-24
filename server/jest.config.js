/** Unit tests: pure logic, no database. */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.spec.ts'],
  // @saloni/engine is consumed from source in tests (ESM-style '.js' specifiers mapped to .ts).
  moduleNameMapper: {
    '^@saloni/engine$': '<rootDir>/../packages/engine/src/index.ts',
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
  transform: { '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.json' }] },
};
