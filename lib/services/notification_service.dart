import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around flutter_local_notifications.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Emits the prompt id whenever the user taps a notification.
  final tapped = StreamController<int>.broadcast();

  /// Android fixes the sound per channel, so each sound gets its own channel.
  static String _channelId(String sound) => 'ema_prompts_$sound';

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload == 'preview') return;
        final id = int.tryParse(resp.payload ?? '');
        if (id != null) tapped.add(id);
      },
    );

    if (Platform.isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await impl?.requestNotificationsPermission();
      await impl?.requestExactAlarmsPermission();
      for (final key in NotificationSounds.all.keys) {
        await impl?.createNotificationChannel(AndroidNotificationChannel(
          _channelId(key),
          'Survey prompts (${NotificationSounds.all[key]})',
          description: 'Randomly timed survey prompts',
          importance: Importance.max,
          playSound: true,
          sound: key == 'default' ? null : RawResourceAndroidNotificationSound(key),
          enableVibration: true,
        ));
      }
    }
    if (Platform.isIOS) await _installIosSounds();
  }

  /// iOS plays custom notification sounds from the app bundle or from
  /// <app>/Library/Sounds. Copying the bundled assets there avoids having to
  /// touch the Xcode project.
  Future<void> _installIosSounds() async {
    try {
      final lib = await getLibraryDirectory();
      final dir = Directory('${lib.path}/Sounds');
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final f in NotificationSounds.files) {
        final out = File('${dir.path}/$f.wav');
        final data = await rootBundle.load('assets/sounds/$f.wav');
        if (await out.exists() && await out.length() == data.lengthInBytes) continue;
        await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
    } catch (e) {
      // Fall back to the default sound; scheduling still works.
    }
  }

  /// If the app was cold-launched by tapping a notification, return that id.
  Future<int?> launchPromptId() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp != true) return null;
    return int.tryParse(d?.notificationResponse?.payload ?? '');
  }

  NotificationDetails _details(Duration visibleFor, String sound) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId(sound),
          'Survey prompts (${NotificationSounds.all[sound] ?? sound})',
          channelDescription: 'Randomly timed survey prompts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: sound == 'default' ? null : RawResourceAndroidNotificationSound(sound),
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 400, 200, 400]),
          // Android removes the notification by itself after this long.
          timeoutAfter: visibleFor.inMilliseconds,
          category: AndroidNotificationCategory.reminder,
          fullScreenIntent: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: false,
          sound: sound == 'default' ? null : '$sound.wav',
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

  Future<void> schedule({
    required int id,
    required DateTime when,
    required Duration visibleFor,
    String sound = 'default',
    String title = 'Survey time',
    String body = 'Tap to answer a few quick questions.',
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _details(visibleFor, sound),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: id.toString(),
    );
  }

  Future<void> showNow({
    required int id,
    required Duration visibleFor,
    String sound = 'default',
    String title = 'Survey time',
    String body = 'Tap to answer a few quick questions.',
    String? payload,
  }) =>
      _plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: _details(visibleFor, sound),
          payload: payload ?? id.toString());

  /// Diagnostics for the settings screen.
  Future<String> diagnostics(String sound) async {
    final parts = <String>[];
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final perm = await ios?.checkPermissions();
      parts.add('notifications: ${perm?.isEnabled == true ? 'allowed' : 'NOT allowed'} '
          '(alert ${perm?.isAlertEnabled == true ? 'on' : 'off'}, '
          'sound ${perm?.isSoundEnabled == true ? 'on' : 'off'})');
      final lib = await getLibraryDirectory();
      final dir = Directory('${lib.path}/Sounds');
      final present = await dir.exists()
          ? await dir.list().map((e) => e.uri.pathSegments.last).toList()
          : const <String>[];
      parts.add('Library/Sounds: ${present.length} files at ${dir.path}');
      if (sound != 'default') {
        final f = File('${dir.path}/$sound.wav');
        parts.add(await f.exists() ? 'file ok (${await f.length()} B)' : 'sound file MISSING');
      }
      parts.add('pending=${(await _plugin.pendingNotificationRequests()).length}');
    }
    return parts.join(' · ');
  }

  /// Fire a throwaway notification so the user can hear a sound option.
  Future<void> previewSound(String sound) => showNow(
        id: 0x7FFF0000,
        visibleFor: const Duration(seconds: 10),
        sound: sound,
        title: 'Sound preview',
        body: NotificationSounds.all[sound] ?? sound,
        payload: 'preview',
      );

  Future<void> cancel(int id) => _plugin.cancel(id: id);
  Future<void> cancelAll() => _plugin.cancelAll();

  /// Remove already-delivered notifications for these ids (used on iOS,
  /// which has no native auto-dismiss timeout, when the app comes to the
  /// foreground after a prompt has expired).
  Future<void> dismissDelivered(Iterable<int> ids) async {
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  Future<List<int>> pendingIds() async =>
      (await _plugin.pendingNotificationRequests()).map((r) => r.id).toList();
}
