import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../storage/db.dart';
import '../storage/settings_store.dart';

/// Pushes answered/expired prompts to the Google Apps Script web app.
/// Rows are kept locally with an `uploaded` flag and retried until they succeed,
/// so an offline submission is never lost.
class Uploader {
  Uploader(this.db, this.settingsStore);
  final PromptDb db;
  final SettingsStore settingsStore;
  bool _busy = false;

  Future<int> syncAll() async {
    if (_busy) return 0;
    _busy = true;
    try {
      final s = await settingsStore.loadSettings();
      if (s.sheetUrl.trim().isEmpty) return 0;
      final questions = await settingsStore.loadQuestions();
      var ok = 0;
      for (final p in await db.needingUpload()) {
        if (await _upload(p, s.sheetUrl.trim(), questions)) ok++;
      }
      return ok;
    } finally {
      _busy = false;
    }
  }

  Future<bool> _upload(PromptRecord p, String url, List<Question> questions) async {
    final answers = <String, dynamic>{};
    for (final q in questions) {
      final v = p.answers[q.id];
      answers[q.text] = v is List ? v.join('; ') : (v ?? '');
    }
    final body = jsonEncode({
      'uid': p.uid,
      'status': p.status.name,
      'scheduled_at': p.scheduledAt.toIso8601String(),
      'opened_at': p.openedAt?.toIso8601String() ?? '',
      'submitted_at': p.submittedAt?.toIso8601String() ?? '',
      'timezone': DateTime.now().timeZoneName,
      'answers': answers,
    });
    try {
      final resp = await _post(Uri.parse(url), body);
      if (resp.statusCode == 200 && resp.body.contains('"ok":true')) {
        p.uploaded = true;
        p.lastUploadError = null;
      } else {
        p.lastUploadError = 'HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}';
      }
    } catch (e) {
      p.lastUploadError = e.toString();
    }
    p.uploadAttempts++;
    await db.update(p);
    return p.uploaded;
  }

  /// Apps Script answers POSTs with a 302 to a one-time URL; Dart doesn't follow
  /// redirects for POST, so fetch the redirect target with GET.
  Future<http.Response> _post(Uri uri, String body) async {
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = body
      ..followRedirects = false;
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    var resp = await http.Response.fromStream(streamed);
    if ((resp.statusCode == 301 || resp.statusCode == 302 || resp.statusCode == 303) &&
        resp.headers['location'] != null) {
      resp = await http.get(Uri.parse(resp.headers['location']!)).timeout(const Duration(seconds: 30));
    }
    return resp;
  }
}
