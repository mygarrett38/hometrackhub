import 'dart:convert';

import '../models/app_settings.dart';
import '../models/assist_chat.dart';
import '../models/home_item.dart';

/// All of the user's data as a file they can save, share, and load back in:
/// their settings, home items (with their tasks and expenses) and chats.
///
/// Each file is marked with [format] and [version], so only files this
/// version of the app knows how to read are loaded.
class AppDataFile {
  const AppDataFile({
    required this.settings,
    required this.homeItems,
    required this.assistChats,
    this.savedAt,
  });

  /// Marks a file as this app's data.
  static const format = 'hometrackhub-data';

  /// The version of the file's layout. Raise it whenever the data changes in
  /// a way this version of the app couldn't read, so files from other
  /// versions are turned away instead of loaded wrongly.
  static const version = 1;

  final AppSettings settings;
  final List<HomeItem> homeItems;
  final List<AssistChat> assistChats;

  /// When the file was saved, if it says.
  final DateTime? savedAt;

  /// How many tasks the home items have between them.
  int get taskCount =>
      homeItems.fold(0, (count, item) => count + item.tasks.length);

  /// The file's contents, saved at [savedAt].
  String encode(DateTime savedAt) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'exportedAt': savedAt.toIso8601String(),
      'settings': settings.toJson(),
      'homeItems': [for (final item in homeItems) item.toJson()],
      'assistChats': [for (final chat in assistChats) chat.toJson()],
    });
  }

  /// Reads a file made by [encode].
  ///
  /// Throws an [IncompatibleDataFileException] if the file isn't this app's
  /// data, was saved by a version of the app whose files this one can't
  /// read, or is damaged.
  static AppDataFile decode(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      throw const IncompatibleDataFileException(DataFileProblem.notAppData);
    }
    if (json is! Map<String, dynamic> || json['format'] != format) {
      throw const IncompatibleDataFileException(DataFileProblem.notAppData);
    }
    if (json['version'] != version) {
      throw const IncompatibleDataFileException(DataFileProblem.otherVersion);
    }

    try {
      final savedAt = json['exportedAt'] as String?;
      return AppDataFile(
        settings: AppSettings.fromJson(
          json['settings'] as Map<String, dynamic>,
        ),
        homeItems: [
          for (final item in json['homeItems'] as List<dynamic>)
            HomeItem.fromJson(item as Map<String, dynamic>),
        ],
        assistChats: [
          for (final chat in json['assistChats'] as List<dynamic>)
            AssistChat.fromJson(chat as Map<String, dynamic>),
        ],
        savedAt: savedAt == null ? null : DateTime.tryParse(savedAt),
      );
    } catch (_) {
      // Anything missing or of the wrong kind, such as a list where a home
      // item should be, or a setting this version doesn't know.
      throw const IncompatibleDataFileException(DataFileProblem.damaged);
    }
  }
}

/// Why a file couldn't be loaded.
enum DataFileProblem {
  /// The file isn't data saved by this app.
  notAppData,

  /// The file was saved by a version of the app that saves data in a way
  /// this version can't read.
  otherVersion,

  /// The file looks like this app's data, but parts are missing or wrong.
  damaged,
}

/// Thrown by [AppDataFile.decode] for a file that can't be loaded.
class IncompatibleDataFileException implements Exception {
  const IncompatibleDataFileException(this.problem);

  final DataFileProblem problem;

  @override
  String toString() => 'IncompatibleDataFileException(${problem.name})';
}
