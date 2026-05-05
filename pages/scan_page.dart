import 'package:flutter/material.dart';

import '../ble/multi_ble_service.dart';
import 'all_devices_page.dart';
import 'saved_files_page.dart';

class ScanPage extends StatefulWidget {
  final MultiBleService ble;
  const ScanPage({super.key, required this.ble});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.ble.startScan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.ble.stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.ble.startScan();
    } else if (state == AppLifecycleState.paused) {
      widget.ble.stopScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("All Devices"),
        actions: [
          IconButton(
            tooltip: "Files",
            icon: const Icon(Icons.folder_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SavedFilesPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: AllDevicesPage(ble: widget.ble),
    );
  }
}
