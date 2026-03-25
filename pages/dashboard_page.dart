import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ble/ble_service.dart';
import '../ble/notification_service.dart';
import 'calibration_page.dart';
import 'saved_files_page.dart';

String _latestTimestampStatus = "unknown";

class DashboardPage extends StatefulWidget {
  final BleService ble;
  final String deviceName;
  final String deviceId;

  const DashboardPage({
    super.key,
    required this.ble,
    required this.deviceName,
    required this.deviceId,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final List<String> _logs = [];
  final List<String> _currentBurstLogs = [];
  final ScrollController _scrollCtrl = ScrollController();

  StreamSubscription<String>? _logSub;
  StreamSubscription<int?>? _battSub;
  StreamSubscription<bool?>? _chgSub;

  int? _batteryPercent;
  bool? _isCharging;

  bool _isAutoSavingCsv = false;
  bool _burstInProgress = false;

  @override
  void initState() {
    super.initState();

    NotificationService.scheduleThreeDailyNotifications();

    _logSub = widget.ble.logStream.listen((line) {
      if (!mounted) return;
      _handleIncomingLogLine(line);
    });

    _battSub = widget.ble.batteryPercentStream.listen((p) {
      if (!mounted) return;
      setState(() => _batteryPercent = p);
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _batteryPercent = null);
    });

    _chgSub = widget.ble.chargingStream.listen((c) {
      if (!mounted) return;
      setState(() => _isCharging = c);
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _isCharging = null);
    });

    widget.ble.log("Dashboard opened for ${widget.deviceId}");
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _battSub?.cancel();
    _chgSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _chargeText() {
    final batt = (_batteryPercent == null) ? "--%" : "${_batteryPercent}%";
    if (_isCharging == true) return "Charge: $batt ⚡";
    return "Charge: $batt";
  }

  void _handleIncomingLogLine(String line) {
    final s = line.trim().toLowerCase();

    // Always keep full terminal history
    _logs.add(line);

    // Start of a BLE burst from firmware
    if (s == "# burst recent start" || s == "# burst all start") {
      _burstInProgress = true;
      _currentBurstLogs.clear();
      _currentBurstLogs.add(line);
    } else if (_burstInProgress) {
      _currentBurstLogs.add(line);
    }

    // End of a BLE burst from firmware
    if (s == "# burst recent end" || s == "# burst all end") {
      _burstInProgress = false;
      _autoSaveCsvAfterBurst();
    }

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }


  String _buildCsvFromLogList(List<String> sourceLogs) {
    final lines = <String>[];
    lines.add("date,time,impedance_ohm,timestamp_status");

    for (final raw in sourceLogs) {
      final s = raw.trim();
      if (s.isEmpty) continue;

      final lower = s.toLowerCase();

      // Ignore headers / comments / markers
      if (lower == "time,impedance_ohm" ||
          lower == "unix_s,impedance_ohm" ||
          lower == "unix_s,impedance_ohm,time_status" ||
          lower == "date,time,impedance_ohm" ||
          lower == "date,time,impedance_ohm,timestamp_status" ||
          s.startsWith('#')) {
        continue;
      }

      // 1) New firmware format: unix_s,impedance,time_status
      final unixSStatusMatch = RegExp(
        r'^(\d+),(-?\d+(?:\.\d+)?),([012])$',
      ).firstMatch(s);

      if (unixSStatusMatch != null) {
        final unixS = int.parse(unixSStatusMatch.group(1)!);
        final impedance = unixSStatusMatch.group(2)!;
        final statusNum = int.parse(unixSStatusMatch.group(3)!);

        String status;
        switch (statusNum) {
          case 1:
            status = "known";
            break;
          case 2:
            status = "estimated";
            break;
          default:
            status = "unknown";
        }

        final dt = DateTime.fromMillisecondsSinceEpoch(
          unixS * 1000,
          isUtc: true,
        ).toLocal();

        final dateStr =
            "${dt.year.toString().padLeft(4, '0')}-"
            "${dt.month.toString().padLeft(2, '0')}-"
            "${dt.day.toString().padLeft(2, '0')}";

        final timeStr =
            "${dt.hour.toString().padLeft(2, '0')}:"
            "${dt.minute.toString().padLeft(2, '0')}:"
            "${dt.second.toString().padLeft(2, '0')}";

        lines.add("$dateStr,$timeStr,$impedance,$status");
        continue;
      }

      // 2) Old debug format: unix_ms=... Z=...
      final msMatch = RegExp(
        r'unix_ms=(\d+)\s+Z=(-?\d+(?:\.\d+)?)',
      ).firstMatch(s);

      if (msMatch != null) {
        final unixMs = int.parse(msMatch.group(1)!);
        final impedance = msMatch.group(2)!;

        final dt = DateTime.fromMillisecondsSinceEpoch(
          unixMs,
          isUtc: true,
        ).toLocal();

        final dateStr =
            "${dt.year.toString().padLeft(4, '0')}-"
            "${dt.month.toString().padLeft(2, '0')}-"
            "${dt.day.toString().padLeft(2, '0')}";

        final timeStr =
            "${dt.hour.toString().padLeft(2, '0')}:"
            "${dt.minute.toString().padLeft(2, '0')}:"
            "${dt.second.toString().padLeft(2, '0')}";

        lines.add("$dateStr,$timeStr,$impedance,unknown");
        continue;
      }

      // 3) Older format: unix_s,impedance
      final unixSMatch = RegExp(
        r'^(\d+),(-?\d+(?:\.\d+)?)$',
      ).firstMatch(s);

      if (unixSMatch != null) {
        final unixS = int.parse(unixSMatch.group(1)!);
        final impedance = unixSMatch.group(2)!;

        final dt = DateTime.fromMillisecondsSinceEpoch(
          unixS * 1000,
          isUtc: true,
        ).toLocal();

        final dateStr =
            "${dt.year.toString().padLeft(4, '0')}-"
            "${dt.month.toString().padLeft(2, '0')}-"
            "${dt.day.toString().padLeft(2, '0')}";

        final timeStr =
            "${dt.hour.toString().padLeft(2, '0')}:"
            "${dt.minute.toString().padLeft(2, '0')}:"
            "${dt.second.toString().padLeft(2, '0')}";

        lines.add("$dateStr,$timeStr,$impedance,unknown");
        continue;
      }

      // 4) Already formatted: date,time,impedance
      final datedMatch = RegExp(
        r'^(\d{4}-\d{2}-\d{2}),(\d{2}:\d{2}:\d{2}),(-?\d+(?:\.\d+)?)$',
      ).firstMatch(s);

      if (datedMatch != null) {
        final dateStr = datedMatch.group(1)!;
        final timeStr = datedMatch.group(2)!;
        final impedance = datedMatch.group(3)!;

        lines.add("$dateStr,$timeStr,$impedance,unknown");
        continue;
      }

      // 5) Already formatted: date,time,impedance,status
      final datedStatusMatch = RegExp(
        r'^(\d{4}-\d{2}-\d{2}),(\d{2}:\d{2}:\d{2}),(-?\d+(?:\.\d+)?),(known|unknown|estimated)$',
      ).firstMatch(s);

      if (datedStatusMatch != null) {
        final dateStr = datedStatusMatch.group(1)!;
        final timeStr = datedStatusMatch.group(2)!;
        final impedance = datedStatusMatch.group(3)!;
        final status = datedStatusMatch.group(4)!;

        lines.add("$dateStr,$timeStr,$impedance,$status");
        continue;
      }
    }

    if (lines.length == 1) return "";
    return "${lines.join("\n")}\n";
  }

  String _buildCsvFromLogs() => _buildCsvFromLogList(_logs);

  String _buildCsvFromCurrentBurst() => _buildCsvFromLogList(_currentBurstLogs);

  Future<void> _saveCsv({
    bool showShareSheet = true,
    bool burstOnly = false,
  }) async {
    final csv = burstOnly ? _buildCsvFromCurrentBurst() : _buildCsvFromLogs();

    if (csv.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No CSV data to save yet.")),
      );
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final suffix = burstOnly ? "_burst" : "";
    final filename = "${widget.deviceName}_${ts}$suffix.csv";
    final file = File("${dir.path}/$filename");

    await file.writeAsString(csv);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved: $filename")),
    );

    if (!showShareSheet) return;

    final box = context.findRenderObject() as RenderBox?;

    if (box != null) {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "CSV from ${widget.deviceName}",
        sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
      );
    } else {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "CSV from ${widget.deviceName}",
      );
    }
  }

  Future<void> _autoSaveCsvAfterBurst() async {
    if (_isAutoSavingCsv) return;
    _isAutoSavingCsv = true;

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await _saveCsv(showShareSheet: false, burstOnly: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("CSV auto-saved after transmit.")),
      );
    } finally {
      _isAutoSavingCsv = false;
    }
  }

  Future<void> _showEraseDialog() async {
    if (!widget.ble.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device not connected")),
      );
      return;
    }

    final TextEditingController pinController = TextEditingController();
    const String correctPin = '2468';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Erase NAND"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter passcode to erase all stored NAND data."),
              const SizedBox(height: 12),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final ok = pinController.text.trim() == correctPin;
                Navigator.pop(context, ok);
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );

    pinController.dispose();

    if (!mounted) return;

    if (confirmed == true) {
      await _sendEraseCommand();
    } else if (confirmed == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Incorrect passcode")),
      );
    }
  }

  Future<void> _sendEraseCommand() async {
    try {
      widget.ble.log("Erase NAND pressed");
      await widget.ble.eraseNand(widget.deviceId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erase command sent")),
      );
    } catch (e) {
      if (!mounted) return;
      widget.ble.log("Erase failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erase failed: $e")),
      );
    }
  }

  Future<void> _showTransmitDialog() async {
    if (!widget.ble.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device not connected")),
      );
      return;
    }

    final String? choice = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Transmit Data"),
          content: const Text("Choose what data to transmit."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("Cancel"),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, "recent"),
              child: const Text("Recent Data"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, "all"),
              child: const Text("All Data"),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;

    try {
      if (choice == "all") {
        widget.ble.log("Transmit all pressed");
        await widget.ble.startTransmit(widget.deviceId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transmit all started")),
        );
      } else if (choice == "recent") {
        widget.ble.log("Transmit recent pressed");
        await widget.ble.startTransmitRecent(widget.deviceId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transmit recent started")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      widget.ble.log("Transmit failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Transmit failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = widget.ble;
    final connected = ble.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text("Dashboard: ${widget.deviceName}"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(connected ? "Connected" : "Not connected"),
                const SizedBox(width: 8),
                StreamBuilder<int?>(
                  stream: ble.rssiStream,
                  builder: (context, snap) {
                    final rssi = snap.data;
                    return Text(rssi == null ? "(-- dBm)" : "($rssi dBm)");
                  },
                ),
                const SizedBox(width: 12),
                Text(_chargeText()),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: connected
                      ? null
                      : () async {
                          try {
                            ble.log("Reconnect + time sync requested");
                            await ble.connectAndSyncTime(widget.deviceId);

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Reconnected + time synced"),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ble.log("Reconnect failed: $e");
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Reconnect failed: $e"),
                              ),
                            );
                          }
                        },
                  child: const Text("Reconnect + Sync Time"),
                ),
                ElevatedButton(
                  onPressed: connected
                      ? () {
                          ble.log("Calibrate pressed");
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CalibratePage(
                                ble: ble,
                                deviceId: widget.deviceId,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: const Text("Calibrate"),
                ),
                ElevatedButton(
                  onPressed: connected ? _showTransmitDialog : null,
                  child: const Text("Transmit"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: connected ? _showEraseDialog : null,
                  child: const Text("Erase NAND"),
                ),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      ble.log("Save as CSV pressed");
                      await _saveCsv();
                    } catch (e) {
                      if (!mounted) return;
                      ble.log("Save CSV failed: $e");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Save failed: $e")),
                      );
                    }
                  },
                  child: const Text("Save as CSV"),
                ),
                OutlinedButton(
                  onPressed: () async {
                    ble.log("Disconnect pressed");
                    await ble.disconnect();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Disconnect"),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SavedFilesPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.folder),
                  label: const Text('Files'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Terminal",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _logs.isEmpty
                          ? const Text("No logs yet.")
                          : ListView.builder(
                              controller: _scrollCtrl,
                              itemCount: _logs.length,
                              itemBuilder: (_, i) => Text(
                                _logs[i],
                                style: const TextStyle(
                                  fontFamily: "monospace",
                                  fontSize: 12,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _logs.clear()),
                          child: const Text("Clear"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}