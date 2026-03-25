import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Time sync + transmit command
final Uuid timeServiceUuid =
    Uuid.parse("9f2a6e30-4c9d-4f88-b7d3-9b2d7a3a1a11");

final Uuid timeCharUuid =
    Uuid.parse("9f2a6e31-4c9d-4f88-b7d3-9b2d7a3a1a11");

/// Terminal / CSV output from firmware
final Uuid bleprintServiceUuid =
    Uuid.parse("2f3a1001-2b7a-4c2a-9d2b-7a1c6d8b2a01");

final Uuid bleprintCharUuid =
    Uuid.parse("2f3a1002-2b7a-4c2a-9d2b-7a1c6d8b2a01");