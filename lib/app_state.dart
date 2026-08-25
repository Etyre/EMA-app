import 'package:flutter/foundation.dart';

import 'services/notification_service.dart';
import 'services/scheduler.dart';
import 'services/uploader.dart';
import 'storage/db.dart';
import 'storage/settings_store.dart';

/// Simple service locator so screens can reach shared services.
class AppState {
  AppState._();
  static final AppState instance = AppState._();

  /// Bumped whenever prompt data changes so screens can refresh.
  final changes = ValueNotifier<int>(0);
  void notifyChanged() => changes.value++;

  final settingsStore = SettingsStore();
  final db = PromptDb();
  final notifications = NotificationService();
  late final scheduler = Scheduler(db, notifications, settingsStore);
  late final uploader = Uploader(db, settingsStore);

  /// Housekeeping run whenever the app comes to the foreground.
  Future<void> housekeeping() async {
    await scheduler.expireStale();
    await scheduler.topUp();
    await uploader.syncAll();
    notifyChanged();
  }
}
