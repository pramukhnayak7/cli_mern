import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ProgEditorApp());
}

class ProgEditorApp extends StatelessWidget {
  const ProgEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Program Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
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
  // Default server URL — change this to your phone's IP
  final TextEditingController urlController = TextEditingController(
    text: 'http://192.168.1.5:8050',
  );

  List<String> programs = [];
  bool isLoading = false;
  String? error;
  String selectedContent = '';
  String selectedFile = '';

  Future<void> fetchPrograms() async {
    final base = urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    setState(() {
      isLoading = true;
      error = null;
      programs = [];
    });

    try {
      // Try p1..p20 to see which exist
      List<String> found = [];
      for (int i = 1; i <= 20; i++) {
        final res = await http.get(Uri.parse('$base/p$i')).timeout(
          const Duration(seconds: 4),
        );
        if (res.statusCode == 200) {
          found.add('p$i.txt');
        }
      }
      setState(() {
        programs = found;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Cannot reach server: $e';
        isLoading = false;
      });
    }
  }

  Future<void> loadContent(String file) async {
    final base = urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final name = file.replaceAll('.txt', '');
    setState(() {
      isLoading = true;
      error = null;
      selectedFile = file;
    });

    try {
      final res = await http.get(Uri.parse('$base/$name')).timeout(
        const Duration(seconds: 4),
      );
      if (res.statusCode == 200) {
        setState(() {
          selectedContent = res.body;
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'Server returned ${res.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error loading: $e';
        isLoading = false;
      });
    }
  }

  Future<void> saveContent() async {
    if (selectedFile.isEmpty) return;
    final base = urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final name = selectedFile.replaceAll('.txt', '');

    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$base/$name'),
        headers: {'Content-Type': 'text/plain'},
        body: selectedContent,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved!')),
          );
        }
      } else {
        setState(() {
          error = 'Save failed: ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Save error: $e';
      });
    }
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Program Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPrograms,
          ),
        ],
      ),
      body: Column(
        children: [
          // Server URL bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL (your phone IP:8050)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => fetchPrograms(),
            ),
          ),
          // Action row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Scan Programs'),
                    onPressed: isLoading ? null : fetchPrograms,
                  ),
                ),
                const SizedBox(width: 8),
                if (selectedFile.isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                      onPressed: isLoading ? null : saveContent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Error / loading
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red.shade50,
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          // Program list
          Expanded(
            child: programs.isEmpty && !isLoading && error == null
                ? const Center(
                    child: Text(
                      'Tap "Scan Programs" to load p1.txt, p2.txt, ...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: programs.length,
                    itemBuilder: (context, i) {
                      final file = programs[i];
                      final isSelected = selectedFile == file;
                      return ListTile(
                        leading: const Icon(Icons.code),
                        title: Text(file),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                        selected: isSelected,
                        onTap: () => loadContent(file),
                      );
                    },
                  ),
          ),
        ],
      ),
      // Editor bottom sheet area
      bottomSheet: selectedContent.isNotEmpty
          ? Container(
              height: 260,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedFile,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            selectedContent = '';
                            selectedFile = '';
                          });
                        },
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
                      onChanged: (val) => selectedContent = val,
                      controller: TextEditingController(text: selectedContent),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
