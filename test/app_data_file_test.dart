import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/app_data_file.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';

void main() {
  final file = AppDataFile(
    settings: const AppSettings(themeMode: ThemeMode.dark),
    homeItems: [
      HomeItem(
        id: 'furnace',
        name: 'Furnace',
        category: HomeItemCategory.hvac,
        tasks: [
          MaintenanceTask(
            id: 'filter',
            title: 'Replace filter',
            interval: const MaintenanceInterval.months(3),
            startDate: DateTime(2026, 1, 1),
          ),
        ],
      ),
    ],
    assistChats: const [],
  );
  final savedAt = DateTime(2026, 11, 4, 9, 30);

  /// [file] saved, with [change] made to its JSON.
  String savedWith(void Function(Map<String, dynamic> json) change) {
    final json = jsonDecode(file.encode(savedAt)) as Map<String, dynamic>;
    change(json);
    return jsonEncode(json);
  }

  /// The problem [AppDataFile.decode] finds with [contents].
  DataFileProblem? problemWith(String contents) {
    try {
      AppDataFile.decode(contents);
      return null;
    } on IncompatibleDataFileException catch (error) {
      return error.problem;
    }
  }

  test('a saved file loads back the same', () {
    final loaded = AppDataFile.decode(file.encode(savedAt));

    expect(loaded.settings.toJson(), file.settings.toJson());
    expect(
      [for (final item in loaded.homeItems) item.toJson()],
      [for (final item in file.homeItems) item.toJson()],
    );
    expect(loaded.assistChats, isEmpty);
    expect(loaded.savedAt, savedAt);
    expect(loaded.taskCount, 1);
  });

  test('files that aren\'t the app\'s data are turned away', () {
    expect(problemWith('Shopping list'), DataFileProblem.notAppData);
    expect(problemWith('[1, 2, 3]'), DataFileProblem.notAppData);
    expect(
      problemWith(savedWith((json) => json['format'] = 'other-app')),
      DataFileProblem.notAppData,
    );
    // Saved before files were marked with a format and version, so there's
    // no telling whether this version can read it.
    expect(
      problemWith(
        savedWith((json) {
          json.remove('format');
          json.remove('version');
        }),
      ),
      DataFileProblem.notAppData,
    );
  });

  test('files from other versions of the app are turned away', () {
    expect(
      problemWith(
        savedWith((json) => json['version'] = AppDataFile.version + 1),
      ),
      DataFileProblem.otherVersion,
    );
    expect(
      problemWith(savedWith((json) => json.remove('version'))),
      DataFileProblem.otherVersion,
    );
  });

  test('damaged files are turned away', () {
    expect(
      problemWith(savedWith((json) => json['homeItems'] = 'Furnace')),
      DataFileProblem.damaged,
    );
    expect(
      problemWith(savedWith((json) => json.remove('settings'))),
      DataFileProblem.damaged,
    );
    expect(
      problemWith(
        savedWith((json) => (json['settings'] as Map)['themeMode'] = 'sparkly'),
      ),
      DataFileProblem.damaged,
    );
  });
}
