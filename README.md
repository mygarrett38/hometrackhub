# HomeTrack Hub

A home maintenance app designed to track maintenance tasks, find local services, and answer questions about your home. Created for Shepherd University CIS 485 course.

## Features

- Track appliances, vehicles, smart devices and custom home items.
- Maintenance schedules default to typical manufacturer recommendations from a
  built-in catalog, and every interval can be changed or reset.
- Each task has its own reminder: on or off, how many days before the due
  date, and at what time.
- An optional weekly or monthly overview notification summarizes upcoming and
  overdue maintenance.
- Finds smart devices on the current Wi-Fi network using Bonjour/mDNS and
  UPnP/SSDP.
- Settings for notifications, light/dark mode, privacy and home location.
  All data is stored only on the device.

## Supported platforms

Android and iOS.

## Running

```sh
flutter pub get
flutter run            # pick a device
flutter test           # unit and widget tests
```

## Project structure

| Folder | Contents |
| --- | --- |
| `lib/models/` | Plain data classes: home items, maintenance tasks, intervals, settings. |
| `lib/data/` | The built-in home item catalog and repositories that save data with `shared_preferences`. |
| `lib/services/` | Notification scheduling, reminder planning and network device discovery. |
| `lib/state/` | `ChangeNotifier` controllers the UI listens to, plus `ReminderSync`, which reschedules notifications after every change. |
| `lib/ui/` | Screens and shared widgets. |
| `test/` | Unit tests for the models, planner and catalog, plus widget tests. |

State is shared with the [provider](https://pub.dev/packages/provider)
package. `lib/main.dart` creates the controllers and services and provides
them to the widget tree.

## Platform notes

- **Android:** scheduled notifications need core library desugaring and the
  receivers declared in `AndroidManifest.xml`. Both are already configured.
- **iOS:** the Bonjour service types the app searches for must be listed
  under `NSBonjourServices` in `ios/Runner/Info.plist`. Keep that list in sync
  with `lib/services/device_discovery_service.dart`. iOS skips the UPnP search
  because sending multicast packets needs a special entitlement from Apple.
- **iOS:** a maximum of 64 notifications can be pending, so the app schedules
  the next 60 reminders and refreshes them whenever it opens or data changes.
