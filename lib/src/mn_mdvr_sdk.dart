import 'dart:typed_data';

import 'mn_channel.dart';
import 'mn_models.dart';
import 'mn_result.dart';

/// The MDVR host, reached over RS232: host GPS, passenger counting, stop
/// announcements, routes, calls, camera channels, alarms and calibration.
class MnMdvrSdk {
  MnMdvrSdk._();

  static final MnMdvrSdk instance = MnMdvrSdk._();

  /// Frame tail for the host channel, see [sendFrame].
  static const int hostChannel = 0xFF;

  /// Frame tail for the station channel, see [sendFrame].
  static const int stationChannel = 0xFE;

  // ------------------------------------------------------------ init & device

  /// Binds the MDVR service and opens the serial port. Must be called before
  /// any other method.
  ///
  /// The default node is for P7 / P20; P20A uses `/dev/ttyS8` for the aviation
  /// RS232 connector.
  Future<MnResult> init({String path = '/dev/ttyS4', int baudRate = 19200}) =>
      mnInvoke<String>('mdvr.init', {
        'path': path,
        'baudRate': baudRate,
      }).then(MnResult.fromJson);

  /// Unbinds the service and removes every listener registered in the SDK.
  ///
  /// Streams of this class stop receiving data; listen to them again after the
  /// next [init].
  Future<MnResult> release() => mnCall('mdvr.release');

  Future<String> getSdkVersion() async =>
      await mnInvoke<String>('mdvr.getSdkVersion') ?? '';

  /// `data.mdvr_device_identifier`: host hardware serial number.
  Future<MnResult> getDeviceIdentifier() =>
      mnCall('mdvr.getMdvrDeviceIdentifier');

  /// `data`: `boot`, `kernel`, `rootfs`, `app1`..`app3`, `blackbox`,
  /// `resource`, `mcu`. Waits up to 10 s.
  Future<MnResult> getVersion() => mnCall('mdvr.getMdvrVersion');

  /// Sends a reboot command to the host; does not wait for the restart.
  Future<MnResult> reboot() => mnCall('mdvr.rebootMdvr');

  // ---------------------------------------------------------------- GPS & CAN

  /// Host GPS frames. `data`: `time`, `date`, `lat`, `lng` (hex-encoded, see
  /// vendor docs), `speed`, `bearing`, `posStatus`, `acc`, `csq`, ...
  late final Stream<MnResult> gpsUpdates = mnResultEvents('mdvr.gps');

  /// CAN frames passed through by the host. `data`: `channel`, `canId`, `data`
  /// (hex strings).
  late final Stream<MnResult> canData = mnResultEvents('mdvr.can');

  // ----------------------------------------------------------- passenger flow

  /// `data`: `doorCount`, `doorStats` (`upCount`, `downCount`), `totalInside`.
  Future<MnResult> getApcInfo() => mnCall('mdvr.getMdvrApcInfo');

  /// Passenger-flow pushes, same `data` as [getApcInfo].
  late final Stream<MnResult> apcUpdates = mnResultEvents('mdvr.apc');

  // --------------------------------------------------------------- driver MIC

  /// [micType]: 0 internal, 1 external.
  Future<MnResult> openDriveMic({int micType = 0}) =>
      mnCall('mdvr.openDriveMic', {'mic_type': micType});

  Future<MnResult> closeDriveMic() => mnCall('mdvr.closeDriveMic');

  /// [volume]: 0–10.
  Future<MnResult> setDriveMicVolume(int volume) =>
      mnCall('mdvr.setDriveMicVolume', {'volume': volume});

  // ---------------------------------------------------------- call & intercom

  /// Code 200 means the dial command was delivered, not that the call is
  /// connected; follow [dialState] for that.
  Future<MnResult> dial(String phone) => mnCall('mdvr.dial', {'phone': phone});

  Future<MnResult> acceptDial() => mnCall('mdvr.acceptDial');

  Future<MnResult> dialOff() => mnCall('mdvr.dialOff');

  /// Call state. `data.status`: 0xA5 incoming, 0xA7 connected, 0xA6 hung up,
  /// 0x01 intercom started. `data.phoneNumber` may be null.
  late final Stream<MnResult> dialState = mnResultEvents('mdvr.dial');

  // ------------------------------------------- announcements / routes / voice

  /// Announces the next stop.
  Future<MnResult> switchNext() => mnCall('mdvr.switchNext');

  /// Moves the announcement to the next stop, or to the previous one when
  /// [next] is `false`.
  Future<MnResult> switchStop({required bool next}) =>
      mnCall('mdvr.switchStop', {'switch': next ? 1 : 0});

  Future<MnResult> switchRoute(int index) =>
      mnCall('mdvr.switchRoute', {'index': index});

  /// `data`: `direction`, `version`, `index`, `stationCount`, `routeInfo` and
  /// the per-channel volumes.
  Future<MnResult> queryRouteStatus() => mnCall('mdvr.queryRouteStatus');

