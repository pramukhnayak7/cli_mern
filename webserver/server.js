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

  // /p1 : curl ONLY — serves this Node.js server code (browsers get 404)
  if (url === '/p1' && req.method === 'GET') {
    if (!isCurl(req)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
      console.log('[' + ip + '] 404 /p1 (browser blocked)');
      return;
    }
    const f = path.join(__dirname, 'server.js');
    if (fs.existsSync(f)) {
      res.writeHead(200, { 'Content-Type': 'application/javascript' });
      res.end(fs.readFileSync(f, 'utf8'));
      console.log('[' + ip + '] 200 /p1 (curl download -> server.js)');
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
    }
    return;
  }

  // Serve raw program text: /p2, /p3, ...
  const m = url.match(/^\/p(\d+)$/);
  if (m && req.method === 'GET') {
    const num = parseInt(m[1], 10);
    if (num === 1) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
      console.log('[' + ip + '] 404 /p1 (reserved)');
      return;
    }
    const file = path.join(DIR, 'p' + num + '.txt');
    fs.readFile(file, 'utf8', (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Program ' + num + ' not found\n');
        console.log('[' + ip + '] 404 /p' + num);
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(data);
      console.log('[' + ip + '] 200 /p' + num);
    });
    return;
  }

  // Everything else: 404 (no browser pages, no editor)
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found\n');
  console.log('[' + ip + '] 404 ' + url);
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getIP();
  console.log('========================================');
  console.log(' Node.js Web Server — port ' + PORT);
  console.log(' Server:  http://' + ip + ':' + PORT);
  console.log(' Local:   http://localhost:' + PORT);
  console.log(' Folder:  ' + DIR);
  console.log(' Download server.js:');
  console.log('   curl -s http://' + ip + ':' + PORT + '/p1 > server.js');
  console.log('   node server.js');
  console.log(' Programs: /p2, /p3, ... /pn');
  console.log('========================================');
});
