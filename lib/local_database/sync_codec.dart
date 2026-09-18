import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class SyncCodec {
  static String encode(Map<String, dynamic> data) => jsonEncode(_encode(data));

  static Map<String, dynamic> decode(String value) =>
      Map<String, dynamic>.from(_decode(jsonDecode(value)) as Map);

  static dynamic _encode(dynamic value) {
    if (value is Timestamp) {
      return {
        '__firestore_timestamp__': [value.seconds, value.nanoseconds],
      };
    }
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key as String, _encode(entry)));
    }
    if (value is List) return value.map(_encode).toList();
    return value;
  }

  static dynamic _decode(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value.containsKey('__firestore_timestamp__')) {
        final parts = value['__firestore_timestamp__'] as List;
        return Timestamp(parts[0] as int, parts[1] as int);
      }
      return value.map((key, entry) => MapEntry(key as String, _decode(entry)));
    }
    if (value is List) return value.map(_decode).toList();
    return value;
  }
}
