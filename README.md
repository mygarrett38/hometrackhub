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
| `lib/ui/screens/` | Screens, grouped by the tab they belong to: `upcoming/`, `home_items/` and `settings/`. |
| `lib/ui/widgets/` | Small widgets shared by several screens. |
| `test/` | Unit tests for the models, planner and catalog, plus widget tests. |

State is shared with the [provider](https://pub.dev/packages/provider)
package. `lib/main.dart` creates the controllers and services and provides
them to the widget tree.

## Platform notes

- **Launch screen:** the phone shows the logo while the app starts, then
  `lib/ui/screens/launch/launch_screen.dart` animates it into the app. The
  logo is stored once per platform, and all use the background `#F3F1EC`:
  - `assets/images/logo.png`: used by the animation, 1192px.
  - `android/app/src/main/res/drawable-xxxhdpi/splash.png`: Android 11 and
    older, the same 1192px image.
  - `android/app/src/main/res/drawable-xxxhdpi/android12splash.png`:
    Android 12 and newer, which show the logo inside a circle. 1152px,
    with the logo fitting inside a centered 768px circle.
  - `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png`:
    iOS, 894px.
- **App icon:** each platform has one icon image. Around the logo, each
  keeps the original image's own slightly shaded cream background:
  - `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png`:
    Android 8 and newer. Launchers crop this 432px layer to their own shape,
    so the logo must fit in the middle 264px circle. The layer is opaque;
    the matching background color is in `values/colors.xml`.
  - `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`: Android 7,
    a 192px rounded square with transparent corners.
  - `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`:
    iOS, a 1024px square with no transparency. iOS rounds the corners and
    Xcode makes the smaller sizes.
- **Android:** scheduled notifications need core library desugaring and the
  receivers declared in `AndroidManifest.xml`. Both are already configured.
- **iOS:** the Bonjour service types the app searches for must be listed
  under `NSBonjourServices` in `ios/Runner/Info.plist`. Keep that list in sync
  with `lib/services/device_discovery_service.dart`. iOS skips the UPnP search
  because sending multicast packets needs a special entitlement from Apple.
- **iOS:** a maximum of 64 notifications can be pending, so the app schedules
  the next 60 reminders and refreshes them whenever it opens or data changes.
