import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Directory? _dir;
  bool _serverStarted = false;
  String _ip = '...';
  List<String> _files = [];
  String _status = 'Starting server...';
  HttpServer? _server;

  final TextEditingController _repoController = TextEditingController(text: '');
  bool _isSyncing = false;
  String _syncMsg = '';
  String _ownerRepo = '';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

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

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  // /p1 serves server.js (download with: curl -s http://IP:8050/p1 > server.js)
  if (url === '/p1' && req.method === 'GET') {
    const f = path.join(__dirname, 'server.js');
    if (fs.existsSync(f)) {
      res.writeHead(200, { 'Content-Type': 'application/javascript' });
      res.end(fs.readFileSync(f, 'utf8'));
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('server.js not found\n');
    }
    return;
  }

  // /p2, /p3, ... /pn serve program text files
  const m = url.match(/^\/p(\d+)$/);
  if (m && req.method === 'GET') {
    const num = parseInt(m[1], 10);
    if (num === 1) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
      return;
    }
    const file = path.join(DIR, 'p' + num + '.txt');
    fs.readFile(file, 'utf8', (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Program ' + num + ' not found\n');
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(data);
    });
    return;
  }

  // Everything else: 404
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found\n');
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getIP();
  console.log('========================================');
  console.log(' Node.js Web Server — port ' + PORT);
  console.log(' Server:  http://' + ip + ':' + PORT);
  console.log(' Local:   http://localhost:' + PORT);
  console.log(' Download: curl -s http://' + ip + ':' + PORT + '/p1 > server.js');
  console.log(' Programs: /p2, /p3, ... /pn');
  console.log('========================================');
});
''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep running in background
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notifications.initialize(initializationSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'prog_server_channel',
      'Prog Server',
      description: 'Prog Server is running',
      importance: Importance.low,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _notifications.show(
      0,
      'Prog Server',
      'Server running on port 8050',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'prog_server_channel',
          'Prog Server',
          channelDescription: 'Prog Server background service',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
        ),
      ),
    );
  }

  Future<void> _init() async {
    await WakelockPlus.enable();

    // Start foreground service so server stays alive in background like Termux
    const MethodChannel channel = MethodChannel('prog_server/background');
    try {
      await channel.invokeMethod('startForegroundService');
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
    }

    _dir = await getApplicationDocumentsDirectory();
    await _ensureDefaults();
    _refreshFiles();
    await _startServer();
    await _initNotifications();
    _ip = await _getIP();
    if (!mounted) return;
    setState(() {
      _serverStarted = true;
      _status = 'Server running on http://$_ip:8050';
    });
  }

  Future<void> _ensureDefaults() async {
    for (int i = 2; i <= 10; i++) {
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
    if (_dir == null) return;
    final ents = await _dir!.list().toList();
    final list = ents
        .whereType<File>()
        .where((e) => e.path.endsWith('.txt'))
        .map((e) => p.basename(e.path))
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

      // /p1 serves server.js
      if (path == '/p1' && req.method == 'GET') {
        final f = File('${_dir!.path}/server.js');
        if (await f.exists()) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(await f.readAsString());
        } else {
          req.response.statusCode = 404;
          req.response.write('server.js not found\n');
        }
        await req.response.close();
        return;
      }

      // /p2, /p3, ... serve program text
      final m = RegExp(r'^\/p(\d+)$').firstMatch(path);
      if (m != null && req.method == 'GET') {
        final num = int.tryParse(m.group(1)!);
        if (num == null || num == 1) {
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

      // Everything else: 404
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
      setState(() {
        _syncMsg = 'Invalid GitHub URL';
        _ownerRepo = '';
      });
      return;
    }

    setState(() {
      _ownerRepo = ownerRepo ?? '';
      _isSyncing = true;
      _syncMsg = 'Fetching ${ownerRepo ?? ''}...';
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

      if (res.statusCode == 404) {
        setState(() {
          _isSyncing = false;
          _syncMsg =
              '404: Repo "$ownerRepo" not found (check URL or make it public)';
        });
        return;
      }
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
          await File('${_dir!.path}/$name').writeAsString(fileRes.body);
          count++;
        }
      }

      await _refreshFiles();

      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncMsg = 'Synced $count .txt files from ${ownerRepo ?? ''}';
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
                if (_syncMsg.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Repo: $_ownerRepo',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_syncMsg,
                        style: TextStyle(
                          color: _syncMsg.startsWith('Synced')
                              ? Colors.green
                          : _syncMsg.startsWith('404')
                              ? Colors.orange
                          : Colors.red,
                          fontSize: 12,
                        )),
                  ),
                ],
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
                        subtitle: const Text('Tap to read on phone'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ViewPage(
                                fileName: fname,
                                dirPath: _dir!.path,
                              ),
                            ),
                          );
                        },
                        trailing: const Icon(Icons.chevron_right),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final newName = 'p${(_files.length + 1)}.txt';
          await File('${_dir!.path}/$newName').writeAsString('# $newName\n');
          _refreshFiles();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ViewPage extends StatefulWidget {
  final String fileName;
  final String dirPath;

  const ViewPage({super.key, required this.fileName, required this.dirPath});

  @override
  State<ViewPage> createState() => _ViewPageState();
}

class _ViewPageState extends State<ViewPage> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = File('${widget.dirPath}/${widget.fileName}');
    if (await f.exists()) {
      setState(() {
        _content = f.readAsStringSync();
        _loading = false;
      });
    } else {
      setState(() {
        _content = 'File not found';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Stored in: ${widget.dirPath}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
