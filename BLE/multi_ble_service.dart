import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'uuids.dart';
import 'time_codec.dart';

enum CalState { idle, calibrating, success, fail }

class ImpSample {
  final int unixMs;
  final double zOhm;
  ImpSample(this.unixMs, this.zOhm);
}

class DeviceState {
  final String id;
  final String name;

  DeviceConnectionState connState = DeviceConnectionState.disconnected;
  bool get connected => connState == DeviceConnectionState.connected;

  int? rssi;
  double latestZ = 0.0;

  // Default threshold: 10% increase required
  double minIncreasePct = 0.10;

  CalState calState = CalState.idle;
  String calMsg = "Waiting…";
  final List<ImpSample> calSamples = [];

  StreamSubscription<ConnectionStateUpdate>? connSub;
  StreamSubscription<List<int>>? notifySub;
  Timer? rssiTimer;

  DeviceState({required this.id, required this.name});
}

class MultiBleService extends ChangeNotifier {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  final Set<String> targetNames;
  final Map<String, DeviceState> devices = {}; // id -> state

  StreamSubscription<DiscoveredDevice>? _scanSub;

  final StreamController<String> _logCtrl = StreamController<String>.broadcast();
  Stream<String> get logStream => _logCtrl.stream;

  void log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logCtrl.add("[$ts] $msg");
  }

  MultiBleService({required this.targetNames});

  List<DeviceState> get deviceList {
    final list = devices.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // ---------------- SCAN ----------------
  void startScan() {
    stopScan();
    log("Scan started");

    _scanSub = _ble
        .scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency)
        .listen((d) {
      if (d.name.isEmpty) return;
      if (!targetNames.contains(d.name)) return;

      devices.putIfAbsent(d.id, () {
        log("Found target: ${d.name} (${d.id})");
        return DeviceState(id: d.id, name: d.name);
      });

      notifyListeners();
    }, onError: (e) {
      log("Scan error: $e");
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  // -------------- CONNECT --------------
  Future<void> connectAllFound() async {
    for (final st in deviceList) {
      if (!st.connected && st.connSub == null) {
        unawaited(connect(st.id));
      }
    }
  }

  Future<void> connect(String deviceId) async {
    final st = devices[deviceId];
    if (st == null) return;
    if (st.connSub != null) return;

    log("Connecting to ${st.name} ($deviceId)");

    st.connSub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen((u) async {
      st.connState = u.connectionState;
      notifyListeners();

      if (u.connectionState == DeviceConnectionState.connected) {
        log("Connected: ${st.name}");

        await _syncTime(deviceId);
        _startRssi(st);
        _subscribeImpedance(st);

        st.calMsg = "Connected";
        notifyListeners();
      }

      if (u.connectionState == DeviceConnectionState.disconnected) {
        log("Disconnected: ${st.name}");
        await _cleanup(st);

        st.calState = CalState.idle;
        st.calMsg = "Disconnected";
        notifyListeners();

        await st.connSub?.cancel();
        st.connSub = null;
      }
    }, onError: (e) async {
      log("Connect error ${st.name}: $e");
      await _cleanup(st);

      await st.connSub?.cancel();
      st.connSub = null;

      st.connState = DeviceConnectionState.disconnected;
      st.calState = CalState.fail;
      st.calMsg = "Connection failed";
      notifyListeners();
    });
  }

  Future<void> disconnect(String deviceId) async {
    final st = devices[deviceId];
    if (st == null) return;

    log("Disconnect requested: ${st.name}");
    await _cleanup(st);

    await st.connSub?.cancel();
    st.connSub = null;

    st.connState = DeviceConnectionState.disconnected;
    st.calState = CalState.idle;
    st.calMsg = "Disconnected";
    notifyListeners();
  }

  Future<void> disconnectAll() async {
    for (final st in deviceList) {
      await disconnect(st.id);
    }
  }

  Future<void> _cleanup(DeviceState st) async {
    await st.notifySub?.cancel();
    st.notifySub = null;

    st.rssiTimer?.cancel();
    st.rssiTimer = null;

    st.rssi = null;
  }

  Future<void> _syncTime(String deviceId) async {
    try {
      final unixMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final bytes = int64ToLittleEndianBytes(unixMs);

      final qc = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: timeServiceUuid,
        characteristicId: timeCharUuid,
      );

      await _ble.writeCharacteristicWithResponse(qc, value: bytes);
      log("Time sync ok: $deviceId unix_ms=$unixMs");
    } catch (e) {
      log("Time sync failed ($deviceId): $e");
    }
  }

  void _startRssi(DeviceState st) {
    st.rssiTimer?.cancel();
    st.rssiTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        st.rssi = await _ble.readRssi(st.id);
      } catch (_) {
        st.rssi = null;
      }
      notifyListeners();
    });
  }

  void _subscribeImpedance(DeviceState st) {
    st.notifySub?.cancel();

    final qc = QualifiedCharacteristic(
      deviceId: st.id,
      serviceId: impedanceServiceUuid,
      characteristicId: impedanceNotifyCharUuid,
    );

    log("Subscribe impedance notify: ${st.name}");

    st.notifySub = _ble.subscribeToCharacteristic(qc).listen((payload) {
      final sample = _parseImpedance(payload);
      if (sample == null) return;

      st.latestZ = sample.zOhm;

      if (st.calState == CalState.calibrating) {
        st.calSamples.add(sample);
      }

      notifyListeners();
    }, onError: (e) {
      log("Notify error ${st.name}: $e");
      st.calState = CalState.fail;
      st.calMsg = "Notify error";
      notifyListeners();
    });
  }

  // Preferred payload: 16 bytes:
  // [uint64 unix_ms][float32 z_ohm][int16 r][int16 im]
  // Fallback payload: 4 bytes [float32 z_ohm]
  ImpSample? _parseImpedance(List<int> payload) {
    if (payload.length < 4) return null;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));
    try {
      if (payload.length >= 16) {
        final unixMs = bd.getUint64(0, Endian.little);
        final z = bd.getFloat32(8, Endian.little).toDouble();
        if (z.isNaN || z.isInfinite || z <= 0) return null;
        return ImpSample(unixMs, z);
      } else {
        final z = bd.getFloat32(0, Endian.little).toDouble();
        if (z.isNaN || z.isInfinite || z <= 0) return null;
        return ImpSample(DateTime.now().millisecondsSinceEpoch, z);
      }
    } catch (_) {
      return null;
    }
  }

  // ----------- CALIBRATION -----------
  void startCalibration(String deviceId) {
    final st = devices[deviceId];
    if (st == null) return;

    if (!st.connected) {
      st.calState = CalState.fail;
      st.calMsg = "Fail: not connected";
      notifyListeners();
      return;
    }

    st.calSamples.clear();
    st.calState = CalState.calibrating;
    st.calMsg = "Calibrating… hold still, then bend/stretch.";
    notifyListeners();

    Future.delayed(const Duration(seconds: 8), () {
      final (pass, msg) = _evaluateIncrease(st.calSamples, st.minIncreasePct);
      st.calState = pass ? CalState.success : CalState.fail;
      st.calMsg = msg;
      notifyListeners();
    });
  }

  (bool, String) _evaluateIncrease(List<ImpSample> s, double minPct) {
    if (s.length < 15) return (false, "Fail: not enough data received.");

    final t0 = s.first.unixMs;

    // windows (tune later)
    final baselineEnd = t0 + 1800;   // first 1.8s
    final activityStart = t0 + 2200; // 2.2s
    final activityEnd = t0 + 6500;   // 6.5s

    final baseline = <double>[];
    final activity = <double>[];

    for (final p in s) {
      if (p.unixMs <= baselineEnd) baseline.add(p.zOhm);
      if (p.unixMs >= activityStart && p.unixMs <= activityEnd) {
        activity.add(p.zOhm);
      }
    }

    if (baseline.length < 5 || activity.length < 5) {
      return (false, "Fail: not enough samples in windows.");
    }

    baseline.sort();
    final b = baseline[baseline.length ~/ 2]; // median
    final peak = activity.reduce(max);

    final pct = b != 0 ? ((peak - b) / b) : 0.0;

    final pctStr = (pct * 100).toStringAsFixed(1);
    final targetStr = (minPct * 100).toStringAsFixed(0);

    if (pct >= minPct) {
      return (true, "Success: +$pctStr% (target $targetStr%).");
    } else {
      return (false, "Fail: +$pctStr% (need $targetStr%).");
    }
  }

  @override
  void dispose() {
    stopScan();
    for (final st in devices.values) {
      st.notifySub?.cancel();
      st.connSub?.cancel();
      st.rssiTimer?.cancel();
    }
    _logCtrl.close();
    super.dispose();
  }
}