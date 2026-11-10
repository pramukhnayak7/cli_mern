#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 8050;
const DIR = path.join(__dirname, 'programs');

function getIP() {
  const ifaces = os.networkInterfaces();
  for (const name in ifaces) {
    for (const iface of ifaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return '127.0.0.1';
}

function isCurl(req) {
  const ua = req.headers['user-agent'] || '';
  return /curl/i.test(ua);
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  const ip = req.socket.remoteAddress;

  // ---------- /server.js : curl ONLY (browsers get 404) ----------
  if (url === '/server.js' && req.method === 'GET') {
    if (!isCurl(req)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
      console.log(`[${ip}] 404 /server.js (browser blocked)`);
      return;
    }
    const f = path.join(__dirname, 'server.js');
    if (fs.existsSync(f)) {
      res.writeHead(200, { 'Content-Type': 'application/javascript' });
      res.end(fs.readFileSync(f, 'utf8'));
      console.log(`[${ip}] 200 /server.js (curl download)`);
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
    }
    return;
  }

  // ---------- Serve raw program text: /p1, /p2, ... ----------
  const m = url.match(/^\/p(\d+)$/);
  if (m && req.method === 'GET') {
    const file = path.join(DIR, 'p' + m[1] + '.txt');
    fs.readFile(file, 'utf8', (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Program ' + m[1] + ' not found\n');
        console.log(`[${ip}] 404 /p${m[1]}`);
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(data);
      console.log(`[${ip}] 200 /p${m[1]}`);
    });
    return;
  }

  // ---------- Everything else: 404 (no browser pages, no editor) ----------
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found\n');
  console.log(`[${ip}] 404 ${req.url}`);
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getIP();
  console.log('========================================');
  console.log(' Node.js Web Server — port ' + PORT);
  console.log(' Server:  http://' + ip + ':' + PORT);
  console.log(' Local:   http://localhost:' + PORT);
  console.log(' Folder:  ' + DIR);
  console.log(' Download server.js:');
  console.log('   curl -s http://' + ip + ':' + PORT + '/server.js > server.js');
  console.log(' Programs: /p1, /p2, ... /pn');
  console.log('========================================');
});
