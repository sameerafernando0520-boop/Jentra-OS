import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve(process.argv[2]);
const port = Number(process.argv[3] || 8396);
const types = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.ttf':'font/ttf', '.otf':'font/otf'};
http.createServer(async (request, response) => {
  try {
    const route = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    let file = path.resolve(root, '.' + route);
    if (file !== root && !file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
    if (route.endsWith('/')) file = path.join(file, 'index.html');
    let bytes;
    try { bytes = await readFile(file); }
    catch { if (path.extname(file)) { response.writeHead(404).end(); return; } file = path.join(root, 'index.html'); bytes = await readFile(file); }
    response.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control':'no-store'});
    response.end(bytes);
  } catch { response.writeHead(500).end(); }
}).listen(port, '127.0.0.1', () => console.log(`Jentra Sales local verification: http://127.0.0.1:${port}`));
