
// // import 'dart:async';
// // import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
// // import 'uuids.dart';
// // import 'time_codec.dart';

// // class BleService {
// //   final FlutterReactiveBle _ble = FlutterReactiveBle();
// //   StreamSubscription<DiscoveredDevice>? _scanSub;
// //   StreamSubscription<ConnectionStateUpdate>? _connSub;

// //   final StreamController<List<DiscoveredDevice>> _devicesCtrl =
// //       StreamController<List<DiscoveredDevice>>.broadcast();

// //   List<DiscoveredDevice> _devices = [];
// //   String? connectedDeviceId;

// //   DeviceConnectionState _lastConnState = DeviceConnectionState.disconnected;
// //   bool get isConnected => _lastConnState == DeviceConnectionState.connected;
// //   DeviceConnectionState get connectionState => _lastConnState;

// //   Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;

// //   // ---- RSSI ----
// //   final StreamController<int?> _rssiCtrl = StreamController<int?>.broadcast();
// //   Stream<int?> get rssiStream => _rssiCtrl.stream;
// //   Timer? _rssiTimer;

// //   // ---- Battery + Charging streams ----
// //   final StreamController<int?> _batteryPercentCtrl =
// //       StreamController<int?>.broadcast();
// //   final StreamController<bool?> _chargingCtrl =
// //       StreamController<bool?>.broadcast();

// //   Stream<int?> get batteryPercentStream => _batteryPercentCtrl.stream;
// //   Stream<bool?> get chargingStream => _chargingCtrl.stream;

// //   // ---- Live impedance stream ----
// //   final StreamController<double> _liveImpedanceCtrl =
// //       StreamController<double>.broadcast();
// //   Stream<double> get liveImpedanceStream => _liveImpedanceCtrl.stream;

// //   // Standard BLE Battery Service UUIDs
// //   final Uuid _basService = Uuid.parse("0000180f-0000-1000-8000-00805f9b34fb");
// //   final Uuid _basLevelChar = Uuid.parse("00002a19-0000-1000-8000-00805f9b34fb");

// //   // Optional custom charging UUIDs (only if firmware implements them)
// //   final Uuid _powerService =
// //       Uuid.parse("6f7b7a10-9c3a-4e7e-8d22-9f2c0e0b8f01");
// //   final Uuid _chargingChar =
// //       Uuid.parse("6f7b7a11-9c3a-4e7e-8d22-9f2c0e0b8f01");

// //   // Internal subs
// //   StreamSubscription<List<int>>? _batteryNotifySub;
// //   StreamSubscription<List<int>>? _chargingNotifySub;

// //   // ---- Terminal / logs ----
// //   final StreamController<String> _logCtrl = StreamController<String>.broadcast();
// //   Stream<String> get logStream => _logCtrl.stream;

// //   // ---- Device terminal stream (bleprint notifications) ----
// //   StreamSubscription<List<int>>? _terminalNotifySub;

// //   void log(String msg) {
// //     final ts = DateTime.now().toIso8601String().substring(11, 19);
// //     _logCtrl.add("[$ts] $msg");
// //   }

// //   // ===================== Scan =====================

// //   void startScan() {
// //     _devices = [];
// //     _devicesCtrl.add(_devices);

// //     _scanSub?.cancel();
// //     _scanSub = _ble
// //         .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
// //         .listen((d) {
// //       final existingIndex = _devices.indexWhere((x) => x.id == d.id);
// //       if (existingIndex >= 0) {
// //         _devices[existingIndex] = d;
// //       } else {
// //         _devices.add(d);
// //       }
// //       _devicesCtrl.add(List.of(_devices));
// //     });
// //   }

// //   Future<void> stopScan() async {
// //     await _scanSub?.cancel();
// //     _scanSub = null;
// //   }

// //   // ===================== Connect + Time Sync =====================

// //   Future<void> connectAndSyncTime(String deviceId) async {
// //     log("Stopping scan before connect");
// //     await stopScan();

// //     connectedDeviceId = deviceId;
// //     log("Connecting to $deviceId");

// //     _connSub?.cancel();
// //     final completer = Completer<void>();

