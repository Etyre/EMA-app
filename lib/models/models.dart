import 'dart:convert';

/// Types of survey question supported by the editor and survey screen.
enum QuestionType { single, multi, text, scale }

class Question {
  Question({
    required this.id,
    required this.text,
    this.type = QuestionType.single,
    List<String>? options,
    this.allowOther = true,
    this.scaleMin = 1,
    this.scaleMax = 7,
    this.scaleMinLabel = '',
    this.scaleMaxLabel = '',
  }) : options = options ?? [];

  String id;
  String text;
  QuestionType type;
  List<String> options;
  bool allowOther; // single/multi: show an "Other" choice with a text field
  int scaleMin;
  int scaleMax;
  String scaleMinLabel;
  String scaleMaxLabel;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'type': type.name,
        'options': options,
        'allowOther': allowOther,
        'scaleMin': scaleMin,
        'scaleMax': scaleMax,
        'scaleMinLabel': scaleMinLabel,
        'scaleMaxLabel': scaleMaxLabel,
      };

  static Question fromJson(Map<String, dynamic> j) => Question(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        type: QuestionType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => QuestionType.single,
        ),
        options: (j['options'] as List?)?.cast<String>() ?? [],
        allowOther: j['allowOther'] as bool? ?? true,
        scaleMin: j['scaleMin'] as int? ?? 1,
        scaleMax: j['scaleMax'] as int? ?? 7,
        scaleMinLabel: j['scaleMinLabel'] as String? ?? '',
        scaleMaxLabel: j['scaleMaxLabel'] as String? ?? '',
      );
}

/// Minutes since midnight, used for the active time window.
class MinuteOfDay {
  const MinuteOfDay(this.minutes);
  final int minutes;
  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class AppSettings {
  AppSettings({
    this.enabled = false,
    this.minIntervalMinutes = 45,
    this.maxIntervalMinutes = 120,
    this.visibilityMinutes = 15,
    this.windowStart = const MinuteOfDay(8 * 60),
    this.windowEnd = const MinuteOfDay(22 * 60),
    this.sheetUrl = defaultSheetUrl,
    this.sound = 'chime',
  });

  /// Apps Script web-app URL baked in at build time via
  /// `--dart-define=SHEET_URL=...` (see `.env.example` / README). Empty if not
  /// provided; the user can always set it in Settings.
  static const defaultSheetUrl = String.fromEnvironment('SHEET_URL');

  bool enabled;
  int minIntervalMinutes;
  int maxIntervalMinutes;
  int visibilityMinutes; // how long a notification stays visible
  MinuteOfDay windowStart;
  MinuteOfDay windowEnd;
  String sheetUrl; // Apps Script web-app URL
  String sound; // key from [NotificationSounds.all]

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'minIntervalMinutes': minIntervalMinutes,
        'maxIntervalMinutes': maxIntervalMinutes,
        'visibilityMinutes': visibilityMinutes,
        'windowStart': windowStart.minutes,
        'windowEnd': windowEnd.minutes,
        'sheetUrl': sheetUrl,
        'sound': sound,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        enabled: j['enabled'] as bool? ?? false,
        minIntervalMinutes: j['minIntervalMinutes'] as int? ?? 45,
        maxIntervalMinutes: j['maxIntervalMinutes'] as int? ?? 120,
        visibilityMinutes: j['visibilityMinutes'] as int? ?? 15,
        windowStart: MinuteOfDay(j['windowStart'] as int? ?? 8 * 60),
        windowEnd: MinuteOfDay(j['windowEnd'] as int? ?? 22 * 60),
        sheetUrl: j['sheetUrl'] as String? ?? defaultSheetUrl,
        sound: NotificationSounds.all.containsKey(j['sound']) ? j['sound'] as String : 'chime',
      );
}

enum PromptStatus { pending, opened, answered, expired }

/// One scheduled notification ("signal") and, if answered, its answers.
class PromptRecord {
  PromptRecord({
    required this.id,
    required this.uid,
    required this.scheduledAt,
    this.status = PromptStatus.pending,
    this.openedAt,
    this.submittedAt,
    this.answers = const {},
    this.uploaded = false,
    this.uploadAttempts = 0,
    this.lastUploadError,
  });

  final int id; // also used as the notification id
  final String uid; // stable unique id used for de-duplication in the sheet
  final DateTime scheduledAt;
  PromptStatus status;
  DateTime? openedAt;
  DateTime? submittedAt;
  /// questionId -> answer. Answer is String, List<String>, or num.
  Map<String, dynamic> answers;
  bool uploaded;
  int uploadAttempts;
  String? lastUploadError;

  Map<String, dynamic> toRow() => {
        'id': id,
        'uid': uid,
        'scheduled_at': scheduledAt.millisecondsSinceEpoch,
        'status': status.name,
        'opened_at': openedAt?.millisecondsSinceEpoch,
        'submitted_at': submittedAt?.millisecondsSinceEpoch,
        'answers': jsonEncode(answers),
        'uploaded': uploaded ? 1 : 0,
        'upload_attempts': uploadAttempts,
        'last_upload_error': lastUploadError,
      };

  static PromptRecord fromRow(Map<String, dynamic> r) => PromptRecord(
        id: r['id'] as int,
        uid: r['uid'] as String,
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(r['scheduled_at'] as int),
        status: PromptStatus.values.firstWhere((s) => s.name == r['status']),
        openedAt: r['opened_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['opened_at'] as int),
        submittedAt: r['submitted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['submitted_at'] as int),
        answers: (jsonDecode(r['answers'] as String? ?? '{}') as Map)
            .cast<String, dynamic>(),
        uploaded: (r['uploaded'] as int? ?? 0) == 1,
        uploadAttempts: r['upload_attempts'] as int? ?? 0,
        lastUploadError: r['last_upload_error'] as String?,
      );
}

/// Bundled notification sounds. Key = file name (without extension) in
/// assets/sounds/ and android/res/raw/. 'default' = the OS default sound.
class NotificationSounds {
  static const all = <String, String>{
    'default': 'System default',
    'low_hero': 'Two-note (low)',
    'low_bell': 'Low bell',
    'wood': 'Wood block (low)',
    'low_two_tone': 'Two-tone (low)',
    'hum': 'Hum (low, soft)',
    'chime': 'Chime',
    'ding': 'Ding',
    'marimba': 'Marimba',
    'rising': 'Rising',
    'triple_beep': 'Triple beep',
    'soft_pulse': 'Soft pulse',
  };
  static const files = ['low_hero', 'low_bell', 'wood', 'low_two_tone', 'hum', 'chime', 'ding', 'marimba', 'rising', 'triple_beep', 'soft_pulse'];
}
