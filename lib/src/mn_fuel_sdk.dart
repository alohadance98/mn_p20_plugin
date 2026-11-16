import 'mn_channel.dart';
import 'mn_result.dart';

/// Fuel-level sensor, reached over a serial port.
///
/// The vendor ships no documentation for this SDK; the API mirrors
/// `MnFuelSdk-1.0.0.aar` and the vendor demo.
class MnFuelSdk {
  MnFuelSdk._();

  static final MnFuelSdk instance = MnFuelSdk._();

  /// Binds the fuel service and opens the serial port.
  Future<MnResult> init({String path = '/dev/ttyS5', int baudRate = 9600}) =>
      mnInvoke<String>('fuel.init', {
        'path': path,
        'baudRate': baudRate,
      }).then(MnResult.fromJson);

  /// Unbinds the service. Listen to [fuelLevel] again after the next [init].
  Future<MnResult> release() => mnCall('fuel.release');

  Future<String> getSdkVersion() async =>
      await mnInvoke<String>('fuel.getSdkVersion') ?? '';

  /// Queries the current fuel level once.
  Future<MnResult> queryFuelLevel() => mnCall('fuel.requestUpdate');

  /// Sends a custom command as a hex string, e.g. `"11223344"`.
  Future<MnResult> sendCustomCommand(String hexCommand) =>
      mnCall('fuel.sendCustomCommand', hexCommand);

  /// Fuel-level change pushes.
  late final Stream<MnResult> fuelLevel = mnResultEvents('fuel.level');
}