// //     _connSub = _ble
// //         .connectToDevice(
// //           id: deviceId,
// //           connectionTimeout: const Duration(seconds: 10),
// //         )
// //         .listen((update) async {
// //       _lastConnState = update.connectionState;
// //       log("Connection state: ${update.connectionState}");

// //       if (update.connectionState == DeviceConnectionState.connected) {
// //         log("Connected to $deviceId");

// //         startRssiPolling();
// //         log("RSSI polling started");

// //         startBatteryAndChargingSubscriptions(deviceId);
// //         log("Battery/charging subscriptions started");

// //         startTerminalSubscription(deviceId);
// //         log("Terminal subscription started");

// //         try {
// //           final nowUtc = DateTime.now().toUtc();
// //           final unixMs = nowUtc.millisecondsSinceEpoch;
// //           final bytes = int64ToLittleEndianBytes(unixMs);

// //           log("Time sync write (unix ms: $unixMs)");

// //           final qc = QualifiedCharacteristic(
// //             deviceId: deviceId,
// //             serviceId: timeServiceUuid,
// //             characteristicId: timeCharUuid,
// //           );

// //           await _ble.writeCharacteristicWithResponse(qc, value: bytes);

// //           log("Time sync successful");
// //           if (!completer.isCompleted) completer.complete();
// //         } catch (e) {
// //           log("Time sync failed: $e");
// //           if (!completer.isCompleted) completer.completeError(e);
// //         }
// //       }

// //       if (update.connectionState == DeviceConnectionState.disconnected) {
// //         log("Disconnected");

// //         stopRssiPolling();
// //         await stopBatteryAndChargingSubscriptions();
// //         await stopTerminalSubscription();

// //         _rssiCtrl.add(null);
// //         _batteryPercentCtrl.add(null);
// //         _chargingCtrl.add(null);

// //         if (!completer.isCompleted) {
// //           completer.completeError(Exception("Disconnected before time sync."));
// //         }
// //       }
// //     });

// //     return completer.future;
// //   }

// //   // ===================== Transmit =====================

// //   Future<void> startTransmit(String deviceId) async {
// //     final qc = QualifiedCharacteristic(
// //       deviceId: deviceId,
// //       serviceId: timeServiceUuid,
// //       characteristicId: timeCharUuid,
// //     );

// //     await _ble.writeCharacteristicWithResponse(qc, value: const [0x02]);
// //     log("TX: wrote 0x02");
// //   }

// //   // ===================== Disconnect =====================

// //   Future<void> disconnect() async {
// //     log("Disconnect requested");

// //     stopRssiPolling();
// //     await stopBatteryAndChargingSubscriptions();
// //     await stopTerminalSubscription();

// //     await _connSub?.cancel();
// //     _connSub = null;

// //     connectedDeviceId = null;
// //     _lastConnState = DeviceConnectionState.disconnected;

// //     _rssiCtrl.add(null);
// //     _batteryPercentCtrl.add(null);
// //     _chargingCtrl.add(null);
// //   }

// //   // ===================== RSSI =====================

// //   void startRssiPolling({Duration period = const Duration(seconds: 1)}) {
// //     final id = connectedDeviceId;
// //     if (id == null) return;

// //     _rssiTimer?.cancel();
// //     _rssiCtrl.add(null);

// //     _rssiTimer = Timer.periodic(period, (_) async {
// //       final curId = connectedDeviceId;
// //       if (curId == null) return;

// //       try {
// //         final rssi = await _ble.readRssi(curId);
// //         _rssiCtrl.add(rssi);
// //       } catch (_) {
// //         _rssiCtrl.add(null);
// //       }
// //     });
// //   }

// //   void stopRssiPolling() {
// //     _rssiTimer?.cancel();
// //     _rssiTimer = null;
// //     _rssiCtrl.add(null);
// //   }

// //   // ===================== Battery + Charging =====================

// //   Future<void> readBatteryOnce(String deviceId) async {
// //     final qc = QualifiedCharacteristic(
// //       deviceId: deviceId,
// //       serviceId: _basService,
// //       characteristicId: _basLevelChar,
// //     );

