// pg is configured (src/infra/db/pg-types.ts) to return int8 and numeric as JS numbers.
const fs = require('fs');
const f = 'src/infra/db/db.types.ts';
fs.writeFileSync(f, fs.readFileSync(f, 'utf8')
  .replace(/^export type Int8 = ColumnType<string,/m, 'export type Int8 = ColumnType<number,')
  .replace(/^export type Numeric = ColumnType<string,/m, 'export type Numeric = ColumnType<number,'));
