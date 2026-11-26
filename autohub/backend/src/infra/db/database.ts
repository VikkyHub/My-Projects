import { Global, Inject, Module, OnApplicationShutdown } from '@nestjs/common';
import { CamelCasePlugin, Kysely, PostgresDialect, Transaction } from 'kysely';
import { Pool, types } from 'pg';
import { ENV, Env } from '../../config/env';
import type { DB } from './db.types';

// Money is bigint paise; values stay far below 2^53 so JS numbers are exact.
types.setTypeParser(types.builtins.INT8, (v) => Number(v));
types.setTypeParser(types.builtins.NUMERIC, (v) => Number(v));

export type Database = Kysely<DB>;
export type Tx = Transaction<DB>;
export const KYSELY = Symbol('KYSELY');
export const InjectDb = () => Inject(KYSELY);

export function createDatabase(url: string): Database {
  return new Kysely<DB>({
    dialect: new PostgresDialect({ pool: new Pool({ connectionString: url, max: 10 }) }),
    plugins: [new CamelCasePlugin()],
  });
}

@Global()
@Module({
  providers: [{ provide: KYSELY, inject: [ENV], useFactory: (env: Env) => createDatabase(env.DATABASE_URL) }],
  exports: [KYSELY],
})
export class DatabaseModule implements OnApplicationShutdown {
  constructor(@InjectDb() private readonly db: Database) {}
  async onApplicationShutdown() {
    await this.db.destroy();
  }
}
