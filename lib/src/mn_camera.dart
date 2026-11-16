import 'package:flutter/widgets.dart';

import 'mn_channel.dart';

/// An open camera preview, rendered into a Flutter texture.
class MnCameraPreview {
  const MnCameraPreview({
    required this.textureId,
    required this.width,
    required this.height,
  });

  /// Id to pass to a [Texture] widget.
  final int textureId;

  /// Preview resolution in pixels.
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 16 / 9 : width / height;
}

/// Live preview of the terminal's video inputs.
///
/// On the P20 the camera channels (CH1..CH4) are ordinary Android cameras,
/// addressed by their position in the system camera list: channel 1 is index
/// 0. Use [MnCameraView] to show one; this class is the lower-level API.
abstract final class MnCamera {
  /// Asks for the CAMERA runtime permission if it is not granted yet.
  static Future<bool> requestPermission() async =>
      await mnInvoke<bool>('camera.requestPermission') ?? false;

  /// System camera ids, in channel order.
  static Future<List<String>> getCameraIds() async =>
      (await mnInvoke<List<Object?>>('camera.list') ?? const []).cast<String>();

  /// Opens the camera at [index] and starts its preview.
  ///
  /// Throws a `PlatformException` when the permission is missing
  /// (`MN_CAMERA_PERMISSION`), the index does not exist (`MN_CAMERA_NOT_FOUND`)
  /// or the camera fails to start (`MN_CAMERA_ERROR`).
  static Future<MnCameraPreview> open(int index) async {
    final info = (await mnInvoke<Map<Object?, Object?>>('camera.open', {
      'index': index,
    }))!;
    return MnCameraPreview(
      textureId: info['textureId'] as int,
      width: info['width'] as int,
      height: info['height'] as int,
    );
  }

  /// Stops the preview and releases the camera.
  static Future<void> close(MnCameraPreview preview) =>
      mnInvoke<void>('camera.close', {'textureId': preview.textureId});
}

/// Shows the live picture of camera [index] (0 = CH1).
///
/// The camera is opened when the widget is mounted, reopened when [index]
/// changes, and released when the widget is disposed. Only one camera is held
/// at a time, like the vendor demo.
class MnCameraView extends StatefulWidget {
  const MnCameraView({
    super.key,
    required this.index,
    this.placeholder,
    this.errorBuilder,
  });

  /// Position of the camera in the system camera list.
  final int index;

  /// Shown while the camera is opening.
  final Widget? placeholder;

  /// Builds the widget shown when the camera cannot be opened.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<MnCameraView> createState() => _MnCameraViewState();
}

class _MnCameraViewState extends State<MnCameraView> {
  MnCameraPreview? _preview;
  Object? _error;

  /// Serialises open/close so a quick channel switch never holds two cameras.
  Future<void> _pending = Future<void>.value();

  /// Bumped on every switch; an open that finishes late is discarded.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _switchTo(widget.index);
  }

  @override
  void didUpdateWidget(MnCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _switchTo(widget.index);
  }

  @override
  void dispose() {
    _generation++;
    final preview = _preview;
    _preview = null;
    _pending = _pending.then((_) async {
      if (preview != null) await _closeQuietly(preview);
    });
    super.dispose();
  }

  void _switchTo(int index) {
    final generation = ++_generation;
    final previous = _preview;
    setState(() {
      _preview = null;
      _error = null;
    });

    _pending = _pending.then((_) async {
      if (previous != null) await _closeQuietly(previous);
      if (generation != _generation) return;
      try {
        if (!await MnCamera.requestPermission()) {
          throw StateError('CAMERA permission denied');
        }
        final preview = await MnCamera.open(index);
        if (generation != _generation || !mounted) {
          await _closeQuietly(preview);
          return;
        }
        setState(() => _preview = preview);
      } catch (error) {
        if (generation == _generation && mounted) {
          setState(() => _error = error);
        }
      }
    });
  }

  static Future<void> _closeQuietly(MnCameraPreview preview) async {
    try {
      await MnCamera.close(preview);
    } catch (_) {
      // The engine may already be gone; there is nothing left to release.
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          Center(child: Text('$error', textAlign: TextAlign.center));
    }
    final preview = _preview;
    if (preview == null) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    return Center(
      child: AspectRatio(
        aspectRatio: preview.aspectRatio,
        child: Texture(textureId: preview.textureId),
      ),
    );
  }
}
