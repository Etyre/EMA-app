import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models/models.dart';
import 'history_screen.dart';
import 'questions_screen.dart';
import 'settings_screen.dart';
import 'survey_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final app = AppState.instance;
  AppSettings? settings;
  List<PromptRecord> upcoming = [];
  int pendingUploads = 0;
  int answered = 0, missed = 0;

  @override
  void initState() {
    super.initState();
    app.changes.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    app.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    settings = await app.settingsStore.loadSettings();
    upcoming = await app.db.pendingAfter(DateTime.now());
    pendingUploads = (await app.db.needingUpload()).length;
    answered = (await app.db.byStatus(PromptStatus.answered)).length;
    missed = (await app.db.byStatus(PromptStatus.expired)).length;
    if (mounted) setState(() {});
  }

  Future<void> _toggle(bool v) async {
    settings!.enabled = v;
    await app.settingsStore.saveSettings(settings!);
    if (v) {
      await app.scheduler.topUp();
    } else {
      await app.scheduler.rebuild(); // cancels future prompts
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final fmt = DateFormat('EEE d MMM, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('EMA Sampler'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () async {
          await app.housekeeping();
          _refresh();
        }),
      ]),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: SwitchListTile(
                  title: const Text('Sampling active'),
                  subtitle: Text(s.enabled
                      ? 'Prompts every ${s.minIntervalMinutes}–${s.maxIntervalMinutes} min, '
                          '${s.windowStart.label}–${s.windowEnd.label}'
                      : 'Paused'),
                  value: s.enabled,
                  onChanged: _toggle,
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('Scheduled prompts'),
                  subtitle: Text(upcoming.isEmpty ? 'None' : '${upcoming.length} queued over the next few days'),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text('$answered answered · $missed missed'),
                  subtitle: Text(pendingUploads == 0
                      ? (s.sheetUrl.isEmpty ? 'Google Sheet not configured' : 'All synced to Google Sheet')
                      : '$pendingUploads waiting to upload'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen())).then((_) => _refresh()),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Questions'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const QuestionsScreen())).then((_) => _refresh()),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.settings),
                label: const Text('Settings'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _refresh()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.notifications_active),
                label: const Text('Send test prompt now'),
                onPressed: () async {
                  final rec = await app.scheduler.testPrompt();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Test notification sent (check with app in background too).'),
                    action: SnackBarAction(
                        label: 'Open',
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => SurveyScreen(promptId: rec.id)))),
                  ));
                  _refresh();
                },
              ),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 24),
                ExpansionTile(
                  title: const Text('Upcoming prompts'),
                  subtitle: const Text('Hidden by default — peeking spoils the randomness'),
                  initiallyExpanded: false,
                  children: [
                    for (final p in upcoming.take(10)) ListTile(dense: true, title: Text(fmt.format(p.scheduledAt))),
                  ],
                ),
              ],
            ]),
    );
  }
}
