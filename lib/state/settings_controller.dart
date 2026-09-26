import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../models/app_settings.dart';

/// Holds the user's settings, saves every change, and notifies listening
/// widgets so they can rebuild.
class SettingsController extends ChangeNotifier {
  SettingsController(this._repository) : _settings = _repository.load();

  final SettingsRepository _repository;
  AppSettings _settings;

  AppSettings get settings => _settings;

  /// Replaces the current settings. Typically called with
  /// `settings.copyWith(...)`.
  Future<void> update(AppSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    await _repository.save(newSettings);
  }

  /// Restores every setting to its default value.
  Future<void> reset() async {
    _settings = const AppSettings();
    await _repository.deleteAll();
    notifyListeners();
  }
}
