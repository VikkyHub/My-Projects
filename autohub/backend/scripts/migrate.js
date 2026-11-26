// Runs dbmate (installed via npm, no global install needed) with DATABASE_URL from the env or .env.
const { execFileSync } = require('child_process');
const { join } = require('path');

function migrate(url, { quiet = false } = {}) {
  const bin = join(__dirname, '..', 'node_modules', '.bin', process.platform === 'win32' ? 'dbmate.cmd' : 'dbmate');
  execFileSync(bin, ['--migrations-dir', join(__dirname, '..', 'db', 'migrations'), '--no-dump-schema', '--wait', 'up'], {
    stdio: quiet ? 'ignore' : 'inherit',
    env: { ...process.env, DATABASE_URL: url },
    shell: process.platform === 'win32',
  });
}
module.exports = { migrate };

if (require.main === module) {
  try { process.loadEnvFile?.('.env'); } catch {}
  if (!process.env.DATABASE_URL) { console.error('DATABASE_URL is not set'); process.exit(1); }
  migrate(process.env.DATABASE_URL);
}
