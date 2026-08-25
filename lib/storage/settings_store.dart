import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Settings and question definitions live in SharedPreferences as JSON.
/// They are keyed with a schema version so future app updates can migrate
/// old data instead of discarding it.
class SettingsStore {
  static const _settingsKey = 'settings';
  static const _questionsKey = 'questions';
  static const _schemaKey = 'schema_version';
  static const currentSchema = 1;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> migrateIfNeeded() async {
    final p = await _prefs;
    final v = p.getInt(_schemaKey) ?? 0;
    if (v == 0) {
      // Fresh install (or pre-versioned data): nothing to migrate.
      await p.setInt(_schemaKey, currentSchema);
    }
    // Future: if (v < 2) { ...transform stored JSON...; await p.setInt(_schemaKey, 2); }
  }

  Future<AppSettings> loadSettings() async {
    final p = await _prefs;
    final s = p.getString(_settingsKey);
    if (s == null) return AppSettings();
    return AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings s) async {
    final p = await _prefs;
    await p.setString(_settingsKey, jsonEncode(s.toJson()));
  }

  Future<List<Question>> loadQuestions() async {
    final p = await _prefs;
    final s = p.getString(_questionsKey);
    if (s == null) {
      // Persist defaults immediately so question ids stay stable.
      final qs = defaultQuestions();
      await saveQuestions(qs);
      return qs;
    }
    return (jsonDecode(s) as List)
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveQuestions(List<Question> qs) async {
    final p = await _prefs;
    await p.setString(_questionsKey, jsonEncode(qs.map((q) => q.toJson()).toList()));
  }

  static List<Question> defaultQuestions() => [
        Question(
          id: const Uuid().v4(),
          text: 'What are you doing right now?',
          options: ['Working', 'Eating', 'Socializing', 'Resting', 'Commuting'],
        ),
        Question(
          id: const Uuid().v4(),
          text: 'How are you feeling?',
          type: QuestionType.scale,
          scaleMin: 1,
          scaleMax: 7,
          scaleMinLabel: 'Very bad',
          scaleMaxLabel: 'Very good',
        ),
      ];
}
