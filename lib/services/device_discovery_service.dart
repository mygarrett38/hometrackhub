import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Bluetooth signal strengths, in dBm, at or above which a device is
/// considered very close or nearby.
const _veryCloseSignalStrength = -60;
const _nearbySignalStrength = -75;

/// A smart device found on the home network or over Bluetooth.
@immutable
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.suggestedTypeId,
    this.manufacturer = '',
    this.model = '',
    this.address,
    this.detailsUrl,
    this.signalStrength,
    this.foundOverBluetooth = false,
  });

  /// Stable identifier used to recognize the same device in later scans.
  final String id;
  final String name;

  /// What kind of device this appears to be, for example "Google Cast device".
  final String kind;

  /// Id of the home item catalog entry that best matches this device.
  final String suggestedTypeId;

  final String manufacturer;
  final String model;

  /// The device's IP address, if known.
  final String? address;

  /// Where the device's name and other details can be downloaded, if they
  /// haven't been yet. See [DeviceDiscoveryService.loadDetails].
  final Uri? detailsUrl;

  /// Whether only the device's address is known so far.
  bool get needsDetails => detailsUrl != null;

  /// How strongly a Bluetooth device's signal was received, in dBm. Values
  /// closer to zero usually mean the device is closer.
  final int? signalStrength;

  /// Whether the device was found over Bluetooth rather than on the local
  /// network.
  final bool foundOverBluetooth;
}

/// Combines scan results that describe the same physical device.
///
/// Many devices announce themselves several ways. A Roku player, for
/// example, shows up as an AirPlay device, a Spotify Connect speaker and a
/// Roku player, all at the same IP address. For each address, only the
/// entry with the most useful details is kept.
///
/// Bluetooth doesn't share IP addresses, so a Bluetooth device is matched
/// by name instead. If the network has a device with the same name, only
/// the network entry is kept.
List<DiscoveredDevice> mergeDuplicateDevices(
  Iterable<DiscoveredDevice> devices,
) {
  final networkNames = {
    for (final device in devices)
      if (!device.foundOverBluetooth) device.name.toLowerCase(),
  };
  final bestByAddress = <String, DiscoveredDevice>{};
  for (final device in devices) {
    if (device.foundOverBluetooth &&
        networkNames.contains(device.name.toLowerCase())) {
      continue;
    }
    final key = device.address ?? device.id;
    final existing = bestByAddress[key];
    if (existing == null || _detailScore(device) > _detailScore(existing)) {
      bestByAddress[key] = device;
    }
  }
  return bestByAddress.values.toList();
}

/// Higher scores mean the device entry is more useful to show to people.
int _detailScore(DiscoveredDevice device) {
  // Devices waiting for details almost always turn out to have a readable
  // name. Scoring them just below that means they replace entries named with
  // a random id, so their details get loaded, but not entries that are
  // already readable, so no time is spent loading details that aren't needed.
  if (device.needsDetails) return 3;

  // Some services, like Spotify Connect, use a random id as their name.
  final nameIsRandomId = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-')
      .hasMatch(device.name.toLowerCase());

  var score = 0;
  if (!nameIsRandomId) score += 4;
  if (device.manufacturer.isNotEmpty) score += 2;
  if (device.model.isNotEmpty) score += 1;
  return score;
}

