// Loads reference data (+ demo data unless --reference-only). Works without psql installed.
//   DATABASE_URL=... node scripts/seed.js [--reference-only]
const { readFileSync } = require('fs');
const { join } = require('path');
const { Client } = require('pg');

async function seed(url, { demo = true } = {}) {
  const client = new Client({ connectionString: url });
  await client.connect();
  try {
    const files = ['001_reference_data.sql', ...(demo ? ['002_demo_data.sql'] : [])];
    for (const f of files) {
      await client.query(readFileSync(join(__dirname, '..', 'db', 'seeds', f), 'utf8'));
      console.log(`seeded ${f}`);
    }
  } finally {
    await client.end();
  }
}

module.exports = { seed };

if (require.main === module) {
  try { process.loadEnvFile?.('.env'); } catch {}
  if (!process.env.DATABASE_URL) { console.error('DATABASE_URL is not set'); process.exit(1); }
  seed(process.env.DATABASE_URL, { demo: !process.argv.includes('--reference-only') })
    .catch((e) => { console.error(e.message); process.exit(1); });
}
