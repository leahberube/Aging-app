import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ble/ble_service.dart';
import '../ble/notification_service.dart';
import 'calibration_page.dart';
import 'saved_files_page.dart';

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

  String? _lastSavedKey;
  DateTime? _lastSavedAt;

  StreamSubscription<String>? _logSub;
  StreamSubscription<int?>? _battSub;
  StreamSubscription<bool?>? _chgSub;

  Timer? _burstCloseTimer;

  int? _batteryPercent;
  bool? _isCharging;

  bool _burstInProgress = false;
  bool _isAutoSavingCsv = false;
  bool _burstSaveTriggered = false;

  String? _currentTransmitType; // "recent" or "all"

  @override
  void initState() {
    super.initState();

    NotificationService.scheduleThreeDailyNotifications();

    _logSub = widget.ble.logStream.listen((line) {
      if (!mounted) return;

      final s = line.trim().toLowerCase();

      final isRelevant =
          s == "# burst recent start" ||
          s == "# burst recent end" ||
          s == "# burst all start" ||
          s == "# burst all end" ||
          RegExp(r'^(\d+),(-?\d+(?:\.\d+)?)(,[012])?$').hasMatch(line.trim()) ||
          RegExp(
            r'^(\d{4}-\d{2}-\d{2}),(\d{2}:\d{2}:\d{2}),(-?\d+(?:\.\d+)?)(,(known|unknown|estimated))?$',
          ).hasMatch(line.trim()) ||
          RegExp(r'unix_ms=\d+\s+z=-?\d+(?:\.\d+)?', caseSensitive: false)
              .hasMatch(line.trim());

      if (!isRelevant) {
        _logs.add(line);
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
        return;
      }

      _handleIncomingLogLine(line);
    });

    _battSub = widget.ble.batteryPercentStream.listen(
      (p) {
        if (!mounted) return;
        setState(() => _batteryPercent = p);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _batteryPercent = null);
      },
    );

    _chgSub = widget.ble.chargingStream.listen(
      (c) {
        if (!mounted) return;
        setState(() => _isCharging = c);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isCharging = null);
      },
    );

    widget.ble.log("Dashboard opened for ${widget.deviceId}");
  }

  @override
  void dispose() {
    _burstCloseTimer?.cancel();
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
    final trimmed = line.trim();
    final s = trimmed.toLowerCase();

    _logs.add(line);

    final isBurstRecentStart = s == "# burst recent start";
    final isBurstAllStart = s == "# burst all start";
    final isBurstRecentEnd = s == "# burst recent end";
    final isBurstAllEnd = s == "# burst all end";

    final isBurstStart = isBurstRecentStart || isBurstAllStart;
    final isBurstEnd = isBurstRecentEnd || isBurstAllEnd;

    final isDataLine =
        RegExp(r'^(\d+),(-?\d+(?:\.\d+)?)(,[012])?$').hasMatch(trimmed) ||
        RegExp(
          r'^(\d{4}-\d{2}-\d{2}),(\d{2}:\d{2}:\d{2}),(-?\d+(?:\.\d+)?)(,(known|unknown|estimated))?$',
        ).hasMatch(trimmed) ||
        RegExp(r'unix_ms=\d+\s+Z=-?\d+(?:\.\d+)?', caseSensitive: false)
            .hasMatch(trimmed);

    if (isBurstStart) {
      final newType = isBurstRecentStart ? "recent" : "all";

      if (_burstInProgress && _currentTransmitType == newType) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
        return;
      }

      _burstCloseTimer?.cancel();
      _burstInProgress = true;
      _burstSaveTriggered = false;
      _currentTransmitType = newType;
      _currentBurstLogs
        ..clear()
        ..add(trimmed);
    } else if (_burstInProgress) {
      if (isDataLine || isBurstEnd) {
        if (_currentBurstLogs.isEmpty || _currentBurstLogs.last != trimmed) {
          _currentBurstLogs.add(trimmed);
        }
      }
    }

    if (isBurstEnd) {
      final endType = isBurstRecentEnd ? "recent" : "all";

      if (!_burstInProgress || _currentTransmitType != endType) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
        return;
      }

      if (_burstSaveTriggered) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
        return;
      }

      _burstInProgress = false;
      _burstSaveTriggered = true;

      final burstSnapshot = List<String>.from(_currentBurstLogs);
      final transmitTypeSnapshot = _currentTransmitType;

      _burstCloseTimer?.cancel();
      _burstCloseTimer = Timer(const Duration(milliseconds: 300), () async {
        final csv = _buildCsvFromLogList(burstSnapshot);

        if (csv.trim().isEmpty) {
          _isAutoSavingCsv = false;
          _currentTransmitType = null;
          return;
        }

        await _autoSaveCsvAfterBurst(
          burstLogs: burstSnapshot,
          transmitType: transmitTypeSnapshot,
        );
      });
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

      if (lower == "time,impedance_ohm" ||
          lower == "unix_s,impedance_ohm" ||
          lower == "unix_s,impedance_ohm,time_status" ||
          lower == "date,time,impedance_ohm" ||
          lower == "date,time,impedance_ohm,timestamp_status" ||
          s.startsWith('#')) {
        continue;
      }

      final unixSStatusMatch =
          RegExp(r'^(\d+),(-?\d+(?:\.\d+)?),([012])$').firstMatch(s);

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

      final msMatch =
          RegExp(r'unix_ms=(\d+)\s+Z=(-?\d+(?:\.\d+)?)').firstMatch(s);

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

      final unixSMatch =
          RegExp(r'^(\d+),(-?\d+(?:\.\d+)?)$').firstMatch(s);

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

      final datedMatch =
          RegExp(r'^(\d{4}-\d{2}-\d{2}),(\d{2}:\d{2}:\d{2}),(-?\d+(?:\.\d+)?)$')
              .firstMatch(s);

      if (datedMatch != null) {
        final dateStr = datedMatch.group(1)!;
        final timeStr = datedMatch.group(2)!;
        final impedance = datedMatch.group(3)!;
        lines.add("$dateStr,$timeStr,$impedance,unknown");
        continue;
      }

      final datedStatusMatch = RegExp(
        r'^(\d{4}-\d{2}-\d{2}),(\d{2}:\d{2}:\d{2}),(-?\d+(?:\.\d+)?),(known|unknown|estimated)$',
      ).firstMatch(s);

      if (datedStatusMatch != null) {
        final dateStr = datedStatusMatch.group(1)!;
        final timeStr = datedStatusMatch.group(2)!;
        final impedance = datedStatusMatch.group(3)!;
        final status = datedStatusMatch.group(4)!;
        lines.add("$dateStr,$timeStr,$impedance,$status");
      }
    }

    if (lines.length == 1) {
      final rawCsvish = sourceLogs
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && !e.startsWith('#'))
          .join("\n");

      if (rawCsvish.isEmpty) return "";
      return "date,time,impedance_ohm,timestamp_status\n$rawCsvish\n";
    }

    return "${lines.join("\n")}\n";
  }

  String _buildCsvFromLogs() => _buildCsvFromLogList(_logs);

  Future<void> _saveCsv({
    required String csv,
    bool showShareSheet = true,
    bool showSavedSnackbar = true,
    String? filenameSuffix,
  }) async {
    final normalizedCsv = csv.trim();
    if (normalizedCsv.isEmpty) {
      throw Exception("No CSV data to save.");
    }

    // Prevent duplicate saves of the same CSV within a short window.
    final saveKey = '${filenameSuffix ?? ""}::$normalizedCsv';
    final now = DateTime.now();

    if (_lastSavedKey == saveKey &&
        _lastSavedAt != null &&
        now.difference(_lastSavedAt!) < const Duration(seconds: 2)) {
      debugPrint("Skipping duplicate CSV save");
      return;
    }

    _lastSavedKey = saveKey;
    _lastSavedAt = now;

    final dir = await getApplicationDocumentsDirectory();
    final ts = now.toIso8601String().replaceAll(':', '-');
    final suffix = (filenameSuffix == null || filenameSuffix.isEmpty)
        ? ""
        : "_$filenameSuffix";
    final filename = "${widget.deviceName}_${ts}$suffix.csv";
    final file = File("${dir.path}/$filename");

    await file.writeAsString('$normalizedCsv\n');

    if (!mounted) return;

    if (showSavedSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved: $filename")),
      );
    }

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

  Future<void> _autoSaveCsvAfterBurst({
    required List<String> burstLogs,
    required String? transmitType,
  }) async {
    if (_isAutoSavingCsv) return;
    _isAutoSavingCsv = true;

    try {
      final csv = _buildCsvFromLogList(burstLogs);

      if (csv.trim().isEmpty) {
        throw Exception("Transmit finished but no CSV data was found.");
      }

      await _saveCsv(
        csv: csv,
        showShareSheet: false,
        showSavedSnackbar: false,
        filenameSuffix: transmitType == "recent" ? "recent" : "all",
      );

      if (!mounted) return;

      final successMessage = transmitType == "recent"
          ? "Recent data auto-saved successfully."
          : "All data auto-saved successfully.";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );

      await NotificationService.showTransmitSuccess(
        deviceName: widget.deviceName,
        message: successMessage,
      );
    } catch (e) {
      if (!mounted) return;

      final failureMessage = "$e";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );

      await NotificationService.showTransmitFailure(
        deviceName: widget.deviceName,
        message: failureMessage,
      );
    } finally {
      _isAutoSavingCsv = false;
      _currentTransmitType = null;
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
      _burstCloseTimer?.cancel();
      _burstInProgress = false;
      _burstSaveTriggered = false;
      _currentBurstLogs.clear();
      _currentTransmitType = choice;

      if (choice == "all") {
        widget.ble.log("Transmit all pressed");
        await widget.ble.startTransmit(widget.deviceId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transmit all started")),
        );
      } else {
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

      await NotificationService.showTransmitFailure(
        deviceName: widget.deviceName,
        message: "Transmit command failed: $e",
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
                              SnackBar(content: Text("Reconnect failed: $e")),
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
                      await _saveCsv(
                        csv: _buildCsvFromLogs(),
                        showShareSheet: true,
                        showSavedSnackbar: true,
                      );
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
                  label: const Text("Files"),
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
