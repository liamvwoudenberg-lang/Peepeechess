// Only imported by the isolated local review server on port 3001.
import { readFileSync } from 'node:fs';
const file = process.env.AUDIT_CLOCK_FILE;
if (!file || process.env.PORT !== '3001') throw new Error('Clock shim requires the isolated review server');
const realNow = Date.now.bind(Date);
Date.now = () => realNow() + Number(readFileSync(file, 'utf8').trim() || '0');
