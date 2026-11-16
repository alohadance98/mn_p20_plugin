import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:mn_p20_plugin/mn_p20_plugin.dart';

import 'camera_page.dart';

void main() => runApp(const ExampleApp());

/// One entry of a console: a named action, optionally with an editable
/// JSON parameter.
class Command {
  const Command(this.name, this.run, {this.param});

  final String name;
  final String? param;
  final Future<Object?> Function(Map<String, dynamic> param) run;
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MN P20 SDK',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('MN P20 SDK'),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'P20'),
                Tab(text: 'MDVR'),
                Tab(text: 'LED'),
                Tab(text: 'Fuel'),
                Tab(text: 'Camera'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              Console(commands: _p20Commands, streams: _p20Streams),
              Console(commands: _mdvrCommands, streams: _mdvrStreams),
              Console(commands: _ledCommands),
              Console(commands: _fuelCommands, streams: _fuelStreams),
              const CameraPage(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------- P20

final _p20 = MnP20Sdk.instance;

final List<Command> _p20Commands = [
  Command('init', (_) => _p20.init()),
  Command('release', (_) => _p20.release()),
  Command('getSdkVersion', (_) => _p20.getSdkVersion()),
  Command('getVersion', (_) => _p20.getVersion()),
  Command('getDeviceIdentifier', (_) => _p20.getDeviceIdentifier()),
  Command(
    'showSystemBar',
    (p) => _p20.showSystemBar(
      statusBar: p['statusBar'] as bool,
      navigationBar: p['navigationBar'] as bool,
    ),
    param: '{"statusBar": true, "navigationBar": true}',
  ),
  Command(
    'setSpeaker',
    (p) => _p20.setSpeaker(
      internal: p['internal'] as bool,
      external: p['external'] as bool,
    ),
    param: '{"internal": true, "external": true}',
  ),
  Command(
    'ttsSpeak',
    (p) => _p20.ttsSpeak(p['text'] as String, lang: p['lang'] as String),
    param: '{"text": "Hello, this is a TTS test", "lang": "en"}',
  ),
  Command('ttsStop', (_) => _p20.ttsStop()),
  Command(
    'controlIoOut',
    (p) => _p20.controlIoOut(open: p['open'] as bool),
    param: '{"open": true}',
  ),
  Command(
    'canOpen',
    (p) => _p20.canOpen(p['port'] as int, p['bitrate'] as int),
    param: '{"port": 0, "bitrate": 250000}',
  ),
  Command(
    'canSend',
    (p) => _p20.canSend(
      port: p['port'] as int,
      id: p['id'] as int,
      extended: p['extended'] as bool,
      data: (p['data'] as List).cast<int>(),
    ),
    param:
        '{"port": 0, "id": 419348235, "extended": true, '
        '"data": [0, 17, 34, 51, 68, 85, 102, 119]}',
  ),
  Command(
    'canClose',
    (p) => _p20.canClose(p['port'] as int),
    param: '{"port": 0}',
  ),
  Command(
    'initFtDriveMode',
    (p) => _p20.initFtDriveMode(enable: p['enable'] as bool),
    param: '{"enable": true}',
  ),
  Command(
    'setFtDriveMode',
    (p) => _p20.setFtDriveMode(
      rainSnowMode: p['rainSnowMode'] as bool?,
      ecoMode: p['ecoMode'] as bool?,
      powerMode: p['powerMode'] as bool?,
    ),
    param: '{"ecoMode": false, "powerMode": true}',
  ),
  Command('getStorageInfo', (_) => _p20.getStorageInfo()),
  Command('testEth0', (_) => _p20.testEth0()),
  Command('test4G', (_) => _p20.test4G()),
  Command(
    'setEthDhcp',
    (p) => _p20.setEthDhcp(dhcp: p['dhcp'] as bool),
    param: '{"dhcp": true}',
  ),
  Command(
    'setStaticIpConfig',
    (p) => _p20.setStaticIpConfig(
      ip: p['ip'] as String,
      subnetMask: p['subnetMask'] as String,
      gateway: p['gateway'] as String,
      dns: p['dns'] as String,
    ),
    param:
        '{"ip": "192.168.0.10", "subnetMask": "255.255.255.0", '
        '"gateway": "192.168.0.1", "dns": "8.8.8.8"}',
  ),
  Command(
    'execRootShell',
    (p) => _p20.execRootShell(p['cmd'] as String),
    param: '{"cmd": "ip -details -statistics link show can0"}',
  ),
  Command('queryTmsState', (_) => _p20.queryTmsState()),
];

final Map<String, Stream<Object?>> _p20Streams = {
  'locationUpdates': _p20.locationUpdates,
  'ioStatus': _p20.ioStatus,
  'nfcEvents': _p20.nfcEvents,
  'gsensorData': _p20.gsensorData,
  'wifiStatus': _p20.wifiStatus,
  'canFrames': _p20.canFrames,
  'dsmAlarms': _p20.dsmAlarms,
};

// ---------------------------------------------------------------------- MDVR

final _mdvr = MnMdvrSdk.instance;

final List<Command> _mdvrCommands = [
  Command(
    'init',
    (p) =>
        _mdvr.init(path: p['path'] as String, baudRate: p['baudRate'] as int),
    param: '{"path": "/dev/ttyS4", "baudRate": 19200}',
  ),
  Command('release', (_) => _mdvr.release()),
  Command('getSdkVersion', (_) => _mdvr.getSdkVersion()),
  Command('getDeviceIdentifier', (_) => _mdvr.getDeviceIdentifier()),
  Command('getVersion', (_) => _mdvr.getVersion()),
  Command('getApcInfo', (_) => _mdvr.getApcInfo()),
  Command('queryHostInfo', (_) => _mdvr.queryHostInfo()),
  Command('queryHostDetailStatus', (_) => _mdvr.queryHostDetailStatus()),
  Command('getRouteCount', (_) => _mdvr.getRouteCount()),
  Command('queryRouteStatus', (_) => _mdvr.queryRouteStatus()),
  Command(
    'queryRouteInfo',
    (p) => _mdvr.queryRouteInfo(p['index'] as int),
    param: '{"index": 0}',
  ),
  Command('queryStopInfo', (_) => _mdvr.queryStopInfo()),
  Command(
    'switchRoute',
    (p) => _mdvr.switchRoute(p['index'] as int),
    param: '{"index": 0}',
  ),
  Command('switchNext', (_) => _mdvr.switchNext()),
  Command(
    'switchStop',
    (p) => _mdvr.switchStop(next: p['next'] as bool),
    param: '{"next": true}',
  ),
  Command('replayVoice', (_) => _mdvr.replayVoice()),
  Command(
    'playServiceVoice',
    (p) => _mdvr.playServiceVoice(p['key'] as int),
    param: '{"key": 1}',
  ),
  Command('stopServiceVoice', (_) => _mdvr.stopServiceVoice()),
  Command(
    'openDriveMic',
    (p) => _mdvr.openDriveMic(micType: p['micType'] as int),
    param: '{"micType": 0}',
  ),
  Command('closeDriveMic', (_) => _mdvr.closeDriveMic()),
  Command(
    'dial',
    (p) => _mdvr.dial(p['phone'] as String),
    param: '{"phone": "10086"}',
  ),
  Command('acceptDial', (_) => _mdvr.acceptDial()),
  Command('dialOff', (_) => _mdvr.dialOff()),
  Command(
    'switchAnalogChannels',
    (p) => _mdvr.switchAnalogChannels((p['channels'] as List).cast<int>()),
    param: '{"channels": [1, 2, 3, 4]}',
  ),
  Command(
    'switchIpcChannel',
    (p) => _mdvr.switchIpcChannel(p['index'] as int),
    param: '{"index": 1}',
  ),
  Command('resetToDefaultChannel', (_) => _mdvr.resetToDefaultChannel()),
  Command(
    'startTrip',
    (p) => _mdvr.startTrip(
      time: p['time'] as String,
      direction: p['direction'] as int,
      lineFlag: p['lineFlag'] as int,
    ),
    param: '{"time": "08:30", "direction": 0, "lineFlag": 1}',
  ),
  Command(
    'endTrip',
    (p) => _mdvr.endTrip(
      time: p['time'] as String,
      direction: p['direction'] as int,
      lineFlag: p['lineFlag'] as int,
    ),
    param: '{"time": "17:45", "direction": 0, "lineFlag": 0}',
  ),
  Command('queryAdasInfo', (_) => _mdvr.queryAdasInfo()),
  Command('queryDsmInfo', (_) => _mdvr.queryDsmInfo()),
  Command(
    'requestCalibPhoto',
    (p) =>
        _mdvr.requestCalibPhoto(calibrationType: p['calibrationType'] as int),
    param: '{"calibrationType": 2}',
  ),
];

final Map<String, Stream<Object?>> _mdvrStreams = {
  'gpsUpdates': _mdvr.gpsUpdates,
  'canData': _mdvr.canData,
  'apcUpdates': _mdvr.apcUpdates,
  'dialState': _mdvr.dialState,
  'routeStatus': _mdvr.routeStatus,
  'hostDetailStatus': _mdvr.hostDetailStatus,
  'upsUpdates': _mdvr.upsUpdates,
  'displayMessages': _mdvr.displayMessages,
  'alarms': _mdvr.alarms,
  'calibPhotoEvents': _mdvr.calibPhotoEvents,
};

// ----------------------------------------------------------------------- LED

final _led = MnLedSdk.instance;

final List<Command> _ledCommands = [
  Command(
    'init',
    (p) => _led.init(path: p['path'] as String, baudRate: p['baudRate'] as int),
    param: '{"path": "/dev/ttyS5", "baudRate": 38400}',
  ),
  Command('release', (_) => _led.release()),
  Command('getSdkVersion', (_) => _led.getSdkVersion()),
  Command('getRouteList', (_) => _led.getRouteList()),
  Command('getNonOpStatusList', (_) => _led.getNonOpStatusList()),
  Command(
    'switchRoute',
    (p) => _led.switchRoute(
      index: p['index'] as int,
      direction: p['direction'] as int,
    ),
    param: '{"index": 0, "direction": 0}',
  ),
  Command(
    'triggerStopAnnouncement',
    (p) => _led.triggerStopAnnouncement(
      index: p['index'] as int,
      direction: p['direction'] as int,
      stopIndex: p['stopIndex'] as int,
      isArrival: p['isArrival'] as bool,
    ),
    param: '{"index": 0, "direction": 0, "stopIndex": 0, "isArrival": true}',
  ),
  Command(
    'sendLedDisplay',
    (p) => _led.sendLedDisplay(
      addr: p['addr'] as int,
      routeName: p['routeName'] as String,
      languageUR: p['languageUR'] as String,
      languageEN: p['languageEN'] as String,
    ),
    param:
        '{"addr": 1, "routeName": "3A", "languageUR": "ڈاؤن اسٹیشن", '
        '"languageEN": "DownStation"}',
  ),
  Command(
    'sendImageRegion',
    (p) => _led.sendImageRegion(
      addr: p['addr'] as int,
      filePath: p['filePath'] as String,
    ),
    param:
        '{"addr": 1, "filePath": '
        '"/storage/emulated/0/ConfigFolder/011 1/Go/Sign1/Region.bin"}',
  ),
];

// ---------------------------------------------------------------------- Fuel

final _fuel = MnFuelSdk.instance;

final List<Command> _fuelCommands = [
  Command(
    'init',
    (p) =>
        _fuel.init(path: p['path'] as String, baudRate: p['baudRate'] as int),
    param: '{"path": "/dev/ttyS5", "baudRate": 9600}',
  ),
  Command('release', (_) => _fuel.release()),
  Command('getSdkVersion', (_) => _fuel.getSdkVersion()),
  Command('queryFuelLevel', (_) => _fuel.queryFuelLevel()),
  Command(
    'sendCustomCommand',
    (p) => _fuel.sendCustomCommand(p['hex'] as String),
    param: '{"hex": "11223344"}',
  ),
];

final Map<String, Stream<Object?>> _fuelStreams = {
  'fuelLevel': _fuel.fuelLevel,
};

// ------------------------------------------------------------------- console

/// Lets the user pick a command, edit its JSON parameter, run it, and toggle
/// stream subscriptions. Everything is written to a scrolling log.
class Console extends StatefulWidget {
  const Console({super.key, required this.commands, this.streams = const {}});

  final List<Command> commands;
  final Map<String, Stream<Object?>> streams;

  @override
  State<Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<Console> with AutomaticKeepAliveClientMixin {
  late Command _selected = widget.commands.first;
  late final _param = TextEditingController(text: _selected.param ?? '');
  final _subscriptions = <String, StreamSubscription<Object?>>{};
  final _log = <String>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _param.dispose();
    super.dispose();
  }

  void _append(String line) {
    if (!mounted) return;
    final now = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _log.insert(0, '[$now] $line');
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _run() async {
    final command = _selected;
    try {
      final text = _param.text.trim();
      final param = text.isEmpty
          ? const <String, dynamic>{}
          : (jsonDecode(text) as Map).cast<String, dynamic>();
      final result = await command.run(param);
      _append('${command.name} -> ${result ?? 'done'}');
    } catch (error) {
      _append('${command.name} failed: $error');
    }
  }

  void _toggle(String name, bool listen) {
    if (listen) {
      _subscriptions[name] = widget.streams[name]!.listen(
        (event) => _append('$name: $event'),
        onError: (Object error) => _append('$name error: $error'),
      );
    } else {
      _subscriptions.remove(name)?.cancel();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<Command>(
                  isExpanded: true,
                  value: _selected,
                  items: [
                    for (final command in widget.commands)
                      DropdownMenuItem(
                        value: command,
                        child: Text(command.name),
                      ),
                  ],
                  onChanged: (command) => setState(() {
                    _selected = command!;
                    _param.text = command.param ?? '';
                  }),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: _run, child: const Text('Run')),
            ],
          ),
          TextField(
            controller: _param,
            enabled: _selected.param != null,
            decoration: const InputDecoration(labelText: 'Parameter (JSON)'),
            minLines: 1,
            maxLines: 3,
          ),
          if (widget.streams.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final name in widget.streams.keys)
                    FilterChip(
                      label: Text(name),
                      selected: _subscriptions.containsKey(name),
                      onSelected: (listen) => _toggle(name, listen),
                    ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(
                  _log[index],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
