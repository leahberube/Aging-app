import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SavedFilesPage extends StatefulWidget {
  const SavedFilesPage({super.key});

  @override
  State<SavedFilesPage> createState() => _SavedFilesPageState();
}

class _SavedFilesPageState extends State<SavedFilesPage> {
  late Future<List<File>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<File>> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.csv'))
        .toList();

    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    return files;
  }

  Future<void> _refresh() async {
    setState(() {
      _filesFuture = _loadFiles();
    });
  }

  // 🔥 SAME SHARE BEHAVIOR AS DASHBOARD
  Future<void> _shareFile(File file) async {
    final box = context.findRenderObject() as RenderBox?;

    if (box != null) {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "CSV file",
        sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
      );
    } else {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "CSV file",
      );
    }
  }

  // 🔒 PASSWORD DELETE (same as NAND)
  Future<void> _deleteFile(File file) async {
    const correctPin = '2468';
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete File"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter passcode to delete this file."),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Passcode",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, controller.text == correctPin);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    controller.dispose();

    if (confirmed == true) {
      await file.delete();
      _refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File deleted")),
      );
    } else if (confirmed == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Incorrect passcode")),
      );
    }
  }

  String _fileName(String path) => path.split('/').last;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved CSV Files"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final files = snapshot.data!;

          if (files.isEmpty) {
            return const Center(child: Text("No saved CSV files yet."));
          }

          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final file = files[i];

              return ListTile(
                title: Text(_fileName(file.path)),
                subtitle: Text(file.path),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () => _shareFile(file),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteFile(file),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}