// //     try {
// //       final data = await _ble.readCharacteristic(qc);
// //       if (data.isNotEmpty) {
// //         final p = data[0].clamp(0, 100);
// //         _batteryPercentCtrl.add(p);
// //       }
// //     } catch (_) {
// //       // leave unknown
// //     }
// //   }

// //   void startBatteryAndChargingSubscriptions(String deviceId) {
// //     final battQc = QualifiedCharacteristic(
// //       deviceId: deviceId,
// //       serviceId: _basService,
// //       characteristicId: _basLevelChar,
// //     );

// //     _batteryNotifySub?.cancel();
// //     _batteryNotifySub = _ble.subscribeToCharacteristic(battQc).listen(
// //       (data) {
// //         if (data.isEmpty) return;
// //         final p = data[0].clamp(0, 100);
// //         _batteryPercentCtrl.add(p);
// //       },
// //       onError: (_) => _batteryPercentCtrl.add(null),
// //     );

// //     readBatteryOnce(deviceId);

// //     final chgQc = QualifiedCharacteristic(
// //       deviceId: deviceId,
// //       serviceId: _powerService,
// //       characteristicId: _chargingChar,
// //     );

// //     _chargingNotifySub?.cancel();
// //     _chargingNotifySub = _ble.subscribeToCharacteristic(chgQc).listen(
// //       (data) {
// //         if (data.isEmpty) return;
// //         _chargingCtrl.add(data[0] == 1);
// //       },
// //       onError: (_) => _chargingCtrl.add(null),
// //     );
// //   }

// //   Future<void> stopBatteryAndChargingSubscriptions() async {
// //     await _batteryNotifySub?.cancel();
// //     await _chargingNotifySub?.cancel();
// //     _batteryNotifySub = null;
// //     _chargingNotifySub = null;
// //   }

// //   // ===================== Terminal / bleprint =====================

// //   void startTerminalSubscription(String deviceId) {
// //     final qc = QualifiedCharacteristic(
// //       deviceId: deviceId,
// //       serviceId: bleprintServiceUuid,
// //       characteristicId: bleprintCharUuid,
// //     );

// //     _terminalNotifySub?.cancel();
// //     _terminalNotifySub = _ble.subscribeToCharacteristic(qc).listen(
// //       (data) {
// //         if (data.isEmpty) return;

// //         final text = String.fromCharCodes(data);
// //         final lines = text.replaceAll('\r', '').split('\n');

// //         for (final line in lines) {
// //           final trimmed = line.trim();
// //           if (trimmed.isEmpty) continue;

// //           if (trimmed.startsWith("LIVE,")) {
// //             final parts = trimmed.split(',');
// //             if (parts.length >= 2) {
// //               final z = double.tryParse(parts[1]);
// //               if (z != null) {
// //                 _liveImpedanceCtrl.add(z);
// //               }
// //             }
// //           }

// //           _logCtrl.add(trimmed);
// //         }
// //       },
// //       onError: (e) {
// //         log("Terminal subscribe error: $e");
// //       },
// //     );
// //   }

// //   Future<void> stopTerminalSubscription() async {
// //     await _terminalNotifySub?.cancel();
// //     _terminalNotifySub = null;
// //   }
// //   // ===================== NAND ERASE =====================
// //   Future<void> eraseNand(String deviceId) async {
// //     final qc = QualifiedCharacteristic(
// //       deviceId: deviceId,
// //       serviceId: timeServiceUuid,
// //       characteristicId: timeCharUuid,
// //     );

// //     await _ble.writeCharacteristicWithResponse(qc, value: const [0x01]);
// //     log("TX: wrote 0x01");
// //   }

// //   // ===================== Dispose =====================

// //   Future<void> dispose() async {
// //     stopRssiPolling();
// //     await stopScan();
// //     await disconnect();

// //     await _devicesCtrl.close();
// //     await _rssiCtrl.close();
// //     await _batteryPercentCtrl.close();
// //     await _chargingCtrl.close();
// //     await _logCtrl.close();
// //     await _liveImpedanceCtrl.close();
// //   }
// // }


// import 'dart:async';
// import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
// import 'uuids.dart';
// import 'time_codec.dart';

