import 'dart:async';
import 'package:flutter/material.dart';
import '../ble/multi_ble_service.dart';
import '../ble/ble_service.dart';

class CalibratePage extends StatefulWidget {
  final BleService ble;
  final String deviceId;

  const CalibratePage({
    super.key,
    required this.ble,
    required this.deviceId,
  });

  @override
  State<CalibratePage> createState() => _CalibratePageState();
}

class _CalibratePageState extends State<CalibratePage> {
  StreamSubscription<double>? _liveSub;
  StreamSubscription<String>? _logSub;

  double? _baselineImpedance;
  double? _currentImpedance;
  double? _percentChange;

  bool _isCalibrating = false;
  bool? _passed; // null = not started yet

  final List<String> _logs = [];
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();

    _logSub = widget.ble.logStream.listen((line) {
      if (!mounted) return;

      setState(() {
        _logs.add(line);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    });
  }

  void _startCalibration() {
    _liveSub?.cancel();

    setState(() {
      _isCalibrating = true;
      _baselineImpedance = null;
      _currentImpedance = null;
      _percentChange = null;
      _passed = null;
      _logs.clear();
    });

    widget.ble.log("Calibration started");

    _liveSub = widget.ble.liveImpedanceStream.listen((z) {
      if (!mounted || !_isCalibrating) return;

      setState(() {
        _baselineImpedance ??= z; // first live value becomes baseline
        _currentImpedance = z;

        if (_baselineImpedance != null && _baselineImpedance! != 0) {
          _percentChange =
              (((_currentImpedance! - _baselineImpedance!) / _baselineImpedance!) * 100.0);

          _passed = _percentChange! >= 4.0;
        }
      });
    });
  }

  void _stopCalibration() {
    _liveSub?.cancel();
    _liveSub = null;

    setState(() {
      _isCalibrating = false;
    });

    widget.ble.log("Calibration stopped");
  }

  String _statusText() {
    if (!_isCalibrating) return "Not calibrating";
    if (_baselineImpedance == null) return "Waiting for first live value...";
    if (_percentChange == null) return "Collecting live data...";
    return _passed == true ? "Calibration passed" : "Calibration not reached";
  }

  Widget _statusIcon() {
    if (!_isCalibrating || _passed == null) {
      return const Icon(Icons.hourglass_empty, size: 52);
    }

    return Icon(
      _passed == true ? Icons.check_circle : Icons.cancel,
      size: 60,
      color: _passed == true ? Colors.green : Colors.red,
    );
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _logSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.ble.isConnected;

    return Scaffold(
      appBar: AppBar(title: const Text("Calibration")),
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
                  stream: widget.ble.rssiStream,
                  builder: (context, snap) {
                    final rssi = snap.data;
                    return Text(rssi == null ? "(-- dBm)" : "($rssi dBm)");
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: connected && !_isCalibrating
                            ? _startCalibration
                            : null,
                        child: const Text("Start Calibration"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isCalibrating ? _stopCalibration : null,
                        child: const Text("Stop"),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _statusIcon(),
                    const SizedBox(height: 10),
                    Text(
                      _statusText(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Baseline: ${_baselineImpedance?.toStringAsFixed(2) ?? '--'} Ω",
                    ),
                    Text(
                      "Current: ${_currentImpedance?.toStringAsFixed(2) ?? '--'} Ω",
                    ),
                    Text(
                      "Change: ${_percentChange?.toStringAsFixed(2) ?? '--'} %",
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Pass threshold: +4%",
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
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
                          ? const Text("No calibration logs yet.")
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
