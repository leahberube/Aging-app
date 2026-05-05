import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'notification_service.dart';
import 'ble_service.dart';

class TransmitResult {
  final String deviceId;
  final String deviceName;
  final TransmitStatus status;
  final String message;

  TransmitResult({
    required this.deviceId,
    required this.deviceName,
    required this.status,
    required this.message,
  });
}

class MultiBleService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;

  final StreamController<List<DiscoveredDevice>> _devicesCtrl =
      StreamController<List<DiscoveredDevice>>.broadcast();

  final List<DiscoveredDevice> _devices = [];

  final Map<String, BleService> _services = {};

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices);
  List<String> get managedDeviceIds => List.unmodifiable(_services.keys);

  bool hasServiceFor(String deviceId) => _services.containsKey(deviceId);

  BleService serviceFor(String deviceId) {
    return _services.putIfAbsent(deviceId, () => BleService());
  }

  void startScan() {
    _scanSub?.cancel();

    _scanSub = _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.lowLatency,
        )
        .listen((d) {
          final idx = _devices.indexWhere((x) => x.id == d.id);
          if (idx >= 0) {
            _devices[idx] = d;
          } else {
            _devices.add(d);
          }
          _devicesCtrl.add(List.of(_devices));
        });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connectAndSyncTime(String deviceId) async {
    final ble = serviceFor(deviceId);
    await ble.connectAndSyncTime(deviceId);
  }

  Future<void> connectAllFound({
    bool skipUnnamed = true,
    Duration delayBetweenStarts = const Duration(milliseconds: 700),
  }) async {
    await stopScan();

    final snapshot = List<DiscoveredDevice>.from(_devices);

    for (final d in snapshot) {
      if (skipUnnamed && d.name.trim().isEmpty) continue;

      try {
        await connectAndSyncTime(d.id);
      } catch (_) {}

      if (delayBetweenStarts > Duration.zero) {
        await Future.delayed(delayBetweenStarts);
      }
    }

    startScan();
  }

  Future<void> disconnectDevice(String deviceId) async {
    final ble = _services[deviceId];
    if (ble == null) return;
    await ble.disconnect();
  }

  Future<void> disconnectAll() async {
    for (final ble in _services.values) {
      await ble.disconnect();
    }
  }

  Future<void> startTransmit(String deviceId) async {
    await serviceFor(deviceId).startTransmit(deviceId);
  }

  Future<void> startTransmitRecent(String deviceId) async {
    await serviceFor(deviceId).startTransmitRecent(deviceId);
  }

  Future<void> eraseNand(String deviceId) async {
    await serviceFor(deviceId).eraseNand(deviceId);
  }

  Future<void> startCalibration(String deviceId) async {
    await serviceFor(deviceId).startCalibration(deviceId);
  }

  String _deviceName(String deviceId) {
    for (final d in _devices) {
      if (d.id == deviceId) {
        if (d.name.trim().isNotEmpty) return d.name.trim();
        break;
      }
    }
    return deviceId;
  }

  Future<TransmitResult> _transmitSingleDevice(
    String deviceId, {
    bool recentOnly = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final ble = _services[deviceId];

    if (ble == null) {
      return TransmitResult(
        deviceId: deviceId,
        deviceName: _deviceName(deviceId),
        status: TransmitStatus.failed,
        message: 'No service found for device.',
      );
    }

    if (!ble.isConnected) {
      return TransmitResult(
        deviceId: deviceId,
        deviceName: _deviceName(deviceId),
        status: TransmitStatus.failed,
        message: 'Device is not connected.',
      );
    }

    final deviceName = _deviceName(deviceId);
    StreamSubscription<String>? sub;
    final completer = Completer<TransmitResult>();

      try {
      sub = ble.logStream.listen((msg) {
        final text = msg.trim().toLowerCase();

        final isStart =
            text == '# burst recent start' || text == '# burst all start';
        final isSuccess =
            text == '# burst recent end' || text == '# burst all end';
        final isFailure =
            text.contains('# burst failed') ||
            text.contains('transmit failed') ||
            text.contains('error');

        if (isStart) return;

        if (isSuccess) {
          if (!completer.isCompleted) {
            completer.complete(
              TransmitResult(
                deviceId: deviceId,
                deviceName: deviceName,
                status: TransmitStatus.success,
                message: msg,
              ),
            );
          }
        } else if (isFailure) {
          if (!completer.isCompleted) {
            completer.complete(
              TransmitResult(
                deviceId: deviceId,
                deviceName: deviceName,
                status: TransmitStatus.failed,
                message: msg,
              ),
            );
          }
        }
      });

      if (recentOnly) {
        await ble.startTransmitRecent(deviceId);
      } else {
        await ble.startTransmit(deviceId);
      }

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => TransmitResult(
          deviceId: deviceId,
          deviceName: deviceName,
          status: TransmitStatus.timeout,
          message: 'Timed out waiting for transmit to finish.',
        ),
      );

      await sub.cancel();
      return result;
    } catch (e) {
      await sub?.cancel();
      return TransmitResult(
        deviceId: deviceId,
        deviceName: deviceName,
        status: TransmitStatus.failed,
        message: 'Exception: $e',
      );
    }
  }

  Future<List<TransmitResult>> transmitAllSequential(
    List<String> deviceIds, {
    bool recentOnly = false,
  }) async {
    final results = <TransmitResult>[];
    int successCount = 0;
    int failCount = 0;

    for (final deviceId in deviceIds) {
      final result = await _transmitSingleDevice(
        deviceId,
        recentOnly: recentOnly,
      );

      results.add(result);

      if (result.status == TransmitStatus.success) {
        successCount++;
      } else {
        failCount++;
      }

      await NotificationService.showTransmitResult(
        deviceName: result.deviceName,
        status: result.status,
        message: result.message,
      );
    }

    await NotificationService.showSummaryNotification(
      title: 'Transmit All finished',
      body: '$successCount succeeded, $failCount failed',
    );

    return results;
  }

  Future<void> removeDeviceService(String deviceId) async {
    final ble = _services.remove(deviceId);
    if (ble == null) return;
    await ble.dispose();
  }

  Future<void> dispose() async {
    await stopScan();

    for (final ble in _services.values) {
      await ble.dispose();
    }
    _services.clear();

    await _devicesCtrl.close();
  }
}