// class BleService {
//   final FlutterReactiveBle _ble = FlutterReactiveBle();
//   StreamSubscription<DiscoveredDevice>? _scanSub;
//   StreamSubscription<ConnectionStateUpdate>? _connSub;

//   final StreamController<List<DiscoveredDevice>> _devicesCtrl =
//       StreamController<List<DiscoveredDevice>>.broadcast();

//   List<DiscoveredDevice> _devices = [];
//   String? connectedDeviceId;

//   DeviceConnectionState _lastConnState = DeviceConnectionState.disconnected;
//   bool get isConnected => _lastConnState == DeviceConnectionState.connected;
//   DeviceConnectionState get connectionState => _lastConnState;

//   Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;

//   // ---- RSSI ----
//   final StreamController<int?> _rssiCtrl = StreamController<int?>.broadcast();
//   Stream<int?> get rssiStream => _rssiCtrl.stream;
//   Timer? _rssiTimer;

//   // ---- Battery + Charging streams ----
//   final StreamController<int?> _batteryPercentCtrl =
//       StreamController<int?>.broadcast();
//   final StreamController<bool?> _chargingCtrl =
//       StreamController<bool?>.broadcast();

//   Stream<int?> get batteryPercentStream => _batteryPercentCtrl.stream;
//   Stream<bool?> get chargingStream => _chargingCtrl.stream;

//   // ---- Live impedance stream ----
//   final StreamController<double> _liveImpedanceCtrl =
//       StreamController<double>.broadcast();
//   Stream<double> get liveImpedanceStream => _liveImpedanceCtrl.stream;

//   // Standard BLE Battery Service UUIDs
//   final Uuid _basService = Uuid.parse("0000180f-0000-1000-8000-00805f9b34fb");
//   final Uuid _basLevelChar = Uuid.parse("00002a19-0000-1000-8000-00805f9b34fb");

//   // Optional custom charging UUIDs (only if firmware implements them)
//   final Uuid _powerService =
//       Uuid.parse("6f7b7a10-9c3a-4e7e-8d22-9f2c0e0b8f01");
//   final Uuid _chargingChar =
//       Uuid.parse("6f7b7a11-9c3a-4e7e-8d22-9f2c0e0b8f01");

//   // Internal subs
//   StreamSubscription<List<int>>? _batteryNotifySub;
//   StreamSubscription<List<int>>? _chargingNotifySub;

//   // ---- Terminal / logs ----
//   final StreamController<String> _logCtrl = StreamController<String>.broadcast();
//   Stream<String> get logStream => _logCtrl.stream;

//   // ---- Device terminal stream (bleprint notifications) ----
//   StreamSubscription<List<int>>? _terminalNotifySub;

//   void log(String msg) {
//     final ts = DateTime.now().toIso8601String().substring(11, 19);
//     _logCtrl.add("[$ts] $msg");
//   }

//   // ===================== Scan =====================

//   void startScan() {
//     _devices = [];
//     _devicesCtrl.add(_devices);

//     _scanSub?.cancel();
//     _scanSub = _ble
//         .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
//         .listen((d) {
//       final existingIndex = _devices.indexWhere((x) => x.id == d.id);
//       if (existingIndex >= 0) {
//         _devices[existingIndex] = d;
//       } else {
//         _devices.add(d);
//       }
//       _devicesCtrl.add(List.of(_devices));
//     });
//   }

//   Future<void> stopScan() async {
//     await _scanSub?.cancel();
//     _scanSub = null;
//   }

//   // ===================== Connect + Time Sync =====================

//   Future<void> connectAndSyncTime(String deviceId) async {
//     log("Stopping scan before connect");
//     await stopScan();

//     connectedDeviceId = deviceId;
//     log("Connecting to $deviceId");

//     _connSub?.cancel();
//     final completer = Completer<void>();

//     _connSub = _ble
//         .connectToDevice(
//           id: deviceId,
//           connectionTimeout: const Duration(seconds: 10),
//         )
//         .listen((update) async {
//       _lastConnState = update.connectionState;
//       log("Connection state: ${update.connectionState}");

//       if (update.connectionState == DeviceConnectionState.connected) {
//         log("Connected to $deviceId");

