import 'dart:typed_data';

import 'mn_channel.dart';
import 'mn_models.dart';
import 'mn_result.dart';

/// Local hardware of the P20 Android terminal: system bars, GPS, IO, NFC,
/// G-Sensor, TTS, speakers, CAN, network, DSM video alarms, TMS and firmware.
///
/// Binds the local P20 service of the MnSdk Service APK; no serial port needed.
class MnP20Sdk {
  MnP20Sdk._();

  static final MnP20Sdk instance = MnP20Sdk._();

  // ------------------------------------------------------------ init & version

  /// Binds the P20 hardware service. Must complete with code 200 before any
  /// other call.
  Future<MnResult> init() => mnCall('p20.init');

  /// Unbinds the service and removes every listener registered in the SDK.
  ///
  /// Streams of this class stop receiving data; listen to them again after the
  /// next [init].
  Future<MnResult> release() => mnCall('p20.release');

  /// Version of the vendor AAR itself (not the device firmware).
  Future<String> getSdkVersion() async =>
      await mnInvoke<String>('p20.getSdkVersion') ?? '';

  /// `data`: `android_version`, `firmware_version`, `device_version`.
  Future<MnResult> getVersion() => mnCall('p20.getVersion');

  /// `data.device_identifier`: Ethernet MAC address without colons.
  Future<MnResult> getDeviceIdentifier() =>
      mnCall('p20.getP20DeviceIdentifier');

  // --------------------------------------------------------- system & location

  /// Shows or hides the status bar and the navigation bar.
  Future<MnResult> showSystemBar({
    required bool statusBar,
    required bool navigationBar,
  }) => mnCall('p20.showSystemBar', {
    'show_status_bar': statusBar,
    'show_navigation_bar': navigationBar,
  });

  /// Local GPS fixes. `data`: `lat`, `lng`, `speed` (km/h), `bearing`, `alt`,
  /// `time` (ms), `accuracy`, `hdop`, `satellites`.
  late final Stream<MnResult> locationUpdates = mnResultEvents('p20.location');

  // --------------------------------------------------------- IO / NFC / sensor

  /// Turns the 5V output pin on or off.
  Future<MnResult> controlIoOut({required bool open}) =>
      mnCall('p20.controlIOOut', {'open': open});

  /// IO state changes. `data`: `acc`, `gpio1`..`gpio4`, `io5vOut`, each `"0"`
  /// or `"1"`.
  late final Stream<MnResult> ioStatus = mnResultEvents('p20.io');

  /// NFC card swipes. `data.nfc_card_no`.
  late final Stream<MnResult> nfcEvents = mnResultEvents('p20.nfc');

  /// Accelerometer readings in m/s². `data`: `x`, `y`, `z`.
  late final Stream<MnResult> gsensorData = mnResultEvents('p20.gsensor');

  // --------------------------------------------------------------- audio & TTS

  /// Enables the internal speaker (left channel) and/or the external speaker
  /// (right channel). The internal speaker is off after boot.
  Future<MnResult> setSpeaker({
    required bool internal,
    required bool external,
  }) => mnCall('p20.setP20Speaker', {
    'open_left': internal,
    'open_right': external,
  });

  /// Speaks [text] with the local TTS engine. Completes when playback
  /// finishes, not when the utterance is queued.
  ///
  /// [lang]: `en`, `ur` or `ar`. [speed]: 0.5–2.0.
  Future<MnResult> ttsSpeak(
    String text, {
    String lang = 'en',
    double speed = 1.0,
    double pitch = 1.0,
  }) => mnCall('p20.ttsSpeak', {
    'text': text,
    'lang': lang,
    'speed': speed,
    'pitch': pitch,
  });

  Future<MnResult> ttsStop() => mnCall('p20.ttsStop');

  // ----------------------------------------------------------------------- CAN

  /// Opens CAN channel [port] (0 = CAN0, 1 = CAN1) at [bitrate] bits per
  /// second (250000 or 500000). Received frames arrive on [canFrames].
  Future<void> canOpen(int port, int bitrate) =>
      mnInvoke<void>('p20.canOpen', {'port': port, 'bitrate': bitrate});

  Future<void> canClose(int port) =>
      mnInvoke<void>('p20.canClose', {'port': port});

  /// Sends one CAN frame. Fire-and-forget: delivery is not confirmed.
  Future<void> canSend({
    required int port,
    required int id,
    required List<int> data,
    bool extended = false,
  }) => mnInvoke<void>('p20.canDataSend', {
    'port': port,
    'type': extended ? 1 : 0,
    'id': id,
    'data': Uint8List.fromList(data),
  });

