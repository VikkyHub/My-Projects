import { Client } from 'pg';

/** Fresh database per test run: migrate + reference + demo data. */
export default async function globalSetup() {
  const url = new URL(process.env.TEST_DATABASE_URL ?? 'postgres://postgres@127.0.0.1:5499/autohub_e2e?sslmode=disable');
  const dbName = url.pathname.slice(1);
  if (!/_e2e$|_test$/.test(dbName)) throw new Error(`Refusing to reset "${dbName}": test DB name must end in _e2e or _test`);
  const admin = new URL(url.toString());
  admin.pathname = '/postgres';
  const c = new Client({ connectionString: admin.toString() });
  await c.connect();
  await c.query(`DROP DATABASE IF EXISTS "${dbName}" WITH (FORCE)`);
  await c.query(`CREATE DATABASE "${dbName}"`);
  await c.end();

  const { migrate } = require('../scripts/migrate.js');
  const { seed } = require('../scripts/seed.js');
  const log = console.log;
  console.log = () => {};
  try {
    migrate(url.toString(), { quiet: true });
    await seed(url.toString());
  } finally {
    console.log = log;
  }
  process.env.TEST_DATABASE_URL = url.toString();
}
