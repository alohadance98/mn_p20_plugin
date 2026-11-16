import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mn_p20_plugin/mn_p20_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('com.mn.plugin/methods');
  const events = MethodChannel('com.mn.plugin/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  /// Delivers [payload] to Dart as if the native event sink had emitted it.
  Future<void> emit(Map<String, Object?> payload) =>
      messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(payload),
        (_) {},
      );

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'p20.getSdkVersion' => '1.3.1',
        'camera.requestPermission' => true,
        'camera.list' => ['0', '1'],
        'camera.open' => {'textureId': 7, 'width': 1280, 'height': 720},
        'camera.close' => null,
        'subscribe' || 'unsubscribe' || 'p20.canDataSend' => null,
        _ => '{"code":200,"msg":"success","data":{}}',
      };
    });
    messenger.setMockMethodCallHandler(events, (call) async => null);
  });

  group('MnResult', () {
    test('parses code, msg and data', () {
      final result = MnResult.fromJson(
        '{"code":200,"msg":"success","data":{"count":12}}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.msg, 'success');
      expect(result.dataMap['count'], 12);
    });

    test('exposes array data', () {
      final result = MnResult.fromJson(
        '{"code":200,"msg":"","data":[{"index":0}]}',
      );
      expect(result.dataList, hasLength(1));
      expect(result.dataMap, isEmpty);
    });

    test('turns empty or malformed payloads into an error result', () {
      expect(MnResult.fromJson(null).code, MnCode.remoteError);
      expect(MnResult.fromJson('not json').code, MnCode.remoteError);
      expect(MnResult.fromJson('[1]').code, MnCode.remoteError);
    });
  });

  group('method calls', () {
    test('typed parameters are sent as the vendor paramJson', () async {
      final result = await MnP20Sdk.instance.showSystemBar(
        statusBar: false,
        navigationBar: true,
      );

      expect(result.isSuccess, isTrue);
      expect(calls.single.method, 'p20.showSystemBar');
      expect(jsonDecode((calls.single.arguments as Map)['arg'] as String), {
        'show_status_bar': false,
        'show_navigation_bar': true,
      });
    });

    test('omitted optional switches are left out of the JSON', () async {
      await MnP20Sdk.instance.setFtDriveMode(ecoMode: false, powerMode: true);

      expect(jsonDecode((calls.single.arguments as Map)['arg'] as String), {
        'ecoMode': false,
        'powerMode': true,
      });
    });

    test('plain string arguments are passed through unchanged', () async {
      await MnP20Sdk.instance.execRootShell('ip link show can0');

      expect((calls.single.arguments as Map)['arg'], 'ip link show can0');
    });

    test('init forwards the serial port settings', () async {
      await MnMdvrSdk.instance.init(path: '/dev/ttyS8', baudRate: 19200);

      expect(calls.single.method, 'mdvr.init');
      expect(calls.single.arguments, {'path': '/dev/ttyS8', 'baudRate': 19200});
    });

    test('canSend maps the frame type and payload', () async {
      await MnP20Sdk.instance.canSend(
        port: 0,
        id: 0x18FEBF0B,
        extended: true,
        data: [1, 2],
      );

      final arguments = calls.single.arguments as Map;
      expect(arguments['type'], 1);
      expect(arguments['id'], 0x18FEBF0B);
      expect(arguments['data'], Uint8List.fromList([1, 2]));
    });

    test('getSdkVersion returns the raw string', () async {
      expect(await MnP20Sdk.instance.getSdkVersion(), '1.3.1');
    });
  });

  group('streams', () {
    test(
      'subscribe on listen, deliver matching events, unsubscribe on cancel',
      () async {
        final received = <MnResult>[];
        final subscription = MnP20Sdk.instance.nfcEvents.listen(received.add);
        await pumpEventQueue();

        expect(calls.where((c) => c.method == 'subscribe').single.arguments, {
          'event': 'p20.nfc',
        });

        await emit({
          'event': 'p20.nfc',
          'json': '{"code":200,"msg":"","data":{"nfc_card_no":"1234567890"}}',
        });
        await emit({'event': 'p20.io', 'json': '{"code":200,"data":{}}'});
        await pumpEventQueue();

        expect(received, hasLength(1));
        expect(received.single.dataMap['nfc_card_no'], '1234567890');

        await subscription.cancel();
        await pumpEventQueue();

        expect(calls.where((c) => c.method == 'unsubscribe').single.arguments, {
          'event': 'p20.nfc',
        });
      },
    );

    test('CAN frames are decoded', () async {
      final frames = <CanFrame>[];
      final subscription = MnP20Sdk.instance.canFrames.listen(frames.add);
      await pumpEventQueue();

      await emit({
        'event': 'p20.can',
        'port': 0,
        'type': 1,
        'id': 0x18FEBF0B,
        'data': Uint8List.fromList([0, 1, 2]),
      });
      await pumpEventQueue();

      expect(frames.single.extended, isTrue);
      expect(frames.single.id, 0x18FEBF0B);
      expect(frames.single.data, [0, 1, 2]);
      await subscription.cancel();
    });

    test('calibration photo events are decoded', () async {
      final photoEvents = <CalibPhotoEvent>[];
      final subscription = MnMdvrSdk.instance.calibPhotoEvents.listen(
        photoEvents.add,
      );
      await pumpEventQueue();

      await emit({
        'event': 'mdvr.calibPhoto',
        'status': 'progress',
        'progress': 40,
      });
      await emit({
        'event': 'mdvr.calibPhoto',
        'status': 'success',
        'filePath': '/sdcard/calib.jpg',
      });
      await pumpEventQueue();

      expect(photoEvents.first.progress, 40);
      expect(photoEvents.last.status, CalibPhotoStatus.success);
      expect(photoEvents.last.filePath, '/sdcard/calib.jpg');
      await subscription.cancel();
    });
  });

  group('camera', () {
    test('open returns the texture and close releases it', () async {
      expect(await MnCamera.requestPermission(), isTrue);
      expect(await MnCamera.getCameraIds(), ['0', '1']);

      final preview = await MnCamera.open(1);
      expect(preview.textureId, 7);
      expect(preview.aspectRatio, 1280 / 720);
      expect(calls.last.arguments, {'index': 1});

      await MnCamera.close(preview);
      expect(calls.last.method, 'camera.close');
      expect(calls.last.arguments, {'textureId': 7});
    });

    testWidgets('MnCameraView opens, switches and releases the camera', (
      tester,
    ) async {
      Widget view(int index) => Directionality(
        textDirection: TextDirection.ltr,
        child: MnCameraView(index: index),
      );
      List<Object?> of(String method) => [
        for (final call in calls)
          if (call.method == method) call.arguments,
      ];

      await tester.pumpWidget(view(0));
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsOneWidget);
      expect(of('camera.open'), [
        {'index': 0},
      ]);

      await tester.pumpWidget(view(2));
      await tester.pumpAndSettle();
      expect(of('camera.close'), hasLength(1));
      expect(of('camera.open').last, {'index': 2});

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(of('camera.close'), hasLength(2));
    });
  });
}
