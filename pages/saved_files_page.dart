import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SavedFilesPage extends StatefulWidget {
  const SavedFilesPage({super.key});

  @override
  State<SavedFilesPage> createState() => _SavedFilesPageState();
}

class _SavedFilesPageState extends State<SavedFilesPage> {
  late Future<List<File>> _filesFuture;

  static const String _boxFileRequestUrl =
      'https://tufts.app.box.com/f/afa8747a1e7d445b94b00931fe139ac0';

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

  Future<void> _shareFile(File file) async {
    final box = context.findRenderObject() as RenderBox?;

    if (box != null) {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "CSV file",
        sharePositionOrigin:
            box.localToGlobal(Offset.zero) & box.size,
      );
    } else {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "CSV file",
      );
    }
  }

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
      await _refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File deleted")),
      );
    }
  }

  Future<void> _openBoxUploadLink() async {
    final uri = Uri.parse(_boxFileRequestUrl);

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok) {
      throw Exception('Could not open Box upload link');
    }
  }

  Future<void> _showBoxInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Upload to Box"),
        content: const Text(
          "1. Tap 'Choose File'\n"
          "2. Select your saved CSV file\n"
          "3. Tap Upload",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _openBoxUploadLink();
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  // ---------- FILE PARSING ----------

  SavedCsvInfo _parseFile(File file) {
    final name = file.path.split('/').last.replaceAll('.csv', '');
    final modified = file.statSync().modified;

    final match = RegExp(
      r'^(.*?)_(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:\.\d+)?)'
      r'(?:_(recent|all))?$',
    ).firstMatch(name);

    if (match == null) {
      return SavedCsvInfo(
        file: file,
        bodyPart: _pretty(name),
        timestamp: modified,
        suffix: null,
      );
    }

    final rawBody = match.group(1)!;
    final rawTime = match.group(2);
    final suffix = match.group(3);

    DateTime timestamp = modified;

    if (rawTime != null) {
      try {
        final fixed = rawTime.replaceFirstMapped(
          RegExp(r'T(\d{2})-(\d{2})-(\d{2})'),
          (m) => 'T${m.group(1)}:${m.group(2)}:${m.group(3)}',
        );
        timestamp = DateTime.parse(fixed);
      } catch (_) {}
    }

    return SavedCsvInfo(
      file: file,
      bodyPart: _pretty(rawBody),
      timestamp: timestamp,
      suffix: suffix,
    );
  }

  String _pretty(String raw) {
    return raw
        .split('_')
        .map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatDate(DateTime dt) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved CSV Files"),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _showBoxInstructions,
          ),
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

          return Column(
            children: [
              // 🔥 INSTRUCTION BANNER
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.blue.withOpacity(0.1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "How to Send Data:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.ios_share, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text("1. Tap save → Save to Files"),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.cloud_upload, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text("2. Tap upload → Upload to Box"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: files.isEmpty
                    ? const Center(child: Text("No saved CSV files yet."))
                    : ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (_, i) {
                          final info = _parseFile(files[i]);

                          return ListTile(
                            title: Text(
                              info.bodyPart,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              "${_formatDate(info.timestamp)} · ${_formatTime(info.timestamp)}",
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.ios_share),
                                  onPressed: () =>
                                      _shareFile(info.file),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _deleteFile(info.file),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SavedCsvInfo {
  final File file;
  final String bodyPart;
  final DateTime timestamp;
  final String? suffix;

  SavedCsvInfo({
    required this.file,
    required this.bodyPart,
    required this.timestamp,
    required this.suffix,
  });
}
