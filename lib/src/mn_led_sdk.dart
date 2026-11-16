import 'mn_channel.dart';
import 'mn_result.dart';

/// LED destination signs, reached over RS485.
///
/// Call [getRouteList] at least once before [switchRoute] or
/// [triggerStopAnnouncement]. The SDK keeps no operational state: the app
/// tracks the route index, direction, stop index and arrival flag itself.
class MnLedSdk {
  MnLedSdk._();

  static final MnLedSdk instance = MnLedSdk._();

  /// Sign address that targets every sign, for [sendLedDisplay].
  static const int allSigns = 255;

  /// Binds the LED service and opens the serial port.
  ///
  /// The default node is for P7 / P20; P20A uses `/dev/ttyS4` for RS485.
  Future<MnResult> init({String path = '/dev/ttyS5', int baudRate = 38400}) =>
      mnInvoke<String>('led.init', {
        'path': path,
        'baudRate': baudRate,
      }).then(MnResult.fromJson);

  Future<MnResult> release() => mnCall('led.release');

  Future<String> getSdkVersion() async =>
      await mnInvoke<String>('led.getSdkVersion') ?? '';

  /// Routes read from `RouteInformation.csv` on the device.
  ///
  /// `data.routeList`: `filePath`, `index`, `name`, `goStations`,
  /// `backStations`. `data.warnings` lists missing route sub-files. Code -4
  /// means the config folder was never imported.
  Future<MnResult> getRouteList() => mnCall('led.getRouteList');

  /// `data.nonOpList`: `{index, name}` entries such as "Out of Service".
  Future<MnResult> getNonOpStatusList() => mnCall('led.getNonOpStatusList');

  /// Switches the active route and refreshes the signs.
  ///
  /// [index] comes from [getRouteList]; [direction]: 0 up / inbound, 1 down /
  /// outbound.
  Future<MnResult> switchRoute({required int index, int direction = 0}) =>
      mnCall('led.switchRoute', {'index': index, 'direction': direction});

  /// Drives the external signs and the internal screen for one stop.
  ///
  /// Code 201 means [stopIndex] ran past the end of the route.
  Future<MnResult> triggerStopAnnouncement({
    required int index,
    required int direction,
    required int stopIndex,
    required bool isArrival,
  }) => mnCall('led.triggerStopAnnouncement', {
    'index': index,
    'direction': direction,
    'stopIndex': stopIndex,
    'isArrival': isArrival,
  });

  /// Sends route and station text to a sign.
  ///
  /// [addr]: 1 front, 2 rear, 3 side, [allSigns] for every sign.
  Future<MnResult> sendLedDisplay({
    required int addr,
    required String routeName,
    required String languageUR,
    required String languageEN,
  }) => mnCall('led.sendLedDisplay', {
    'addr': addr,
    'routeName': routeName,
    'languageUR': languageUR,
    'languageEN': languageEN,
  });

  /// Sends a pre-built `Region.bin` image at [filePath] to sign [addr].
  Future<MnResult> sendImageRegion({
    required int addr,
    required String filePath,
  }) => mnCall('led.sendImageRegion', {'addr': addr, 'filePath': filePath});
}
