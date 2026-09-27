import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// A smart device found on the home network.
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
  });

  /// Stable identifier used to recognize the same device in later scans.
  final String id;
  final String name;

  /// What kind of device this appears to be, for example "Google Cast device".
  final String kind;

  /// Id of the equipment catalog entry that best matches this device.
  final String suggestedTypeId;

  final String manufacturer;
  final String model;

  /// The device's IP address, if known.
  final String? address;
}

/// Combines scan results that describe the same physical device.
///
/// Many devices announce themselves several ways. A Roku player, for
/// example, shows up as an AirPlay device, a Spotify Connect speaker and a
/// Roku player, all at the same IP address. For each address, only the
/// entry with the most useful details is kept.
List<DiscoveredDevice> mergeDuplicateDevices(
  Iterable<DiscoveredDevice> devices,
) {
  final bestByAddress = <String, DiscoveredDevice>{};
  for (final device in devices) {
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
  // Some services, like Spotify Connect, use a random id as their name.
  final nameIsRandomId = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-')
      .hasMatch(device.name.toLowerCase());

  var score = 0;
  if (!nameIsRandomId) score += 4;
  if (device.manufacturer.isNotEmpty) score += 2;
  if (device.model.isNotEmpty) score += 1;
  return score;
}

/// Collapses runs of spaces in device names, e.g. "Roku    Premiere".
String _cleanName(String name) => name.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Finds smart devices on the local network.
///
/// This is an interface so tests can supply a fake implementation.
abstract interface class DeviceDiscoveryService {
  /// Whether the device is connected to a local network (Wi-Fi or Ethernet)
  /// that can be scanned.
  Future<bool> isConnectedToLocalNetwork();

  /// Scans the network for [duration] and emits devices as they are found.
  ///
  /// The same device may be emitted more than once as more details about it
  /// arrive. Use [DiscoveredDevice.id] to replace the earlier copy.
  Stream<DiscoveredDevice> scan({Duration duration});
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

/// [DeviceDiscoveryService] that searches the network using two common
/// discovery protocols:
///
/// * Bonjour / mDNS, used by HomeKit, Matter, Google Cast, AirPlay, printers
///   and many other devices.
/// * UPnP / SSDP, used by many smart TVs, routers, Roku players and smart
///   plugs.
class NetworkDeviceDiscoveryService implements DeviceDiscoveryService {
  @override
  Future<bool> isConnectedToLocalNetwork() async {
    final connections = await Connectivity().checkConnectivity();
    return connections.contains(ConnectivityResult.wifi) ||
        connections.contains(ConnectivityResult.ethernet);
  }

  @override
  Stream<DiscoveredDevice> scan({
    Duration duration = const Duration(seconds: 10),
  }) {
    final controller = StreamController<DiscoveredDevice>();

    void report(DiscoveredDevice device) {
      if (!controller.isClosed) controller.add(device);
    }

    Future<void> runScan() async {
      final results = await Future.wait([
        _runSafely('mDNS', () => _scanMdns(duration, report)),
        _runSafely('SSDP', () => _scanSsdp(duration, report)),
      ]);
      if (results.every((succeeded) => !succeeded)) {
        controller.addError(
          const SocketException('The local network could not be scanned.'),
        );
      }
      await controller.close();
    }

    runScan();
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
  ) async {
    final discoveries = <BonsoirDiscovery>[];
    final subscriptions = <StreamSubscription<BonsoirDiscoveryEvent>>[];

    try {
      for (final MapEntry(key: type, value: known)
          in _knownMdnsServices.entries) {
        // One service type failing should not stop the others.
        try {
          final discovery = BonsoirDiscovery(type: type, printLogs: false);
          await discovery.initialize();
          subscriptions.add(
            discovery.eventStream!.listen((event) {
              switch (event) {
                case BonsoirDiscoveryServiceFoundEvent(:final service):
                  report(_deviceFromMdns(service, known));
                  // Resolving looks up the device's IP address.
                  service.resolve(discovery.serviceResolver);
                case BonsoirDiscoveryServiceResolvedEvent(:final service):
                  report(_deviceFromMdns(service, known));
                default:
                  break;
              }
            }),
          );
          await discovery.start();
          discoveries.add(discovery);
        } catch (error) {
          debugPrint('Could not search for $type services: $error');
        }
      }
      if (discoveries.isEmpty) {
        throw StateError('No Bonjour searches could be started.');
      }
      await Future<void>.delayed(duration);
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      for (final discovery in discoveries) {
        await discovery.stop();
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
  ) async {
    // iOS only lets apps send multicast packets with a special entitlement
    // granted by Apple, so SSDP is skipped there. Bonjour still works.
    if (Platform.isIOS) return;

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final seenLocations = <String>{};
    final pendingLookups = <Future<void>>[];

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;

      final headers = _parseHttpHeaders(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      final location = headers['location'];
      if (location == null || !seenLocations.add(location)) return;

      pendingLookups.add(
        _describeUpnpDevice(location, datagram.address.address).then((device) {
          if (device != null) report(device);
        }),
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

    // UDP packets can be lost, so the search is sent a few times.
    const attempts = 3;
    for (var attempt = 0; attempt < attempts; attempt++) {
      socket.send(utf8.encode(searchRequest), multicastAddress, 1900);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final remaining = duration - const Duration(seconds: attempts);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);

    socket.close();
    await Future.wait(pendingLookups);
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
  Future<DiscoveredDevice?> _describeUpnpDevice(
    String location,
    String address,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse(location));
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
        address: address,
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
  /// description and the id of the closest equipment catalog entry.
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
    return ('Network device', 'smart_device');
  }
}
