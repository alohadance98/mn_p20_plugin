import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'mn_result.dart';

const String _channelName = 'com.mn.plugin';

const MethodChannel _methods = MethodChannel('$_channelName/methods');
const EventChannel _events = EventChannel('$_channelName/events');

Stream<Map<Object?, Object?>>? _sharedEvents;

/// Every push from the native side, as one shared broadcast stream.
Stream<Map<Object?, Object?>> get _allEvents => _sharedEvents ??= _events
    .receiveBroadcastStream()
    .map((event) => event as Map<Object?, Object?>);

/// Invokes a vendor method that answers with a `{code, msg, data}` JSON string.
///
/// [arg] is forwarded as the vendor `paramJson`: a `Map` is JSON-encoded, a
/// `String` is passed through unchanged.
Future<MnResult> mnCall(String method, [Object? arg]) async {
  final json = await _methods.invokeMethod<String>(method, {
    if (arg != null) 'arg': arg is String ? arg : jsonEncode(arg),
  });
  return MnResult.fromJson(json);
}

/// Invokes a method with raw (non-JSON) arguments and returns its raw reply.
Future<T?> mnInvoke<T>(String method, [Map<String, Object?>? arguments]) =>
    _methods.invokeMethod<T>(method, arguments);

/// Pushes tagged [event] that the native side emits without a registration
/// step (CAN frames, calibration-photo progress).
Stream<Map<Object?, Object?>> mnRawEvents(String event) =>
    _allEvents.where((payload) => payload['event'] == event);

/// Pushes tagged [event], backed by a native listener that is registered when
/// the first Dart listener subscribes and unregistered when the last one leaves.
Stream<Map<Object?, Object?>> mnSubscribedEvents(String event) {
  late final StreamController<Map<Object?, Object?>> controller;
  StreamSubscription<Map<Object?, Object?>>? upstream;

  controller = StreamController<Map<Object?, Object?>>.broadcast(
    onListen: () {
      // Listen on the event channel first so no push is lost, then register.
      upstream = mnRawEvents(event)
          .listen(controller.add, onError: controller.addError);
      _methods
          .invokeMethod<void>('subscribe', {'event': event})
          .catchError(controller.addError);
    },
    onCancel: () async {
      try {
        await _methods.invokeMethod<void>('unsubscribe', {'event': event});
      } on PlatformException {
        // Nothing useful to do if the native side is already gone.
      } on MissingPluginException {
        // Same: the engine is shutting down.
      }
      await upstream?.cancel();
      upstream = null;
    },
  );
  return controller.stream;
}

/// [mnSubscribedEvents] for listeners whose pushes are `{code, msg, data}` JSON.
Stream<MnResult> mnResultEvents(String event) =>
    mnSubscribedEvents(event)
        .map((payload) => MnResult.fromJson(payload['json'] as String?));
