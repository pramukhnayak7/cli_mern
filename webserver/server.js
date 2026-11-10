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

const server = http.createServer((req, res) => {
  const m = req.url.match(/^\/p(\d+)$/);
  const ip = req.socket.remoteAddress;

  if (!m) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Use /p1, /p2, ... /pn\n');
    console.log(`[${ip}] 404 ${req.url}`);
    return;
  }

  const file = path.join(DIR, `p${m[1]}.txt`);
  fs.readFile(file, 'utf8', (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end(`Program ${m[1]} not found\n`);
      console.log(`[${ip}] 404 /p${m[1]}`);
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(data);
    console.log(`[${ip}] 200 /p${m[1]}`);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getIP();
  console.log('==============================');
  console.log(` Server: http://${ip}:${PORT}`);
  console.log(` Local:  http://localhost:${PORT}`);
  console.log(` Folder: ${DIR}`);
  console.log(` Example: curl -s http://${ip}:${PORT}/p1 | xclip -selection clipboard`);
  console.log('==============================');
});
