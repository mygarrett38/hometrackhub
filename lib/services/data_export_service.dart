import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Saves or shares a copy of the user's data as a file.
abstract class DataExportService {
  /// Asks the user where to save [contents] as [fileName]. Returns whether
  /// it was saved, which is false if the user cancelled.
  Future<bool> save(String fileName, String contents);

  /// Opens the device's share sheet with [contents] attached as [fileName].
  ///
  /// [origin] is where the share sheet points from on tablets, such as the
  /// button that opened it.
  Future<void> share(String fileName, String contents, {Rect? origin});
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

  static Uint8List _bytes(String contents) =>
      Uint8List.fromList(utf8.encode(contents));
}