  /// Frames received on every channel opened with [canOpen].
  late final Stream<CanFrame> canFrames = mnRawEvents('p20.can')
      .map(CanFrame.fromEvent);

  // ------------------------------------------------- Foton driving-mode switch
  //
  // Requires canOpen(0, bitrate) first; every call below returns code -2 while
  // the channel is closed. `data`: `rainSnowMode`, `ecoMode`, `powerMode`,
  // `running`.

  /// Starts or stops the 100 ms periodic push of the soft-switch state. Start
  /// it once after [canOpen] and stop it when leaving the screen.
  Future<MnResult> initFtDriveMode({required bool enable}) =>
      mnCall('p20.initFtDriveMode', {'enable': enable});

  Future<MnResult> setFtRainSnowMode({required bool enable}) =>
      mnCall('p20.setFtRainSnowMode', {'enable': enable});

  /// Enabling economy mode turns power mode off in the same frame.
  Future<MnResult> setFtEcoMode({required bool enable}) =>
      mnCall('p20.setFtEcoMode', {'enable': enable});

  /// Enabling power mode turns economy mode off in the same frame.
  Future<MnResult> setFtPowerMode({required bool enable}) =>
      mnCall('p20.setFtPowerMode', {'enable': enable});

  /// Sets several switches in one frame. Omitted switches keep their value;
  /// [ecoMode] and [powerMode] cannot both be `true`.
  Future<MnResult> setFtDriveMode({
    bool? rainSnowMode,
    bool? ecoMode,
    bool? powerMode,
  }) => mnCall('p20.setFtDriveMode', {
    'rainSnowMode': ?rainSnowMode,
    'ecoMode': ?ecoMode,
    'powerMode': ?powerMode,
  });

  // ------------------------------------------------- storage / network / Wi-Fi

  /// `data`: `total`, `available`, `percentage`.
  Future<MnResult> getStorageInfo() => mnCall('p20.getStorageInfo');

  /// `data.status`: whether Ethernet is connected.
  Future<MnResult> testEth0() => mnCall('p20.testEth0');

  /// `data.status`: whether the cellular network is connected.
  Future<MnResult> test4G() => mnCall('p20.test4G');

  Future<MnResult> setEthDhcp({required bool dhcp}) =>
      mnCall('p20.setEthDhcp', {'dhcp': dhcp});

  /// Applies a static IPv4 configuration to Ethernet and disables DHCP.
  Future<MnResult> setStaticIpConfig({
    required String ip,
    required String subnetMask,
    required String gateway,
    required String dns,
  }) => mnCall('p20.setStaticIpConfig', {
    'static_ip': ip,
    'sub_net_mask': subnetMask,
    'gateway': gateway,
    'dns': dns,
  });

  /// Wi-Fi state, pushed on subscription and on every change. `data`:
  /// `enabled`, `connected`, `ssid`, `rssi`, `level`.
  late final Stream<MnResult> wifiStatus = mnResultEvents('p20.wifi');

  // ----------------------------------------------------------- DSM video alarm

  /// AI alarms (DMS / ADAS / BSD) with their video clip.
  late final Stream<DsmAlarm> dsmAlarms = mnSubscribedEvents('p20.dsm')
      .map(DsmAlarm.fromEvent);

  // ------------------------------------------------------------ device control

  /// Reboots the terminal immediately. No result is ever delivered.
  Future<void> rebootDevice() => mnInvoke<void>('p20.rebootDevice');

  /// Starts a full firmware upgrade from a package already on the device, e.g.
  /// `/storage/emulated/0/P20_Update.zip`. The device reboots; code 200 only
  /// means the request was dispatched. A package that does not match the
  /// device can leave it unbootable.
  Future<MnResult> upgradeFirmware(String path) =>
      mnCall('p20.upgradeFirmware', {'path': path});

  /// Runs [command] as root (do not prepend `su`). `data`: `cmd`, `result`
  /// (exit status), `success`.
  Future<MnResult> execRootShell(String command) =>
      mnCall('p20.execRootShell', command);

  // ----------------------------------------------------------------------- TMS

  /// `data`: `enable`, `serverUrl`, `deviceCode`.
  Future<MnResult> queryTmsState() => mnCall('p20.queryTmsState');

  /// Turns the remote-management client on or off, optionally switching to
  /// [serverUrl]. The state is not persisted across restarts.
  Future<MnResult> setTmsState({required bool enable, String? serverUrl}) =>
      mnCall('p20.setTmsState', {'enable': enable, 'serverUrl': ?serverUrl});
}
