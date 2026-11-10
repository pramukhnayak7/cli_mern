import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const ProgServerApp());
}

class ProgServerApp extends StatelessWidget {
  const ProgServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prog Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.deepPurple),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Directory? _dir;
  bool _serverStarted = false;
  String _ip = '...';
  List<String> _files = [];
  String _selected = '';
  String _content = '';
  String _status = 'Starting server...';
  HttpServer? _server;

  static const String serverJsCode = '''const http = require('http');
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

const LOCAL_IPS = ['127.0.0.1', '::1', '::ffff:127.0.0.1', 'localhost'];

bool isLocal(String? ip) {
  if (ip == null) return false;
  return LOCAL_IPS.contains(ip) || ip.startsWith('127.');
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  const ip = req.socket.remoteAddress;

  // Phone-only access: 404 for any external browser
  if (!isLocal(ip)) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found\\n');
    console.log('[' + ip + '] 404 BLOCKED ' + url);
    return;
  }

  const m = url.match(/^\\/p(\\d+)$/);

  // Serve raw program text: /p1, /p2, ... (for curl)
  if (m && req.method === 'GET') {
    const file = path.join(DIR, 'p' + m[1] + '.txt');
    fs.readFile(file, 'utf8', (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Program ' + m[1] + ' not found\\n');
        console.log('[' + ip + '] 404 /p' + m[1]);
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(data);
      console.log('[' + ip + '] 200 /p' + m[1]);
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found\\n');
  console.log('[' + ip + '] 404 ' + req.url);
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getIP();
  console.log('========================================');
  console.log(' Node.js Web Server — port ' + PORT);
  console.log(' Server:  http://' + ip + ':' + PORT);
  console.log(' Local:   http://localhost:' + PORT);
  console.log(' Folder:  ' + DIR);
  console.log(' Example: curl -s http://' + ip + ':' + PORT + '/p1 | xclip -selection clipboard');
  console.log('========================================');
});
''';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _dir = await getApplicationDocumentsDirectory();
    await _ensureDefaults();
    _refreshFiles();
    await _startServer();
    _ip = await _getIP();
    if (!mounted) return;
    setState(() {
      _serverStarted = true;
      _status = 'Server running on http://$_ip:8050';
    });
  }

  Future<void> _ensureDefaults() async {
    for (int i = 1; i <= 5; i++) {
      final f = File('${_dir!.path}/p$i.txt');
      if (!await f.exists()) {
        await f.writeAsString('# Program $i\nprint("Hello from p$i")\n');
      }
    }
    final serverJs = File('${_dir!.path}/server.js');
    if (!await serverJs.exists()) {
      await serverJs.writeAsString(serverJsCode);
    }
  }

  Future<void> _refreshFiles() async {
    final ents = await _dir!.list().toList();
    final list = ents
        .whereType<File>()
        .where((e) => e.path.endsWith('.txt'))
        .map((e) => e.path.split('/').last)
        .toList();
    list.sort((a, b) {
      final ai = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final bi = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return ai.compareTo(bi);
    });
    if (!mounted) return;
    setState(() => _files = list);
  }

  Future<void> _startServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8050);
    _server!.listen((req) async {
      final path = req.uri.path;

      // Serve server.js file for download: /server.js
      if (path == '/server.js' && req.method == 'GET') {
        final f = File('${_dir!.path}/server.js');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found');
        }
        await req.response.close();
        return;
      }

      // Serve raw program text: /p1, /p2, ... (for curl)
      final m = RegExp(r'^/p(\d+)$').firstMatch(path);
      if (m != null && req.method == 'GET') {
        final f = File('${_dir!.path}/p${m.group(1)!}.txt');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found');
        }
        await req.response.close();
        return;
      }

      // Admin web page served by the app itself
      if ((path == '/' || path == '/admin') && req.method == 'GET') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_adminHtml());
        await req.response.close();
        return;
      }

      // API: list files
      if (path == '/api/files' && req.method == 'GET') {
        final ents = await _dir!.list().toList();
        final list = ents
            .whereType<File>()
            .where((e) => e.path.endsWith('.txt'))
            .map((e) => e.path.split('/').last)
            .toList();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(list));
        await req.response.close();
        return;
      }

      // API: get file
      if (path.startsWith('/api/get/') && req.method == 'GET') {
        final name = path.substring('/api/get/'.length);
        final f = File('${_dir!.path}/$name');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
        return;
      }

      // API: save file
      if (path == '/api/save' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final params = _parseQuery(body);
        final file = params['file'] ?? '';
        final content = params['content'] ?? '';
        if (_isValidFile(file)) {
          await File('${_dir!.path}/$file').writeAsString(content);
          req.response.write('OK');
        } else {
          req.response.statusCode = 400;
          req.response.write('Bad file');
        }
        await req.response.close();
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    });
  }

  bool _isValidFile(String name) => RegExp(r'^p\d+\.txt$').hasMatch(name);

  Map<String, String> _parseQuery(String body) {
    final map = <String, String>{};
    for (final part in body.split('&')) {
      final kv = part.split('=');
      if (kv.length == 2) {
        map[Uri.decodeComponent(kv[0])] = Uri.decodeComponent(kv[1]);
      }
    }
    return map;
  }

  Future<String> _getIP() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final i in interfaces) {
        for (final addr in i.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return 'unknown';
  }

  Future<void> _load(String file) async {
    final f = File('${_dir!.path}/$file');
    if (!mounted) return;
    setState(() {
      _selected = file;
      _content = f.existsSync() ? f.readAsStringSync() : '';
    });
  }

  Future<void> _save() async {
    if (_selected.isEmpty) return;
    await File('${_dir!.path}/$_selected').writeAsString(_content);
    await _refreshFiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prog Server')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.deepPurple.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Server: http://$_ip:8050',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Text(
                    'curl -s http://<PHONE_IP>:8050/server.js > server.js'),
                const Text(
                    'Then: node server.js'),
                Text(_status),
              ],
            ),
          ),
          Expanded(
            child: _files.isEmpty
                ? const Center(child: Text('No programs'))
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (_, i) {
                      final fname = _files[i];
                      return ListTile(
                        leading: const Icon(Icons.code),
                        title: Text(fname),
                        selected: _selected == fname,
                        onTap: () => _load(fname),
                      );
                    },
                  ),
          ),
          if (_selected.isNotEmpty)
            Container(
              height: 260,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_selected,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _selected = '';
                          _content = '';
                        }),
                      ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Edit program text...',
                      ),
                      onChanged: (v) => _content = v,
                      controller: TextEditingController(text: _content),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _refreshFiles,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rescan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final newName = 'p${(_files.length + 1)}.txt';
          File('${_dir!.path}/$newName').writeAsStringSync('# $newName\n');
          _refreshFiles();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _adminHtml() => '''
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Prog Editor</title></head><body>
<h2>Program Editor</h2>
<p><a href="/server.js">Download server.js</a></p>
<ul id="list"></ul>
<script>
fetch('/api/files').then(r=>r.json()).then(files=>{
  const ul=document.getElementById('list');
  files.forEach(function(name){
    const li=document.createElement('li');
    li.innerHTML='<a href="/p'+name.replace(".txt","")+'" target="_blank">'+name+'</a> ';
    const b=document.createElement('button'); b.textContent='Edit'; b.onclick=function(){
      fetch('/api/get/'+name).then(r=>r.text()).then(c=>{
        const nc=prompt('Edit '+name+':', c);
        if(nc!==null){
          fetch('/api/save',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'file='+encodeURIComponent(name)+'&content='+encodeURIComponent(nc)})
            .then(()=>location.reload());
        }
      });
    };
    li.appendChild(b);
    ul.appendChild(li);
  });
});
</script>
</body></html>
''';
}
