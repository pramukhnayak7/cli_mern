const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const qs = require('querystring');

const PORT = 8050;
const DIR = path.join(__dirname, 'programs');
const SECRET = '__xk9m2_admin__';   // obscure path — not index.html, hidden from casual scans

function getIP() {
  const ifaces = os.networkInterfaces();
  for (const name in ifaces) {
    for (const iface of ifaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return '127.0.0.1';
}

function listPrograms() {
  try {
    return fs.readdirSync(DIR)
      .filter(f => /^p\d+\.txt$/.test(f))
      .sort((a, b) => {
        const na = parseInt(a.match(/\d+/)[0], 10);
        const nb = parseInt(b.match(/\d+/)[0], 10);
        return na - nb;
      });
  } catch (e) {
    return [];
  }
}

function readFileSafe(name) {
  const file = path.join(DIR, name);
  const real = fs.realpathSync(file);
  const dirReal = fs.realpathSync(DIR);
  if (!real.startsWith(dirReal + path.sep)) return null;
  if (!fs.existsSync(real)) return null;
  return fs.readFileSync(real, 'utf8');
}

function writeFileSafe(name, content) {
  const file = path.join(DIR, name);
  const real = fs.realpathSync(file);
  const dirReal = fs.realpathSync(DIR);
  if (!real.startsWith(dirReal + path.sep)) return false;
  fs.writeFileSync(real, content, 'utf8');
  return true;
}

function htmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

const LOCAL_IPS = ['127.0.0.1', '::1', '::ffff:127.0.0.1', 'localhost'];

function isLocal(ip) {
  return LOCAL_IPS.includes(ip) || ip.startsWith('127.');
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  const query = qs.parse(req.url.split('?')[1] || '');
  const ip = req.socket.remoteAddress;

  // ---------- Phone-only access: 404 for any external browser ----------
  if (!isLocal(ip)) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found\n');
    console.log(`[${ip}] 404 BLOCKED ${req.url}`);
    return;
  }

  const m = url.match(/^\/p(\d+)$/);

  // ---------- Serve raw program text: /p1, /p2, ... ----------
  if (m && req.method === 'GET') {
    const data = readFileSafe(`p${m[1]}.txt`);
    if (data === null) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end(`Program ${m[1]} not found\n`);
      console.log(`[${ip}] 404 /p${m[1]}`);
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(data);
    console.log(`[${ip}] 200 /p${m[1]}`);
    return;
  }

  // ---------- Hidden admin page: /__xk9m2_admin__ (not index.html) ----------
  if (url === `/${SECRET}` || url === `/${SECRET}/`) {
    const programs = listPrograms();
    const links = programs.map(f => `<li><a href="/${SECRET}/edit?file=${encodeURIComponent(f)}">${htmlEscape(f)}</a> <a href="/p${f.replace('p','').replace('.txt','')}" target="_blank">view</a></li>`).join('');
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Program Editor</title><style>body{font-family:sans-serif;max-width:700px;margin:40px auto;padding:0 20px;}h1{font-size:20px;}ul{list-style:none;padding:0;}li{margin:8px 0;padding:8px;border:1px solid #ddd;}a{text-decoration:none;color:#0066cc;}a.view{color:#555;font-size:12px;margin-left:10px;}textarea{width:100%;height:320px;font-family:monospace;font-size:14px;padding:10px;box-sizing:border-box;}input[type=submit]{margin-top:10px;padding:8px 16px;cursor:pointer;} pre{background:#f4f4f4;padding:10px;border-radius:4px;overflow:auto;}</style></head><body><h1>Program Editor (hidden)</h1><p>Secret path: <code>/${SECRET}</code></p><ul>${links || '<li>No programs found.</li>'}</ul><p><a href="/${SECRET}/new">Create new</a></p></body></html>`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // ---------- Edit form: /__xk9m2_admin__/edit?file=p1.txt ----------
  if (url === `/${SECRET}/edit` && req.method === 'GET') {
    const file = query.file;
    if (!file || !/^p\d+\.txt$/.test(file)) {
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Invalid file parameter\n');
      return;
    }
    const data = readFileSafe(file) || '';
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Edit ${htmlEscape(file)}</title><style>body{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px;}h1{font-size:20px;}textarea{width:100%;height:400px;font-family:monospace;font-size:14px;padding:10px;box-sizing:border-box;}input[type=submit]{margin-top:10px;padding:8px 16px;cursor:pointer;} .back{margin-top:20px;display:inline-block;} pre{background:#f4f4f4;padding:10px;border-radius:4px;}</style></head><body><h1>Edit ${htmlEscape(file)}</h1><form method="POST" action="/${SECRET}/edit"><input type="hidden" name="file" value="${htmlEscape(file)}"><textarea name="content">${htmlEscape(data)}</textarea><br><input type="submit" value="Save"></form><p class="back"><a href="/${SECRET}">Back to list</a> | <a href="/${file.replace('.txt','')}" target="_blank">View raw</a></p></body></html>`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // ---------- Save edit: /__xk9m2_admin__/edit (POST) ----------
  if (url === `/${SECRET}/edit` && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const params = qs.parse(body);
      const file = params.file;
      const content = params.content !== undefined ? params.content : '';
      if (!file || !/^p\d+\.txt$/.test(file)) {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Invalid file\n');
        return;
      }
      if (writeFileSafe(file, content)) {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<h2>Saved ${htmlEscape(file)}</h2><p><a href="/${SECRET}/edit?file=${encodeURIComponent(file)}">Edit again</a> | <a href="/${SECRET}">Back to list</a> | <a href="/${file.replace('.txt','')}" target="_blank">View raw</a></p>`);
        console.log(`[${ip}] EDIT /p${file.replace('p','').replace('.txt','')} saved`);
      } else {
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        res.end('Forbidden\n');
      }
    });
    return;
  }

  // ---------- Create new: /__xk9m2_admin__/new ----------
  if (url === `/${SECRET}/new` && req.method === 'GET') {
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>New Program</title><style>body{font-family:sans-serif;max-width:600px;margin:40px auto;padding:0 20px;}input,textarea{width:100%;box-sizing:border-box;margin-bottom:10px;padding:8px;font-family:monospace;}input[type=submit]{cursor:pointer;width:auto;}</style></head><body><h1>Create New Program</h1><form method="POST" action="/${SECRET}/create"><input type="text" name="file" placeholder="e.g. p11.txt" required><textarea name="content" rows="10" placeholder="Enter program text..."></textarea><br><input type="submit" value="Create"></form><p><a href="/${SECRET}">Back to list</a></p></body></html>`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // ---------- Save new: /__xk9m2_admin__/create (POST) ----------
  if (url === `/${SECRET}/create` && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const params = qs.parse(body);
      const file = params.file || '';
      const content = params.content || '';
      if (!/^p\d+\.txt$/.test(file)) {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Filename must be like p11.txt\n');
        return;
      }
      const target = path.join(DIR, file);
      if (fs.existsSync(target)) {
        res.writeHead(409, { 'Content-Type': 'text/plain' });
        res.end('File already exists\n');
        return;
      }
      try {
        fs.writeFileSync(target, content, 'utf8');
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<h2>Created ${htmlEscape(file)}</h2><p><a href="/${SECRET}/edit?file=${encodeURIComponent(file)}">Edit it</a> | <a href="/${SECRET}">Back to list</a></p>`);
        console.log(`[${ip}] CREATE /${file}`);
      } catch (e) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Error creating file\n');
      }
    });
    return;
  }

  // ---------- 404 ----------
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found\n');
  console.log(`[${ip}] 404 ${req.url}`);
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getIP();
  console.log('========================================');
  console.log(` Node.js Web Server — port ${PORT}`);
  console.log(` Server:  http://${ip}:${PORT}`);
  console.log(` Local:   http://localhost:${PORT}`);
  console.log(` Hidden editor: http://${ip}:${PORT}/${SECRET}`);
  console.log(` Programs: /p1, /p2, ... /pn`);
  console.log(` Folder:   ${DIR}`);
  console.log(` Example:  curl -s http://${ip}:${PORT}/p1 | xclip -selection clipboard`);
  console.log('========================================');
});