//         startRssiPolling();
//         log("RSSI polling started");

//         startBatteryAndChargingSubscriptions(deviceId);
//         log("Battery/charging subscriptions started");

//         await syncTime(deviceId);
//         log("Time synced");

//         // REMOVE anything like this:
//         // await startCalibration(deviceId);
//         // await startRecording(deviceId);

//         if (!completer.isCompleted) {
//           completer.complete();
//         }
//       }

//       if (update.connectionState == DeviceConnectionState.disconnected) {
//         log("Disconnected from $deviceId");
//         connectedDeviceId = null;

//         if (!completer.isCompleted) {
//           completer.completeError(Exception("Disconnected before setup completed"));
//         }
//       }
//     }, onError: (e) {
//       log("Connection error: $e");
//       if (!completer.isCompleted) {
//         completer.completeError(e);
//       }
//     });

//     return completer.future;
//   }
//   // ===================== Transmit =====================

//   Future<void> startTransmit(String deviceId) async {
//     final qc = QualifiedCharacteristic(
//       deviceId: deviceId,
//       serviceId: timeServiceUuid,
//       characteristicId: timeCharUuid,
//     );

//     await _ble.writeCharacteristicWithResponse(qc, value: const [0x02]);
//     log("TX: wrote 0x02");
//   }

//   // ===================== Disconnect =====================

//   Future<void> disconnect() async {
//     log("Disconnect requested");

//     stopRssiPolling();
//     await stopBatteryAndChargingSubscriptions();
//     await stopTerminalSubscription();

//     await _connSub?.cancel();
//     _connSub = null;

//     connectedDeviceId = null;
//     _lastConnState = DeviceConnectionState.disconnected;

//     _rssiCtrl.add(null);
//     _batteryPercentCtrl.add(null);
//     _chargingCtrl.add(null);
//   }

//   // ===================== RSSI =====================

//   void startRssiPolling({Duration period = const Duration(seconds: 1)}) {
//     final id = connectedDeviceId;
//     if (id == null) return;

//     _rssiTimer?.cancel();
//     _rssiCtrl.add(null);

//     _rssiTimer = Timer.periodic(period, (_) async {
//       final curId = connectedDeviceId;
//       if (curId == null) return;

//       try {
//         final rssi = await _ble.readRssi(curId);
//         _rssiCtrl.add(rssi);
//       } catch (_) {
//         _rssiCtrl.add(null);
//       }
//     });
//   }

//   void stopRssiPolling() {
//     _rssiTimer?.cancel();
//     _rssiTimer = null;
//     _rssiCtrl.add(null);
//   }

//   // ===================== Battery + Charging =====================

//   Future<void> readBatteryOnce(String deviceId) async {
//     final qc = QualifiedCharacteristic(
//       deviceId: deviceId,
//       serviceId: _basService,
//       characteristicId: _basLevelChar,
//     );

//     try {
//       final data = await _ble.readCharacteristic(qc);
//       if (data.isNotEmpty) {
//         final p = data[0].clamp(0, 100);
//         _batteryPercentCtrl.add(p);
//       }
//     } catch (_) {
//       // leave unknown
//     }
//   }

//   void startBatteryAndChargingSubscriptions(String deviceId) {
//     final battQc = QualifiedCharacteristic(
//       deviceId: deviceId,
//       serviceId: _basService,
//       characteristicId: _basLevelChar,
//     );

//     _batteryNotifySub?.cancel();
//     _batteryNotifySub = _ble.subscribeToCharacteristic(battQc).listen(
//       (data) {
//         if (data.isEmpty) return;
//         final p = data[0].clamp(0, 100);
//         _batteryPercentCtrl.add(p);
//       },
//       onError: (_) => _batteryPercentCtrl.add(null),
//     );

//     readBatteryOnce(deviceId);

//     final chgQc = QualifiedCharacteristic(
//       deviceId: deviceId,
//       serviceId: _powerService,
//       characteristicId: _chargingChar,
//     );

