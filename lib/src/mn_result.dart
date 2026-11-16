import 'dart:convert';

/// Status codes used by the vendor SDK in the `code` field of every result.
abstract final class MnCode {
  /// The call succeeded.
  static const int success = 200;

  /// A business status rather than an error, e.g. the stop index ran past the
  /// end of the route in `MnLedSdk.triggerStopAnnouncement`.
  static const int businessStatus = 201;

  /// The SDK is not connected to the MnSdk Service APK (check `init`).
  static const int notConnected = -1;

  /// Cross-process exception, invalid parameter or internal logic error.
  static const int remoteError = -2;

  /// The hardware did not answer in time (typically no reply on the serial port).
  static const int timeout = -3;

  /// A configuration file or folder is missing on the device.
  static const int fileNotFound = -4;
}

/// The unified `{code, msg, data}` result returned by the vendor SDK.
class MnResult {
  const MnResult({required this.code, this.msg = '', this.data, this.raw});

  /// Parses the JSON string delivered by the SDK. Never throws: an empty or
  /// malformed payload becomes a [MnCode.remoteError] result.
  factory MnResult.fromJson(String? json) {
    if (json == null || json.isEmpty) {
      return const MnResult(code: MnCode.remoteError, msg: 'Empty response');
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return MnResult(
          code: (decoded['code'] as num?)?.toInt() ?? MnCode.remoteError,
          msg: decoded['msg']?.toString() ?? '',
          data: decoded['data'],
          raw: json,
        );
      }
    } on FormatException {
      // Fall through to the malformed-payload result below.
    }
    return MnResult(
      code: MnCode.remoteError,
      msg: 'Malformed response',
      raw: json,
    );
  }

  /// Status code, see [MnCode].
  final int code;

  /// Result description or error message.
  final String msg;

  /// Business data: a `Map`, a `List`, a primitive or `null`.
  final Object? data;

  /// The JSON string exactly as the SDK produced it.
  final String? raw;

  bool get isSuccess => code == MnCode.success;

  /// [data] as a JSON object, or an empty map when it is not one.
  Map<String, dynamic> get dataMap {
    final value = data;
    return value is Map
        ? value.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  /// [data] as a JSON array, or an empty list when it is not one.
  List<dynamic> get dataList {
    final value = data;
    return value is List ? value : const <dynamic>[];
  }

  @override
  String toString() =>
      raw ?? jsonEncode({'code': code, 'msg': msg, 'data': data});
}