/// Sorts [devices] so the ones people are most likely to want to add come
/// first.
///
/// Devices with a recognizable kind, a readable name and known manufacturer
/// and model rank above generic entries. Ties keep the order the devices were
/// found in, which puts devices that answered the scan sooner (usually the
/// closest ones on the network) first.
List<DiscoveredDevice> rankDevicesByRelevance(
  Iterable<DiscoveredDevice> devices,
) {
  // List.sort isn't stable, so the discovery order is kept explicitly.
  final indexed = devices.indexed.toList()
    ..sort((a, b) {
      final byScore = _relevanceScore(b.$2).compareTo(_relevanceScore(a.$2));
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
  return [for (final (_, device) in indexed) device];
}

int _relevanceScore(DiscoveredDevice device) {
  var score = _detailScore(device);
  if (device.kind != _genericDeviceKind &&
      device.kind != _genericBluetoothKind) {
    score += 3;
  }
  // Bluetooth devices close to the phone are more likely to be the user's.
  final signal = device.signalStrength;
  if (signal != null && signal >= _veryCloseSignalStrength) {
    score += 2;
  } else if (signal != null && signal >= _nearbySignalStrength) {
    score += 1;
  }
  return score;
}

/// The kind given to UPnP devices that couldn't be identified.
const _genericDeviceKind = 'Network device';

/// The kind given to Bluetooth devices that couldn't be identified.
const _genericBluetoothKind = 'Bluetooth device';

/// Collapses runs of spaces in device names, e.g. "Roku    Premiere".
String _cleanName(String name) => name.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Finds smart devices on the local network and over Bluetooth.
///
/// This is an interface so tests can supply a fake implementation.
abstract interface class DeviceDiscoveryService {
  /// Whether the device is connected to a local network (Wi-Fi or Ethernet)
  /// that can be scanned.
  Future<bool> isConnectedToLocalNetwork();

  /// Scans for [duration] and emits devices as they are found.
  ///
  /// Bluetooth devices nearby are always searched for. Devices on the local
  /// network are only searched for when [includeNetwork] is true.
  ///
  /// The same device may be emitted more than once as more details about it
  /// arrive. Use [DiscoveredDevice.id] to replace the earlier copy.
  ///
  /// Some devices are emitted with only their address known, so that busy
  /// networks aren't flooded with requests for details nobody will see. Pass
  /// those to [loadDetails] once they're about to be shown.
  Stream<DiscoveredDevice> scan({Duration duration, bool includeNetwork});

  /// Downloads the details of a device whose [DiscoveredDevice.needsDetails]
  /// is true. Returns `null` if they can't be read, in which case the device
  /// should not be shown.
  Future<DiscoveredDevice?> loadDetails(DiscoveredDevice device);
}

/// Describes a Bonjour / mDNS service type that smart home devices announce.
class _KnownService {
  const _KnownService(this.kind, this.suggestedTypeId);

  final String kind;
  final String suggestedTypeId;
}

/// Bonjour service types to look for. iOS only allows browsing for
/// types listed under NSBonjourServices in ios/Runner/Info.plist, so update that
/// file when changing this list.
const Map<String, _KnownService> _knownMdnsServices = {
  '_hap._tcp': _KnownService('Apple HomeKit accessory', 'smart_device'),
  '_matter._tcp': _KnownService('Matter smart home device', 'smart_device'),
  '_matterc._udp': _KnownService('Matter device (setup mode)', 'smart_device'),
  '_googlecast._tcp': _KnownService('Google Cast device', 'smart_tv'),
  '_airplay._tcp': _KnownService('AirPlay device', 'smart_tv'),
  '_raop._tcp': _KnownService('AirPlay speaker', 'smart_speaker'),
  '_spotify-connect._tcp': _KnownService(
    'Spotify Connect speaker',
    'smart_speaker',
  ),
  '_sonos._tcp': _KnownService('Sonos speaker', 'smart_speaker'),
  '_amzn-wplay._tcp': _KnownService('Amazon Fire TV', 'smart_tv'),
  '_androidtvremote2._tcp': _KnownService('Android TV', 'smart_tv'),
  '_hue._tcp': _KnownService('Philips Hue bridge', 'smart_lighting'),
  '_nanoleafapi._tcp': _KnownService('Nanoleaf lights', 'smart_lighting'),
  '_elg._tcp': _KnownService('Elgato light', 'smart_lighting'),
  '_home-assistant._tcp': _KnownService('Home Assistant hub', 'smart_hub'),
  '_esphomelib._tcp': _KnownService('ESPHome device', 'smart_device'),
  '_shelly._tcp': _KnownService('Shelly smart switch', 'smart_device'),
  '_ipp._tcp': _KnownService('Network printer', 'printer'),
  '_printer._tcp': _KnownService('Network printer', 'printer'),
  '_axis-video._tcp': _KnownService('Network camera', 'security_camera'),
  '_miio._udp': _KnownService('Xiaomi smart device', 'smart_device'),
};

/// [DeviceDiscoveryService] that searches using three common discovery
/// methods:
///
/// * Bonjour / mDNS, used by HomeKit, Matter, Google Cast, AirPlay, printers
///   and many other devices.
/// * UPnP / SSDP, used by many smart TVs, routers, Roku players and smart
///   plugs.
/// * Bluetooth Low Energy, used by smart locks, lights, sensors and devices
///   that are waiting to be set up.
class NearbyDeviceDiscoveryService implements DeviceDiscoveryService {
  @override
  Future<bool> isConnectedToLocalNetwork() async {
    final connections = await Connectivity().checkConnectivity();
    return connections.contains(ConnectivityResult.wifi) ||
        connections.contains(ConnectivityResult.ethernet);
  }

  @override
  Stream<DiscoveredDevice> scan({
    Duration duration = const Duration(seconds: 10),
    bool includeNetwork = true,
  }) {
    final stopped = Completer<void>();
    late final StreamController<DiscoveredDevice> controller;
    late final Future<void> scanFinished;

    void report(DiscoveredDevice device) {
      if (!stopped.isCompleted && !controller.isClosed) controller.add(device);
    }

    Future<void> runScan() async {
      final results = await Future.wait([
        if (includeNetwork) ...[
          _runSafely('mDNS', () => _scanMdns(duration, report, stopped.future)),
          _runSafely('SSDP', () => _scanSsdp(duration, report, stopped.future)),
        ],
        _runSafely(
          'Bluetooth',
          () => _scanBluetooth(duration, report, stopped.future),
        ),
      ]);
      if (!stopped.isCompleted) {
        if (results.every((succeeded) => !succeeded)) {
          controller.addError(
            const SocketException('No nearby devices could be scanned for.'),
          );
        }
        // Do not await close: cancellation waits for scanner cleanup.
        unawaited(controller.close());
      }
    }

    controller = StreamController<DiscoveredDevice>(
      onListen: () => scanFinished = runScan(),
      onCancel: () async {
        if (!stopped.isCompleted) stopped.complete();
        await scanFinished;
      },
    );
    return controller.stream;
  }

  /// Runs one scanner and returns whether it completed without an error, so
  /// a failure in one protocol does not stop the other.
  Future<bool> _runSafely(String name, Future<void> Function() scan) async {
    try {
      await scan();
      return true;
    } catch (error) {
      debugPrint('$name scan failed: $error');
      return false;
    }
  }

  Future<void> _scanMdns(
    Duration duration,
    void Function(DiscoveredDevice) report,
    Future<void> stopped,
  ) async {
    final discoveries = <BonsoirDiscovery>[];
    final subscriptions = <StreamSubscription<BonsoirDiscoveryEvent>>[];
    final pending = Queue<(BonsoirService, BonsoirDiscovery)>();
    final seen = <String>{};
    BonsoirDiscovery? resolvingWith;
    String? resolvingName;
    var active = true;

    // A resolve() future only submits a native request; it does not wait for
    // the address. Wait for the result event before starting the next request.
    void resolveNext() {
      if (!active || resolvingWith != null || pending.isEmpty) return;
      final (service, discovery) = pending.removeFirst();
      resolvingWith = discovery;
      resolvingName = service.name;
      unawaited(
        service.resolve(discovery.serviceResolver).catchError((Object error) {
          debugPrint('Could not resolve ${service.name}: $error');
          if (active &&
              identical(resolvingWith, discovery) &&
              resolvingName == service.name) {
            resolvingWith = null;
            resolveNext();
          }
        }),
      );
    }

    unawaited(stopped.then((_) => active = false));
    try {
      for (final MapEntry(key: type, value: known)
          in _knownMdnsServices.entries) {
        if (!active) break;
        try {
          final discovery = BonsoirDiscovery(type: type, printLogs: false);
          await discovery.initialize();
          discoveries.add(discovery);
          if (!active) break;
          subscriptions.add(
            discovery.eventStream!.listen(
              (event) {
                if (!active) return;
                switch (event) {
                  case BonsoirDiscoveryServiceFoundEvent(:final service):
                    report(_deviceFromMdns(service, known));
                    if (service.hostAddress == null &&
                        seen.add('$type:${service.name}')) {
                      pending.add((service, discovery));
                      resolveNext();
                    }
                  case BonsoirDiscoveryServiceResolvedEvent(:final service):
                    report(_deviceFromMdns(service, known));
                    if (identical(resolvingWith, discovery) &&
                        resolvingName == service.name) {
                      resolvingWith = null;
                      resolveNext();
                    }
                  case BonsoirDiscoveryServiceResolveFailedEvent():
                    if (identical(resolvingWith, discovery)) {
                      resolvingWith = null;
                      resolveNext();
                    }
                  default:
                    break;
                }
              },
              onError: (Object error) {
                debugPrint('Bonjour $type scan error: $error');
              },
            ),
          );
          await discovery.start();
        } catch (error) {
          debugPrint('Could not search for $type services: $error');
        }
      }
      if (discoveries.isEmpty && active) {
        throw StateError('No Bonjour searches could be started.');
      }
      await Future.any([Future<void>.delayed(duration), stopped]);
    } finally {
      active = false;
      pending.clear();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      for (final discovery in discoveries) {
        await _runSafely('Bonjour cleanup', discovery.stop);
      }
    }
  }

  DiscoveredDevice _deviceFromMdns(
    BonsoirService service,
    _KnownService known,
  ) {
    // AirPlay speakers are named like "A1B2C3D4E5F6@Living Room". Only the
    // part after the "@" is meaningful to people.
    final atIndex = service.name.indexOf('@');
    final name = _cleanName(
      atIndex >= 0 ? service.name.substring(atIndex + 1) : service.name,
    );
    return DiscoveredDevice(
      id: 'mdns:${name.toLowerCase()}',
      name: name,
      kind: known.kind,
      suggestedTypeId: known.suggestedTypeId,
      manufacturer: service.attributes['manufacturer'] ?? '',
      model: service.attributes['model'] ?? service.attributes['md'] ?? '',
      address: service.hostAddress,
    );
  }

  Future<void> _scanSsdp(
    Duration duration,
    void Function(DiscoveredDevice) report,
    Future<void> stopped,
  ) async {
    // iOS only lets apps send multicast packets with a special entitlement
    // granted by Apple, so SSDP is skipped there. Bonjour still works.
    if (Platform.isIOS) return;

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final seenLocations = <String>{};

    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;

      final headers = _parseHttpHeaders(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      final location = headers['location'];
      if (location == null || !seenLocations.add(location)) return;
      final detailsUrl = Uri.tryParse(location);
      if (detailsUrl == null) return;

      // The description isn't downloaded yet. On busy networks there can be
      // thousands of devices, so it's only fetched for the ones that are
      // shown, through loadDetails.
      final address = datagram.address.address;
      report(
        DiscoveredDevice(
          id: 'upnp:$location',
          name: address,
          kind: _genericDeviceKind,
          suggestedTypeId: 'smart_device',
          address: address,
          detailsUrl: detailsUrl,
        ),
      );
    });

    const searchRequest =
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: ssdp:all\r\n'
        '\r\n';
    final multicastAddress = InternetAddress('239.255.255.250');

    var cancelled = false;
    unawaited(stopped.then((_) => cancelled = true));
    try {
      // UDP packets can be lost, so the search is sent a few times.
      const attempts = 3;
      for (var attempt = 0; attempt < attempts && !cancelled; attempt++) {
        socket.send(utf8.encode(searchRequest), multicastAddress, 1900);
        await Future.any([
          Future<void>.delayed(const Duration(seconds: 1)),
          stopped,
        ]);
      }
      final remaining = duration - const Duration(seconds: attempts);
      if (!cancelled && remaining > Duration.zero) {
        await Future.any([Future<void>.delayed(remaining), stopped]);
      }
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  /// Parses the headers of an SSDP response. Header names are lower-cased.
  Map<String, String> _parseHttpHeaders(String message) {
    final headers = <String, String>{};
    for (final line in const LineSplitter().convert(message)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final name = line.substring(0, separator).trim().toLowerCase();
      headers[name] = line.substring(separator + 1).trim();
    }
    return headers;
  }

  /// Downloads a UPnP device description and turns it into a
  /// [DiscoveredDevice]. Returns `null` if the description can't be read.
  @override
  Future<DiscoveredDevice?> loadDetails(DiscoveredDevice device) async {
    final location = device.detailsUrl;
    if (location == null) return device;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(location);
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final xml = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));

      final rawName = _readXmlTag(xml, 'friendlyName');
      if (rawName == null) return null;
      final name = _cleanName(rawName);
      final manufacturer = _readXmlTag(xml, 'manufacturer') ?? '';
      final model = _readXmlTag(xml, 'modelName') ?? '';
      final deviceType = _readXmlTag(xml, 'deviceType') ?? '';
      final (kind, typeId) = _classifyUpnpDevice(
        deviceType: deviceType,
        manufacturer: manufacturer,
        model: model,
      );

      return DiscoveredDevice(
        id: 'upnp:${_readXmlTag(xml, 'UDN') ?? location}',
        name: name,
        kind: kind,
        suggestedTypeId: typeId,
        manufacturer: manufacturer,
        model: model,
        address: device.address,
      );
    } catch (error) {
      debugPrint('Could not read UPnP description at $location: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Reads the text of the first `<tag>` in [xml]. A full XML parser isn't
  /// needed for the handful of simple fields used here.
  String? _readXmlTag(String xml, String tag) {
    final match = RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml);
    final value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Guesses what kind of device a UPnP description is for. Returns a
  /// description and the id of the closest home item catalog entry.
  (String, String) _classifyUpnpDevice({
    required String deviceType,
    required String manufacturer,
    required String model,
  }) {
    final text = '$deviceType $manufacturer $model'.toLowerCase();
    if (text.contains('hue')) return ('Philips Hue bridge', 'smart_lighting');
    if (text.contains('roku')) return ('Roku streaming device', 'smart_tv');
    if (text.contains('sonos')) return ('Sonos speaker', 'smart_speaker');
    if (text.contains('wemo')) return ('Wemo smart plug', 'smart_device');
    if (text.contains('internetgatewaydevice')) {
      return ('Router', 'router');
    }
    if (text.contains('printer')) return ('Network printer', 'printer');
    if (text.contains('mediarenderer')) {
      return ('Smart TV or media player', 'smart_tv');
    }
    return (_genericDeviceKind, 'smart_device');
  }

  Future<void> _scanBluetooth(
    Duration duration,
    void Function(DiscoveredDevice) report,
    Future<void> stopped,
  ) async {
    if (!await FlutterBluePlus.isSupported) {
      throw UnsupportedError('This device does not support Bluetooth.');
    }

    // The state is unknown until the system reports it. On iOS, this is
    // also when people are first asked to allow Bluetooth, so they're given
    // as long as the scan takes to answer.
    final state = await Future.any<BluetoothAdapterState?>([
      FlutterBluePlus.adapterState
          .firstWhere((state) => state != BluetoothAdapterState.unknown)
          .timeout(duration),
      stopped.then((_) => null),
    ]);
    if (state == null) return;
    if (state != BluetoothAdapterState.on) {
      throw StateError('Bluetooth is not available: ${state.name}');
    }

    final subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          final device = _deviceFromBluetooth(result);
          if (device != null) report(device);
        }
      },
      onError: (Object error) {
        debugPrint('Bluetooth scan error: $error');
      },
    );
    try {
      // On Android, this asks for permission to find nearby devices.
      await FlutterBluePlus.startScan(timeout: duration, oneByOne: true);
      await Future.any([
        FlutterBluePlus.isScanning
            .firstWhere((scanning) => !scanning)
            .timeout(duration + const Duration(seconds: 5)),
        stopped,
      ]);
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  DiscoveredDevice? _deviceFromBluetooth(ScanResult result) {
    final advertisement = result.advertisementData;
    final name = _cleanName(
      advertisement.advName.isNotEmpty
          ? advertisement.advName
          : result.device.platformName,
    );
    // Devices that don't share a name, like most phones and trackers, can't
    // be told apart, so they aren't listed.
    if (name.isEmpty) return null;

    final (kind, typeId) = classifyBluetoothDevice(
      name: name,
      serviceUuids: [
        for (final uuid in advertisement.serviceUuids) uuid.str,
        for (final uuid in advertisement.serviceData.keys) uuid.str,
      ],
      manufacturerData: advertisement.manufacturerData,
    );
    return DiscoveredDevice(
      id: 'ble:${result.device.remoteId.str}',
      name: name,
      kind: kind,
      suggestedTypeId: typeId,
      signalStrength: result.rssi,
      foundOverBluetooth: true,
    );
  }
}

/// Bluetooth service ids (16-bit, lower case) that identify a kind of device.
const Map<String, (String, String)> _knownBluetoothServices = {
  'fff6': ('Matter device (setup mode)', 'smart_device'),
  'fe0f': ('Philips Hue light', 'smart_lighting'),
  'fe24': ('August smart lock', 'smart_lock'),
  'fe95': ('Xiaomi smart device', 'smart_device'),
  '181a': ('Environmental sensor', 'smart_device'),
};

/// Words in a Bluetooth device's name that suggest what it is. Checked in
/// order, so more specific words come first.
const List<(String, String, String)> _bluetoothNameHints = [
  ('lock|august|yale|schlage', 'Smart lock', 'smart_lock'),
  ('thermostat|ecobee|nest', 'Smart thermostat', 'smart_thermostat'),
  ('vacuum|roomba|roborock', 'Robot vacuum', 'robot_vacuum'),
  (
    'doorbell|camera|cam|ring|arlo|wyze',
    'Camera or doorbell',
    'security_camera',
  ),
  ('hue|bulb|light|lamp|govee|nanoleaf|lifx', 'Smart light', 'smart_lighting'),
  (
    'speaker|soundbar|sonos|echo|bose|jbl',
    'Bluetooth speaker',
    'smart_speaker',
  ),
  ('tv|roku|chromecast', 'TV or streaming device', 'smart_tv'),
  ('printer', 'Printer', 'printer'),
];

/// Guesses what kind of device a Bluetooth advertisement is for. Returns a
/// description and the id of the closest home item catalog entry.
@visibleForTesting
(String, String) classifyBluetoothDevice({
  required String name,
  required List<String> serviceUuids,
  required Map<int, List<int>> manufacturerData,
}) {
  for (final uuid in serviceUuids) {
    final known = _knownBluetoothServices[uuid.toLowerCase()];
    if (known != null) return known;
  }

  // HomeKit accessories advertise Apple's company id (0x004C) followed by
  // the HomeKit advertisement type, 0x06.
  final apple = manufacturerData[0x004C];
  if (apple != null && apple.isNotEmpty && apple.first == 0x06) {
    return ('Apple HomeKit accessory', 'smart_device');
  }

  final lowerName = name.toLowerCase();
  for (final (words, kind, typeId) in _bluetoothNameHints) {
    if (RegExp('\\b($words)\\b').hasMatch(lowerName)) return (kind, typeId);
  }
  return (_genericBluetoothKind, 'smart_device');
}