//     _chargingNotifySub?.cancel();
//     _chargingNotifySub = _ble.subscribeToCharacteristic(chgQc).listen(
//       (data) {
//         if (data.isEmpty) return;
//         _chargingCtrl.add(data[0] == 1);
//       },
//       onError: (_) => _chargingCtrl.add(null),
//     );
//   }

//   Future<void> stopBatteryAndChargingSubscriptions() async {
//     await _batteryNotifySub?.cancel();
//     await _chargingNotifySub?.cancel();
//     _batteryNotifySub = null;
//     _chargingNotifySub = null;
//   }

//   // ===================== Terminal / bleprint =====================

//   void startTerminalSubscription(String deviceId) {
//     final qc = QualifiedCharacteristic(
//       deviceId: deviceId,
//       serviceId: bleprintServiceUuid,
//       characteristicId: bleprintCharUuid,
//     );

//     _terminalNotifySub?.cancel();
//     _terminalNotifySub = _ble.subscribeToCharacteristic(qc).listen(
//       (data) {
//         if (data.isEmpty) return;

//         final text = String.fromCharCodes(data);
//         final lines = text.replaceAll('\r', '').split('\n');

//         for (final line in lines) {
//           final trimmed = line.trim();
//           if (trimmed.isEmpty) continue;

//           if (trimmed.startsWith("LIVE,")) {
//             final parts = trimmed.split(',');
//             if (parts.length >= 2) {
//               final z = double.tryParse(parts[1]);
//               if (z != null) {
//                 _liveImpedanceCtrl.add(z);
//               }
//             }
//           }

//           _logCtrl.add(trimmed);
//         }
//       },
//       onError: (e) {
//         log("Terminal subscribe error: $e");
//       },
//     );
//   }

//   Future<void> stopTerminalSubscription() async {
//     await _terminalNotifySub?.cancel();
//     _terminalNotifySub = null;
//   }
//   // ===================== NAND ERASE =====================
//   Future<void> eraseNand(String deviceId) async {
//     final qc = QualifiedCharacteristic(
//       deviceId: deviceId,
//       serviceId: timeServiceUuid,
//       characteristicId: timeCharUuid,
//     );

//     await _ble.writeCharacteristicWithResponse(qc, value: const [0x01]);
//     log("TX: wrote 0x01");
//   }

//   // start calibration
//   Future<void> startCalibrationFlow() async {
//     final deviceId = connectedDeviceId;
//     if (deviceId == null) {
//       log("Cannot start calibration: no device connected");
//       return;
//     }

//     try {
//       log("Starting calibration...");
//       await startCalibration(deviceId);

//       log("Calibration complete, starting recording...");
//       await startRecording(deviceId);

//       log("Recording started");
//     } catch (e) {
//       log("Calibration flow failed: $e");
//     }
//   }
//   // ===================== Dispose =====================

//   Future<void> dispose() async {
//     stopRssiPolling();
//     await stopScan();
//     await disconnect();

//     await _devicesCtrl.close();
//     await _rssiCtrl.close();
//     await _batteryPercentCtrl.close();
//     await _chargingCtrl.close();
//     await _logCtrl.close();
//     await _liveImpedanceCtrl.close();
//   }
// }


import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'uuids.dart';
import 'time_codec.dart';

