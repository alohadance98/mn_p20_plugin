import 'dart:convert';
import 'dart:typed_data';

/// A CAN frame received on a P20 CAN channel opened with `MnP20Sdk.canOpen`.
class CanFrame {
  const CanFrame({
    required this.port,
    required this.extended,
    required this.id,
    required this.data,
  });

  factory CanFrame.fromEvent(Map<Object?, Object?> event) => CanFrame(
    port: event['port'] as int,
    extended: event['type'] == 1,
    id: event['id'] as int,
    data: event['data'] as Uint8List? ?? Uint8List(0),
  );

  /// Channel index: 0 = CAN0, 1 = CAN1.
  final int port;

  /// `true` for an extended 29-bit identifier, `false` for a standard 11-bit one.
  final bool extended;

  /// CAN identifier.
  final int id;

  /// Payload bytes (up to 8).
  final Uint8List data;

  String get _hexData => data
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  @override
  String toString() =>
      'CanFrame(port: $port, extended: $extended, '
      'id: ${id.toRadixString(16).toUpperCase()}, data: $_hexData)';
}

/// An AI video alarm (DMS / ADAS / BSD) pushed by `MnP20Sdk.dsmAlarms`.
class DsmAlarm {
  const DsmAlarm({required this.info, this.infoJson, this.video});

  factory DsmAlarm.fromEvent(Map<Object?, Object?> event) {
    final infoJson = event['info'] as String?;
    Map<String, dynamic> info = const {};
    if (infoJson != null && infoJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(infoJson);
        if (decoded is Map) info = decoded.cast<String, dynamic>();
      } on FormatException {
        // Keep the empty map; the raw string stays available in [infoJson].
      }
    }
    return DsmAlarm(
      info: info,
      infoJson: infoJson,
      video: event['video'] as Uint8List?,
    );
  }

  /// Decoded alarm metadata (`time`, `category`, `type`, ...).
  final Map<String, dynamic> info;

  /// Alarm metadata exactly as the SDK delivered it.
  final String? infoJson;

  /// Raw bytes of the alarm video clip.
  final Uint8List? video;

  /// 0x01 DMS, 0x02 ADAS, 0x03 BSD.
  int? get category => (info['category'] as num?)?.toInt();

  /// Alarm type within [category]; see the vendor documentation table.
  int? get type => (info['type'] as num?)?.toInt();

  String? get time => info['time']?.toString();

  @override
  String toString() =>
      'DsmAlarm(info: $infoJson, video: ${video?.length ?? 0} bytes)';
}

enum CalibPhotoStatus { progress, success, error }

/// Progress of a calibration-photo transfer started with
/// `MnMdvrSdk.requestCalibPhoto`.
class CalibPhotoEvent {
  const CalibPhotoEvent({
    required this.status,
    this.progress,
    this.filePath,
    this.error,
  });

  factory CalibPhotoEvent.fromEvent(Map<Object?, Object?> event) =>
      CalibPhotoEvent(
        status: switch (event['status']) {
          'progress' => CalibPhotoStatus.progress,
          'success' => CalibPhotoStatus.success,
          _ => CalibPhotoStatus.error,
        },
        progress: event['progress'] as int?,
        filePath: event['filePath'] as String?,
        error: event['error'] as String?,
      );

  final CalibPhotoStatus status;

  /// Transfer progress in percent, set when [status] is progress.
  final int? progress;

  /// Path of the received photo on the device, set when [status] is success.
  final String? filePath;

  /// Failure description, set when [status] is error.
  final String? error;

  @override
  String toString() => switch (status) {
    CalibPhotoStatus.progress => 'CalibPhotoEvent(progress: $progress)',
    CalibPhotoStatus.success => 'CalibPhotoEvent(success: $filePath)',
    CalibPhotoStatus.error => 'CalibPhotoEvent(error: $error)',
  };
}
