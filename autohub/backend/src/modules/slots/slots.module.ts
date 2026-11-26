import { Injectable, Logger, Module, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { sql } from 'kysely';
import { Database, InjectDb } from '../../infra/db/database';

/**
 * Keeps 14 days of bookable slots materialised. In-process for the MVP; moves to the BullMQ worker
 * (src/worker.ts) once there is more than one API instance — the SQL function is idempotent either way.
 */
@Injectable()
export class SlotGenerator implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly log = new Logger('Slots');
  private timer?: NodeJS.Timeout;
  constructor(@InjectDb() private readonly db: Database) {}

  async run(vendorId?: string) {
    const r = await sql<{ n: number }>`SELECT generate_vendor_slots(14, ${vendorId ?? null}::uuid) AS n`.execute(this.db);
    return r.rows[0].n;
  }

  async onApplicationBootstrap() {
    if (process.env.NODE_ENV === 'test') return;
    const n = await this.run().catch((e) => { this.log.error(e); return 0; });
    if (n) this.log.log(`Generated ${n} new slots`);
    this.timer = setInterval(() => this.run().catch((e) => this.log.error(e)), 6 * 3600_000);
    this.timer.unref();
  }

  onApplicationShutdown() {
    if (this.timer) clearInterval(this.timer);
  }
}

@Module({ providers: [SlotGenerator], exports: [SlotGenerator] })
export class SlotsModule {}
