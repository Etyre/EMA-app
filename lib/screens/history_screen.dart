import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models/models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final app = AppState.instance;
  List<PromptRecord>? items;
  List<Question> questions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    questions = await app.settingsStore.loadQuestions();
    final h = await app.db.history();
    setState(() => items = h);
  }

  String _csv() {
    String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final head = ['uid', 'status', 'scheduled_at', 'opened_at', 'submitted_at', 'uploaded', ...questions.map((q) => q.text)];
    final rows = [head.map(esc).join(',')];
    for (final p in items!) {
      rows.add([
        p.uid, p.status.name, p.scheduledAt.toIso8601String(),
        p.openedAt?.toIso8601String(), p.submittedAt?.toIso8601String(), p.uploaded,
        ...questions.map((q) { final v = p.answers[q.id]; return v is List ? v.join('; ') : v; }),
      ].map(esc).join(','));
    }
    return rows.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM HH:mm');
    final list = items;
    return Scaffold(
      appBar: AppBar(title: const Text('History'), actions: [
        IconButton(
          tooltip: 'Copy CSV',
          icon: const Icon(Icons.copy),
          onPressed: list == null ? null : () async {
            await Clipboard.setData(ClipboardData(text: _csv()));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
            }
          },
        ),
        IconButton(
          tooltip: 'Retry uploads',
          icon: const Icon(Icons.cloud_upload),
          onPressed: () async {
            final n = await app.uploader.syncAll();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded $n')));
            }
            _load();
          },
        ),
      ]),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final p = list[i];
                final answered = p.status == PromptStatus.answered;
                return ExpansionTile(
                  leading: Icon(
                    answered ? Icons.check_circle : Icons.cancel,
                    color: answered ? Colors.green : Colors.grey,
                  ),
                  title: Text(fmt.format(p.scheduledAt)),
                  subtitle: Text('${p.status.name}'
                      '${p.uploaded ? ' · uploaded' : (p.lastUploadError != null ? ' · upload failed' : '')}'),
                  children: [
                    for (final q in questions)
                      ListTile(
                        dense: true,
                        title: Text(q.text),
                        subtitle: Text(() {
                          final v = p.answers[q.id];
                          return v == null ? '—' : (v is List ? v.join('; ') : v.toString());
                        }()),
                      ),
                    if (p.lastUploadError != null)
                      ListTile(dense: true, title: const Text('Upload error'), subtitle: Text(p.lastUploadError!)),
                  ],
                );
              },
            ),
    );
  }
}
