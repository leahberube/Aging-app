import 'package:flutter/material.dart';

import 'ble/ble_service.dart';
import 'ble/notification_service.dart';
import 'pages/scan_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final BleService ble = BleService();

  @override
  void dispose() {
    ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Dashboard',
      home: ScanPage(ble: ble),
    );
  }
}