  /// Route-status pushes, throttled to one per second. Fields the hardware has
  /// not reported yet are omitted.
  late final Stream<MnResult> routeStatus = mnResultEvents('mdvr.routeStatus');

  /// `data.count`.
  Future<MnResult> getRouteCount() => mnCall('mdvr.getRouteCount');

  Future<MnResult> queryRouteInfo(int index) =>
      mnCall('mdvr.queryRouteInfo', {'index': index});

  /// `data`: list of `{index, stationName}` for the current route.
  Future<MnResult> queryStopInfo() => mnCall('mdvr.queryStopInfo');

  /// Plays the pre-recorded service phrase [key] (0–9).
  Future<MnResult> playServiceVoice(int key) =>
      mnCall('mdvr.playServiceVoice', {'key': '$key'});

  Future<MnResult> stopServiceVoice() => mnCall('mdvr.stopServiceVoice');

  /// Replays the latest arrival/departure announcement.
  Future<MnResult> replayVoice() => mnCall('mdvr.replayVoice');

  // ---------------------------------------------------------- camera channels

  /// Shows analog [channels] (1–20). The host picks the layout from their
  /// count: full screen, 4-split or 9-grid.
  Future<MnResult> switchAnalogChannels(List<int> channels) => mnInvoke<String>(
    'mdvr.switchAnalogChannels',
    {'channels': Int32List.fromList(channels)},
  ).then(MnResult.fromJson);

  Future<MnResult> switchIpcChannel(int index) => mnInvoke<String>(
    'mdvr.switchIpcChannel',
    {'index': index},
  ).then(MnResult.fromJson);

  Future<MnResult> resetToDefaultChannel() =>
      mnCall('mdvr.resetToDefaultChannel');

  // ------------------------------------------------------ host status & pushes

  /// Raw host information string in `data`. Waits up to 4 s.
  Future<MnResult> queryHostInfo() => mnCall('mdvr.queryHostInfo');

  /// Summary status; the `data` layout is defined by the host protocol.
  Future<MnResult> queryHostStatus() => mnCall('mdvr.queryHostStatus');

  Future<MnResult> queryHostDetailStatus() =>
      mnCall('mdvr.queryHostDetailStatus');

  /// Host working status, pushed about every 8 s.
  late final Stream<MnResult> hostDetailStatus = mnResultEvents(
    'mdvr.hostDetailStatus',
  );

  /// UPS data. `data`: `powerVoltage`, `upsVoltage`, `temperature`,
  /// `batteryLevel`, `smartStatus`, ...
  late final Stream<MnResult> upsUpdates = mnResultEvents('mdvr.ups');

  /// Prompt messages from the host. `data.first`: command code, `data.second`:
  /// message text.
  late final Stream<MnResult> displayMessages = mnResultEvents(
    'mdvr.displayMsg',
  );

  /// Active-safety alarms. `data.alarm`: 0 muted, 1 sounding. `data.alarmType`:
  /// 0x01–0x08 DSM, 0x11–0x15 ADAS, 0x21 BSD.
  late final Stream<MnResult> alarms = mnResultEvents('mdvr.alarm');

  // ---------------------------------------------------- driver handle & trips

  /// Stores the driver handle (remote-control) status on the host.
  Future<MnResult> storeHandleStatus({
    required int driverKeyStatus,
    required String driverKeyTime,
    required int driverSignStatus,
    required String driverSignTime,
  }) => mnCall('mdvr.storeHandleStatus', {
    'driverKeyStatus': driverKeyStatus,
    'driverKeyTime': driverKeyTime,
    'driverSignStatus': driverSignStatus,
    'driverSignTime': driverSignTime,
  });

  /// `data`: `keyStatus`, `keyTime`, `logStatus`, `logTime`.
  Future<MnResult> queryHandleStatus() => mnCall('mdvr.queryHandleStatus');

  /// Driver sign-in / sign-out. The parameter format is defined by the host
  /// protocol and not fixed by the vendor documentation, so [params] is sent
  /// as-is.
  Future<MnResult> driverAttendance(Map<String, Object?> params) =>
      mnCall('mdvr.driverAttendance', params);

  /// Marks the start of a trip (departure notice, driving-key state, optional
  /// TTS). [time] is `HH:mm`; [direction]: 0 up, 1 down; [lineFlag]: 1
  /// operating route, 0 not operating.
  Future<MnResult> startTrip({
    required String time,
    int direction = 0,
    int lineFlag = 1,
    String? ttsText,
    int? driverSignStatus,
    String? driverSignTime,
  }) => mnCall(
    'mdvr.startTrip',
    _tripParams(
      time,
      direction,
      lineFlag,
      ttsText,
      driverSignStatus,
      driverSignTime,
    ),
  );

  /// Marks the end of a trip. Same parameters as [startTrip].
  Future<MnResult> endTrip({
    required String time,
    int direction = 0,
    int lineFlag = 1,
    String? ttsText,
    int? driverSignStatus,
    String? driverSignTime,
  }) => mnCall(
    'mdvr.endTrip',
    _tripParams(
      time,
      direction,
      lineFlag,
      ttsText,
      driverSignStatus,
      driverSignTime,
    ),
  );

