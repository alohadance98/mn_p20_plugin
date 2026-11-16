import 'package:material_ui/material_ui.dart';
import 'package:mn_p20_plugin/mn_p20_plugin.dart';

/// Live camera preview with channel switching, like the vendor demo's
/// "Camera" and "MDVR Camera" screens.
///
/// The top row picks which P20 video input is shown. The MDVR section tells
/// the MDVR host which of its own channels to output; it needs
/// `MnMdvrSdk.init` (see the MDVR tab) to have succeeded first.
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const _splits = <String, List<int>>{
    'CH1-4': [1, 2, 3, 4],
    'CH5-8': [5, 6, 7, 8],
    'CH9-12': [9, 10, 11, 12],
    'CH13-16': [13, 14, 15, 16],
    'CH17-20': [17, 18, 19, 20],
    'CH1-9': [1, 2, 3, 4, 5, 6, 7, 8, 9],
    'CH10-18': [10, 11, 12, 13, 14, 15, 16, 17, 18],
    'CH19-20': [19, 20],
  };

  final _mdvr = MnMdvrSdk.instance;

  /// Index of the P20 camera being shown, or null while the preview is off.
  int? _camera;
  String _status = '';

  Future<void> _mdvrCall(String label, Future<MnResult> Function() call) async {
    try {
      final result = await call();
      if (mounted) setState(() => _status = '$label -> $result');
    } catch (error) {
      if (mounted) setState(() => _status = '$label failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('P20 camera:'),
              for (var index = 0; index < 4; index++)
                ChoiceChip(
                  label: Text('CH${index + 1}'),
                  selected: camera == index,
                  onSelected: (selected) =>
                      setState(() => _camera = selected ? index : null),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: ColoredBox(
            color: Colors.black,
            child: camera == null
                ? const Center(
                    child: Text(
                      'Select a channel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : MnCameraView(
                    index: camera,
                    placeholder: const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '$error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MDVR output channel (requires MDVR init):'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var channel = 1; channel <= 20; channel++)
                      ActionChip(
                        label: Text('CH$channel'),
                        onPressed: () => _mdvrCall(
                          'CH$channel',
                          () => _mdvr.switchAnalogChannels([channel]),
                        ),
                      ),
                    for (final split in _splits.entries)
                      ActionChip(
                        label: Text(split.key),
                        onPressed: () => _mdvrCall(
                          split.key,
                          () => _mdvr.switchAnalogChannels(split.value),
                        ),
                      ),
                    for (var ipc = 1; ipc <= 4; ipc++)
                      ActionChip(
                        label: Text('IPC$ipc'),
                        onPressed: () => _mdvrCall(
                          'IPC$ipc',
                          () => _mdvr.switchIpcChannel(ipc),
                        ),
                      ),
                    ActionChip(
                      label: const Text('Default'),
                      onPressed: () =>
                          _mdvrCall('Default', _mdvr.resetToDefaultChannel),
                    ),
                  ],
                ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _status,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
