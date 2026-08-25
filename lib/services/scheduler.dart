import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../storage/db.dart';
import '../storage/settings_store.dart';
import 'notification_service.dart';

/// Generates random-interval prompt times inside the active window and keeps
/// a rolling horizon of them scheduled with the OS (iOS caps pending local
/// notifications at 64, so we keep well under that).
class Scheduler {
  Scheduler(this.db, this.notifications, this.settingsStore);

  final PromptDb db;
  final NotificationService notifications;
  final SettingsStore settingsStore;
  final _rng = Random();

  static const maxPending = 40;
  static const horizon = Duration(days: 3);

  /// Cancel every future prompt and regenerate from now. Use after settings change.
  Future<void> rebuild() async {
    final future = await db.pendingAfter(DateTime.now());
    for (final p in future) {
      await notifications.cancel(p.id);
    }
    await db.deleteIds(future.map((p) => p.id).toList());
    await topUp();
  }

  /// Ensure future prompts exist up to [horizon] / [maxPending].
  Future<void> topUp() async {
    final s = await settingsStore.loadSettings();
    if (!s.enabled) return;
    final now = DateTime.now();
    final future = await db.pendingAfter(now);
    var last = future.isEmpty ? now : future.last.scheduledAt;
    var count = future.length;
    final limit = now.add(horizon);
    var id = await db.nextId();
    while (count < maxPending) {
      last = _next(last, s);
      if (last.isAfter(limit)) break;
      final rec = PromptRecord(id: id++, uid: const Uuid().v4(), scheduledAt: last);
      await db.insert(rec);
      await notifications.schedule(
        id: rec.id,
        when: rec.scheduledAt,
        visibleFor: Duration(minutes: s.visibilityMinutes),
        sound: s.sound,
      );
      count++;
    }
  }

  DateTime _next(DateTime from, AppSettings s) {
    final minM = s.minIntervalMinutes;
    final maxM = max(s.maxIntervalMinutes, minM);
    final gapSec = (minM * 60) + _rng.nextInt(max(1, (maxM - minM) * 60 + 1));
    var t = from.add(Duration(seconds: gapSec));
    if (_inWindow(t, s)) return t;
    // Outside the active window: jump to the next window start plus a random
    // offset (0..max interval) so the first prompt of the day isn't always at
    // the same time.
    final start = _nextWindowStart(t, s);
    final offset = _rng.nextInt(maxM * 60 + 1);
    t = start.add(Duration(seconds: offset));
    return _inWindow(t, s) ? t : start.add(Duration(seconds: _rng.nextInt(minM * 60 + 1)));
  }

  static bool _inWindow(DateTime t, AppSettings s) {
    final m = t.hour * 60 + t.minute;
    final a = s.windowStart.minutes, b = s.windowEnd.minutes;
    if (a == b) return true; // 24-hour window
    return a < b ? (m >= a && m < b) : (m >= a || m < b); // handles overnight windows
  }

  static DateTime _nextWindowStart(DateTime t, AppSettings s) {
    var d = DateTime(t.year, t.month, t.day, s.windowStart.hour, s.windowStart.minute);
    if (!d.isAfter(t)) d = d.add(const Duration(days: 1));
    return d;
  }

  /// Mark prompts whose visibility period has elapsed without an answer as
  /// expired so they get logged as "unanswered". Returns their ids.
  Future<List<int>> expireStale() async {
    final s = await settingsStore.loadSettings();
    final cutoff = DateTime.now().subtract(Duration(minutes: s.visibilityMinutes));
    final ids = <int>[];
    for (final status in [PromptStatus.pending, PromptStatus.opened]) {
      for (final p in await db.byStatus(status)) {
        if (p.scheduledAt.isBefore(cutoff)) {
          p.status = PromptStatus.expired;
          await db.update(p);
          ids.add(p.id);
        }
      }
    }
    await notifications.dismissDelivered(ids);
    return ids;
  }

  /// Fire a prompt immediately (for testing).
  Future<PromptRecord> testPrompt() async {
    final s = await settingsStore.loadSettings();
    final rec = PromptRecord(id: await db.nextId(), uid: const Uuid().v4(), scheduledAt: DateTime.now());
    await db.insert(rec);
    await notifications.showNow(id: rec.id, visibleFor: Duration(minutes: s.visibilityMinutes), sound: s.sound);
    return rec;
  }
}