  static Map<String, Object?> _tripParams(
    String time,
    int direction,
    int lineFlag,
    String? ttsText,
    int? driverSignStatus,
    String? driverSignTime,
  ) => {
    'direction': direction,
    'lineFlag': lineFlag,
    'time': time,
    'ttsText': ?ttsText,
    'driverSignStatus': ?driverSignStatus,
    'driverSignTime': ?driverSignTime,
  };

  /// Low-level primitive behind the trip methods; [status] is the raw protocol
  /// byte (1 = leave the operating state).
  Future<MnResult> setHostOperatingStatus(int status) =>
      mnCall('mdvr.setHostOperatingStatus', {'status': status});

  // ------------------------------------------------------------ SMS & contacts

  /// [index] starts at 1.
  Future<MnResult> querySmsContent(int index) =>
      mnCall('mdvr.querySmsContent', {'index': index});

  /// [index] starts at 1.
  Future<MnResult> deleteSmsContent(int index) =>
      mnCall('mdvr.deleteSmsContent', {'index': index});

  Future<MnResult> deleteAllSms() => mnCall('mdvr.deleteAllSms');

  Future<MnResult> queryContacts() => mnCall('mdvr.queryContacts');

  /// Sends [text] to the dispatch center through the host (GB2312-encoded).
  Future<MnResult> sendSmsText(String text) =>
      mnCall('mdvr.sendSmsText', {'text': text});

  /// Asks the host to read [text] aloud (GB2312-encoded).
  Future<MnResult> sendTtsText(String text) =>
      mnCall('mdvr.sendTtsText', {'text': text});

  /// Sends a simulated speed in km/h, e.g. to trigger an overspeed event.
  Future<MnResult> sendSimulatedSpeed(int speed) =>
      mnCall('mdvr.sendSimulatedSpeed', {'speed': speed});

  // -------------------------------------------------------------- calibration

  /// `data`: `vehicleWidth`, `cameraToVehicle`, `mountHeight`, `cameraBump`,
  /// `coordX`, `coordY`.
  Future<MnResult> queryAdasInfo() => mnCall('mdvr.queryAdasInfo');

  /// [vehicleWidth], [cameraToVehicle] and [mountHeight] must be non-zero.
  /// `data.result`: 1 success, 2 failure.
  Future<MnResult> setAdasCalib({
    required int vehicleWidth,
    required int cameraToVehicle,
    required int mountHeight,
    int cameraBump = 0,
    int coordX = 0,
    int coordY = 0,
  }) => mnCall('mdvr.setAdasCalib', {
    'vehicleWidth': vehicleWidth,
    'cameraToVehicle': cameraToVehicle,
    'mountHeight': mountHeight,
    'cameraBump': cameraBump,
    'coordX': coordX,
    'coordY': coordY,
  });

  /// `data.angleOfPitch`.
  Future<MnResult> queryDsmInfo() => mnCall('mdvr.queryDsmInfo');

  /// `data.result`: 1 success, 2 failure.
  Future<MnResult> setDsmCalib() => mnCall('mdvr.setDsmCalib');

  /// One-way setting: code 200 only means the command was sent.
  Future<MnResult> setBsdParam({
    required int cameraHeight,
    required int lv1Distance,
    required int lv2Distance,
    required int lv3Distance,
  }) => mnCall('mdvr.setBsdParam', {
    'cameraHeight': cameraHeight,
    'lv1distance': lv1Distance,
    'lv2distance': lv2Distance,
    'lv3distance': lv3Distance,
  });

  /// One-way setting: code 200 only means the command was sent.
  Future<MnResult> setBsdCalib(int yCoord) =>
      mnCall('mdvr.setBsdCalib', {'yCoord': yCoord});

  /// Requests a calibration photo from the host. Progress and the resulting
  /// file path arrive on [calibPhotoEvents]; listen to it before calling.
  ///
  /// [calibrationType]: 2 ADAS, 1 DSM.
  Future<void> requestCalibPhoto({int calibrationType = 2}) => mnInvoke<void>(
    'mdvr.requestCalibPhoto',
    {'arg': '{"calibrationType":$calibrationType}'},
  );

  late final Stream<CalibPhotoEvent> calibPhotoEvents = mnRawEvents(
    'mdvr.calibPhoto',
  ).map(CalibPhotoEvent.fromEvent);

  // ---------------------------------------------------------------- raw frame

  /// Sends a raw command frame, for protocol commands without a dedicated
  /// method. Header, length, checksum and tail are built by the SDK.
  /// Fire-and-forget: no response is parsed.
  ///
  /// [type] is the one-byte command code; [endType] is [hostChannel] or
  /// [stationChannel].
  Future<void> sendFrame(
    int type, {
    List<int>? data,
    int endType = hostChannel,
  }) => mnInvoke<void>('mdvr.sendFrame', {
    'type': type,
    'data': data == null ? null : Uint8List.fromList(data),
    'endType': endType,
  });
}
