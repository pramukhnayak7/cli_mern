import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  // GitHub sync
  final TextEditingController _repoController = TextEditingController(
    text: 'https://github.com/PranavBShenoy/Mern',
  );
  bool _isSyncing = false;
  String _syncMsg = '';

  static const String serverJsCode = r'''const http = require('http');
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
      // /p1 is reserved for server.js download above
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
    for (int i = 2; i <= 5; i++) {
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

      // /p1 : curl ONLY — serves this Node.js server code
      if (path == '/p1' && req.method == 'GET') {
        if (!_isCurl(req)) {
          req.response.headers.contentType = ContentType.text;
          req.response.write('Not found\n');
          await req.response.close();
          return;
        }
        final f = File('${_dir!.path}/server.js');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found\n');
        }
        await req.response.close();
        return;
      }

      // Serve raw program text: /p2, /p3, ...
      final m = RegExp(r'^\/p(\d+)$').firstMatch(path);
      if (m != null && req.method == 'GET') {
        final num = int.tryParse(m.group(1)!);
        if (num == 1) {
          req.response.statusCode = 404;
          req.response.write('Not found\n');
          await req.response.close();
          return;
        }
        final f = File('${_dir!.path}/p$num.txt');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('Program $num not found\n');
        }
        await req.response.close();
        return;
      }

      // Everything else: 404 (no browser pages, no editor)
      req.response.statusCode = 404;
      req.response.write('Not found\n');
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

  // ---------- GitHub Sync ----------
  Future<void> _syncFromGitHub() async {
    final rawUrl = _repoController.text.trim();
    if (rawUrl.isEmpty) return;

    String? ownerRepo;
    try {
      final uri = Uri.parse(rawUrl);
      final parts = uri.pathSegments;
      if (parts.length >= 2) {
        ownerRepo = '${parts[0]}/${parts[1]}';
      }
    } catch (_) {}
    if (ownerRepo == null) {
      setState(() => _syncMsg = 'Invalid GitHub URL');
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncMsg = 'Fetching $ownerRepo...';
    });

    try {
      final apiUrl = Uri.https('api.github.com', '/repos/$ownerRepo/contents');
      final res = await http.get(
        apiUrl,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'ProgServer-Flutter-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        setState(() {
          _isSyncing = false;
          _syncMsg = 'GitHub API ${res.statusCode}: ${res.body}';
        });
        return;
      }

      final List<dynamic> items = jsonDecode(res.body);
      int count = 0;

      for (final item in items) {
        final name = item['name'] as String?;
        final type = item['type'] as String?;
        final downloadUrl = item['download_url'] as String?;
        if (type != 'file' || name == null || downloadUrl == null) continue;

        if (!name.endsWith('.txt')) continue;

        final fileRes = await http.get(
          Uri.parse(downloadUrl),
        ).timeout(const Duration(seconds: 10));

        if (fileRes.statusCode == 200) {
          final target = File('${_dir!.path}/$name');
          await target.writeAsString(fileRes.body);
          count++;
        }
      }

      await _refreshFiles();

      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncMsg = 'Synced $count .txt files from $ownerRepo';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncMsg = 'Sync error: $e';
      });
    }
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
                    'curl -s http://<PHONE_IP>:8050/p1 > server.js'),
                const Text('Then: node server.js'),
                Text(_status),
              ],
            ),
          ),
          // GitHub Sync section
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sync from GitHub',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _repoController,
                        decoration: const InputDecoration(
                          hintText: 'https://github.com/owner/repo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _syncFromGitHub,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('Sync'),
                    ),
                  ],
                ),
                if (_syncMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_syncMsg,
                        style: TextStyle(
                          color: _syncMsg.startsWith('Synced')
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12,
                        )),
                  ),
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