class BleService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _batteryNotifySub;
  StreamSubscription<List<int>>? _chargingNotifySub;
  StreamSubscription<List<int>>? _terminalNotifySub;

  final StreamController<List<DiscoveredDevice>> _devicesCtrl =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final StreamController<int?> _rssiCtrl = StreamController<int?>.broadcast();
  final StreamController<int?> _batteryPercentCtrl =
      StreamController<int?>.broadcast();
  final StreamController<bool?> _chargingCtrl =
      StreamController<bool?>.broadcast();
  final StreamController<double> _liveImpedanceCtrl =
      StreamController<double>.broadcast();
  final StreamController<String> _logCtrl =
      StreamController<String>.broadcast();

  List<DiscoveredDevice> _devices = [];
  String? connectedDeviceId;
  Timer? _rssiTimer;

  DeviceConnectionState _lastConnState = DeviceConnectionState.disconnected;

  bool get isConnected => _lastConnState == DeviceConnectionState.connected;
  DeviceConnectionState get connectionState => _lastConnState;

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;
  Stream<int?> get rssiStream => _rssiCtrl.stream;
  Stream<int?> get batteryPercentStream => _batteryPercentCtrl.stream;
  Stream<bool?> get chargingStream => _chargingCtrl.stream;
  Stream<double> get liveImpedanceStream => _liveImpedanceCtrl.stream;
  Stream<String> get logStream => _logCtrl.stream;

  final Uuid _basService = Uuid.parse("0000180f-0000-1000-8000-00805f9b34fb");
  final Uuid _basLevelChar = Uuid.parse("00002a19-0000-1000-8000-00805f9b34fb");

  final Uuid _powerService =
      Uuid.parse("6f7b7a10-9c3a-4e7e-8d22-9f2c0e0b8f01");
  final Uuid _chargingChar =
      Uuid.parse("6f7b7a11-9c3a-4e7e-8d22-9f2c0e0b8f01");

  void log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logCtrl.add("[$ts] $msg");
  }

  void startScan() {
    _devices = [];
    _devicesCtrl.add(_devices);

    _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen((d) {
      final idx = _devices.indexWhere((x) => x.id == d.id);
      if (idx >= 0) {
        _devices[idx] = d;
      } else {
        _devices.add(d);
      }
      _devicesCtrl.add(List.of(_devices));
    }, onError: (e) {
      log("Scan error: $e");
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connectAndSyncTime(String deviceId) async {
    log("Stopping scan before connect");
    await stopScan();

    connectedDeviceId = deviceId;
    log("Connecting to $deviceId");

    await _connSub?.cancel();
    final completer = Completer<void>();

    _connSub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen((update) async {
      _lastConnState = update.connectionState;
      log("Connection state: ${update.connectionState}");

      if (update.connectionState == DeviceConnectionState.connected) {
        log("Connected to $deviceId");

        startRssiPolling();
        log("RSSI polling started");

        startBatteryAndChargingSubscriptions(deviceId);
        log("Battery/charging subscriptions started");

        startTerminalSubscription(deviceId);
        log("Terminal subscription started");

        try {
          final nowUtc = DateTime.now().toUtc();
          final unixMs = nowUtc.millisecondsSinceEpoch;
          final bytes = int64ToLittleEndianBytes(unixMs);

          final qc = QualifiedCharacteristic(
            deviceId: deviceId,
            serviceId: timeServiceUuid,
            characteristicId: timeCharUuid,
          );

          log("Time sync write (unix ms: $unixMs)");
          await _ble.writeCharacteristicWithResponse(qc, value: bytes);
          log("Time sync successful");

          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (e) {
          log("Time sync failed: $e");
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      }

      if (update.connectionState == DeviceConnectionState.disconnected) {
        log("Disconnected from $deviceId");

        connectedDeviceId = null;
        stopRssiPolling();
        await stopBatteryAndChargingSubscriptions();
        await stopTerminalSubscription();

        _rssiCtrl.add(null);
        _batteryPercentCtrl.add(null);
        _chargingCtrl.add(null);

        if (!completer.isCompleted) {
          completer.completeError(
            Exception("Disconnected before setup completed"),
          );
        }
      }
    }, onError: (e) {
      log("Connection error: $e");
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  Future<void> eraseNand(String deviceId) async {
    final qc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: timeServiceUuid,
      characteristicId: timeCharUuid,
    );
    await _ble.writeCharacteristicWithResponse(qc, value: const [0x01]);
    log("TX: wrote 0x01 (erase NAND)");
  }

  Future<void> startTransmit(String deviceId) async {
    final qc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: timeServiceUuid,
      characteristicId: timeCharUuid,
    );
    await _ble.writeCharacteristicWithResponse(qc, value: const [0x02]);
    log("TX: wrote 0x02 (burst transmit)");
  }

// transmit recent data
  Future<void> startTransmitRecent(String deviceId) async {
    final qc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: timeServiceUuid,
      characteristicId: timeCharUuid,
    );

    await _ble.writeCharacteristicWithResponse(qc, value: const [0x04]);
    log("TX: wrote 0x04 (recent transmit)");
  }

  Future<void> startCalibration(String deviceId) async {
    final qc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: timeServiceUuid,
      characteristicId: timeCharUuid,
    );
    await _ble.writeCharacteristicWithResponse(qc, value: const [0x03]);
    log("TX: wrote 0x03 (set baseline)");
  }

  Future<void> disconnect() async {
    log("Disconnect requested");

    stopRssiPolling();
    await stopBatteryAndChargingSubscriptions();
    await stopTerminalSubscription();

    await _connSub?.cancel();
    _connSub = null;

    connectedDeviceId = null;
    _lastConnState = DeviceConnectionState.disconnected;

    _rssiCtrl.add(null);
    _batteryPercentCtrl.add(null);
    _chargingCtrl.add(null);
  }

  void startRssiPolling({Duration period = const Duration(seconds: 1)}) {
    final id = connectedDeviceId;
    if (id == null) return;

    _rssiTimer?.cancel();
    _rssiCtrl.add(null);

    _rssiTimer = Timer.periodic(period, (_) async {
      final curId = connectedDeviceId;
      if (curId == null) return;

      try {
        final rssi = await _ble.readRssi(curId);
        _rssiCtrl.add(rssi);
      } catch (_) {
        _rssiCtrl.add(null);
      }
    });
  }

  void stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
    _rssiCtrl.add(null);
  }

  Future<void> readBatteryOnce(String deviceId) async {
    final qc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _basService,
      characteristicId: _basLevelChar,
    );

    try {
      final data = await _ble.readCharacteristic(qc);
      if (data.isNotEmpty) {
        final p = data[0].clamp(0, 100);
        _batteryPercentCtrl.add(p);
      }
    } catch (_) {
      _batteryPercentCtrl.add(null);
    }
  }

  void startBatteryAndChargingSubscriptions(String deviceId) {
    final battQc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _basService,
      characteristicId: _basLevelChar,
    );

    _batteryNotifySub?.cancel();
    _batteryNotifySub = _ble.subscribeToCharacteristic(battQc).listen(
      (data) {
        if (data.isEmpty) return;
        _batteryPercentCtrl.add(data[0].clamp(0, 100));
      },
      onError: (_) => _batteryPercentCtrl.add(null),
    );

    readBatteryOnce(deviceId);

    final chgQc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _powerService,
      characteristicId: _chargingChar,
    );

    _chargingNotifySub?.cancel();
    _chargingNotifySub = _ble.subscribeToCharacteristic(chgQc).listen(
      (data) {
        if (data.isEmpty) return;
        _chargingCtrl.add(data[0] == 1);
      },
      onError: (_) => _chargingCtrl.add(null),
    );
  }

  Future<void> stopBatteryAndChargingSubscriptions() async {
    await _batteryNotifySub?.cancel();
    await _chargingNotifySub?.cancel();
    _batteryNotifySub = null;
    _chargingNotifySub = null;
  }

  void startTerminalSubscription(String deviceId) {
    final qc = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: bleprintServiceUuid,
      characteristicId: bleprintCharUuid,
    );

    _terminalNotifySub?.cancel();
    _terminalNotifySub = _ble.subscribeToCharacteristic(qc).listen(
      (data) {
        if (data.isEmpty) return;

        final text = String.fromCharCodes(data);
        final lines = text.replaceAll('\r', '').split('\n');

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith("LIVE,")) {
            final parts = trimmed.split(',');
            if (parts.length >= 2) {
              final z = double.tryParse(parts[1]);
              if (z != null) {
                _liveImpedanceCtrl.add(z);
              }
            }
          }

          _logCtrl.add(trimmed);
        }
      },
      onError: (e) {
        log("Terminal subscribe error: $e");
      },
    );
  }

  Future<void> stopTerminalSubscription() async {
    await _terminalNotifySub?.cancel();
    _terminalNotifySub = null;
  }

  Future<void> dispose() async {
    stopRssiPolling();
    await stopScan();
    await disconnect();

    await _devicesCtrl.close();
    await _rssiCtrl.close();
    await _batteryPercentCtrl.close();
    await _chargingCtrl.close();
    await _liveImpedanceCtrl.close();
    await _logCtrl.close();
  }
}