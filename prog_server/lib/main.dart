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

function isCurl(req) {
  const ua = req.headers['user-agent'] || '';
  return /curl/i.test(ua);
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  const ip = req.socket.remoteAddress;

  // /server.js : curl ONLY (browsers get 404)
  if (url === '/server.js' && req.method === 'GET') {
    if (!isCurl(req)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\\n');
      console.log('[' + ip + '] 404 /server.js (browser blocked)');
      return;
    }
    const f = path.join(__dirname, 'server.js');
    if (fs.existsSync(f)) {
      res.writeHead(200, { 'Content-Type': 'application/javascript' });
      res.end(fs.readFileSync(f, 'utf8'));
      console.log('[' + ip + '] 200 /server.js (curl download)');
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\\n');
    }
    return;
  }

  // Serve raw program text: /p1, /p2, ...
  const m = url.match(/^\\/p(\\d+)\\$/);
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

  // Everything else: 404 (no browser pages, no editor)
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found\\n');
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
  console.log('   curl -s http://' + ip + ':' + PORT + '/server.js > server.js');
  console.log(' Programs: /p1, /p2, ... /pn');
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

  bool _isCurl(HttpRequest req) {
    final ua = req.headers.value('user-agent') ?? '';
    return RegExp(r'curl', caseSensitive: false).hasMatch(ua);
  }

  Future<void> _startServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8050);
    _server!.listen((req) async {
      final path = req.uri.path;

      // /server.js : curl ONLY (browsers get 404)
      if (path == '/server.js' && req.method == 'GET') {
        if (!_isCurl(req)) {
          req.response.headers.contentType = ContentType.text;
          req.response.write('Not found\\n');
          await req.response.close();
          return;
        }
        final f = File('${_dir!.path}/server.js');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found\\n');
        }
        await req.response.close();
        return;
      }

      // Serve raw program text: /p1, /p2, ...
      final m = RegExp(r'^/p(\d+)$').firstMatch(path);
      if (m != null && req.method == 'GET') {
        final f = File('${_dir!.path}/p${m.group(1)!}.txt');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('Program ${m.group(1)} not found\\n');
        }
        await req.response.close();
        return;
      }

      // Everything else: 404 (no browser pages, no editor)
      req.response.statusCode = 404;
      req.response.write('Not found\\n');
      await req.response.close();
    });
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
                const Text('Then: node server.js'),
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
                        onTap: () {},
                      );
                    },
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
}
