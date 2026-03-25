import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../ble/ble_service.dart';
import 'dashboard_page.dart';

class ScanPage extends StatefulWidget {
  final BleService ble;
  const ScanPage({super.key, required this.ble});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  bool busy = false;

  // Search state
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });

    widget.ble.startScan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
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

  Future<void> _connect(DiscoveredDevice d) async {
    setState(() => busy = true);
    try {
      await widget.ble.connectAndSyncTime(d.id);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardPage(
            ble: widget.ble,
            deviceName: d.name,
            deviceId: d.id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connect/time sync failed: $e")),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Optional: de-dup devices by id (nice if your stream emits repeats)
  List<DiscoveredDevice> _dedupeById(List<DiscoveredDevice> input) {
    final map = <String, DiscoveredDevice>{};
    for (final d in input) {
      map[d.id] = d;
    }
    return map.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan for devices")),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Search by name or id…",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Devices list
          Expanded(
            child: StreamBuilder<List<DiscoveredDevice>>(
              stream: widget.ble.devicesStream,
              builder: (context, snap) {
                final raw = snap.data ?? const <DiscoveredDevice>[];
                final devices = _dedupeById(raw);

                final filtered = (_query.isEmpty)
                    ? devices
                    : devices.where((d) {
                        final name = d.name.toLowerCase();
                        final id = d.id.toLowerCase();
                        return name.contains(_query) || id.contains(_query);
                      }).toList();

                return RefreshIndicator(
                  onRefresh: () async {
                    widget.ble.stopScan();
                    await Future.delayed(const Duration(milliseconds: 150));
                    widget.ble.startScan();
                  },
                  // RefreshIndicator needs a scrollable child even when empty
                  child: filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            if (devices.isEmpty && _query.isEmpty) ...const [
                              Center(child: CircularProgressIndicator()),
                              SizedBox(height: 12),
                              Center(child: Text("Scanning… pull to refresh")),
                            ] else ...[
                              const Center(child: Text("No matching devices.")),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  _query.isEmpty
                                      ? "Pull to refresh to rescan."
                                      : "Try a different search.",
                                ),
                              ),
                            ],
                          ],
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            final name = d.name.isNotEmpty ? d.name : "(unnamed)";

                            return ListTile(
                            title: Text(name),
                            subtitle: Text(d.id),
                            onTap: busy ? null : () => _connect(d),   // ✅ tap anywhere
                            trailing: ElevatedButton(
                              onPressed: busy ? null : () => _connect(d),
                              child: const Text("Connect"),
                            ),
                          );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}