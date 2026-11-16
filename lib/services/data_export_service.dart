import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// A file the user picked: its name and what's in it.
typedef OpenedFile = ({String name, String contents});

/// Saves or shares a copy of the user's data as a file, or opens one to
/// load it back in.
abstract class DataExportService {
  /// Asks the user where to save [contents] as [fileName]. Returns whether
  /// it was saved, which is false if the user cancelled.
  Future<bool> save(String fileName, String contents);

  /// Opens the device's share sheet with [contents] attached as [fileName].
  ///
  /// [origin] is where the share sheet points from on tablets, such as the
  /// button that opened it.
  Future<void> share(String fileName, String contents, {Rect? origin});

  /// Asks the user to pick a saved data file, returning it, or `null` if
  /// they cancelled.
  Future<OpenedFile?> open();
}

/// Uses the device's own save dialog and share sheet.
class DeviceDataExportService implements DataExportService {
  static const _mimeType = 'application/json';

  @override
  Future<bool> save(String fileName, String contents) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: _bytes(contents),
      mimeType: _mimeType,
    );
    return saved != null;
  }

  @override
  Future<void> share(String fileName, String contents, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(_bytes(contents), mimeType: _mimeType)],
        fileNameOverrides: [fileName],
        subject: 'HomeTrack Hub data',
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<OpenedFile?> open() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    // A file that isn't text can't be the app's data. Its contents are left
    // malformed rather than throwing, so it's turned away like any other
    // file that isn't.
    final contents = utf8.decode(
      await file.readAsBytes(),
      allowMalformed: true,
    );
    return (name: file.name, contents: contents);
  }

  static Uint8List _bytes(String contents) =>
      Uint8List.fromList(utf8.encode(contents));
}
