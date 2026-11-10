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
      theme: ThemeData(useMaterial3: true, seedColor: Colors.deepPurple),
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
      final m = RegExp(r'^/p(\d+)$').firstMatch(path);

      // ---------- Serve raw program text: /p1, /p2, ... (for curl) ----------
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

      // ---------- Admin web page served by the app itself ----------
      if ((path == '/' || path == '/admin') && req.method == 'GET') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_adminHtml());
        await req.response.close();
        return;
      }

      // ---------- API: list files ----------
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

      // ---------- API: get file ----------
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

      // ---------- API: save file ----------
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

  bool _isValidFile(String f) => RegExp(r'^p\d+\.txt$').hasMatch(f);

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
                    'curl -s http://<PHONE_IP>:8050/p1 | xclip -selection clipboard'),
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
                      final f = _files[i];
                      return ListTile(
                        leading: const Icon(Icons.code),
                        title: Text(f),
                        selected: _selected == f,
                        onTap: () => _load(f),
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
          _dir!.file(newName).writeAsStringSync('# $newName\n');
          _refreshFiles();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _adminHtml() => '''
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Prog Editor</title></head><body>
<h2>Program Editor</h2>
<ul id="list"></ul>
<script>
fetch('/api/files').then(r=>r.json()).then(files=>{
  const ul=document.getElementById('list');
  files.forEach(f=>{
    const li=document.createElement('li');
    li.innerHTML='<a href="/p${f.replace(".txt","")}" target="_blank">'+f+'</a> ';
    const b=document.createElement('button'); b.textContent='Edit'; b.onclick=()=>{
      fetch('/api/get/'+f).then(r=>r.text()).then(c=>{
        const nc=prompt('Edit '+f+':', c);
        if(nc!==null){
          fetch('/api/save',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'file='+encodeURIComponent(f)+'&content='+encodeURIComponent(nc)})
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
