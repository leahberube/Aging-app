import 'dart:typed_data';

List<int> int64ToLittleEndianBytes(int value) {
  final bd = ByteData(8);
  bd.setInt64(0, value, Endian.little);
  return bd.buffer.asUint8List();
}