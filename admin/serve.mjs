import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const files = new Map([
  ['/', ['index.html', 'text/html']], ['/index.html', ['index.html', 'text/html']],
  ['/app.mjs', ['app.mjs', 'application/javascript']], ['/access.mjs', ['access.mjs', 'application/javascript']],
  ['/boot.mjs', ['boot.mjs', 'application/javascript']],
  ['/styles.css', ['styles.css', 'text/css']],
  ['/confidentialite.html', ['confidentialite.html', 'text/html']],
  ['/suppression-compte.html', ['suppression-compte.html', 'text/html']],
  ['/legal.json', ['legal.json', 'application/json']],
  ['/legal.mjs', ['legal.mjs', 'application/javascript']],
  ['/legal-page.mjs', ['legal-page.mjs', 'application/javascript']],
]);
const server = createServer(async (request, response) => {
  const entry = files.get(new URL(request.url, 'http://127.0.0.1:4173').pathname);
  if (!entry || request.method !== 'GET') { response.writeHead(404).end('Not found'); return; }
  try {
    const contents = await readFile(new URL(`public/${entry[0]}`, import.meta.url));
    response.writeHead(200, { 'Content-Type': `${entry[1]}; charset=utf-8`, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    response.end(contents);
  } catch { response.writeHead(500).end('Local preview unavailable'); }
});
server.listen(4173, '127.0.0.1', () => process.stdout.write('Admin preview: http://127.0.0.1:4173/?emulators=1\n'));
process.on('SIGTERM', () => server.close());
process.on('SIGINT', () => server.close());
