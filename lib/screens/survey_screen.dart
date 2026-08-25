import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key, required this.promptId});
  final int promptId;
  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final app = AppState.instance;
  PromptRecord? prompt;
  List<Question> questions = [];
  final answers = <String, dynamic>{};
  final otherText = <String, TextEditingController>{};
  final otherSelected = <String, bool>{};
  bool submitting = false;
  bool alreadyDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var p = await app.db.byId(widget.promptId);
    questions = await app.settingsStore.loadQuestions();
    if (p == null) {
      p = PromptRecord(id: widget.promptId, uid: 'unknown-${widget.promptId}', scheduledAt: DateTime.now());
      await app.db.insert(p);
    }
    if (p.status == PromptStatus.answered) {
      alreadyDone = true;
    } else {
      // Tapping the notification counts as opening it, even if our local
      // bookkeeping had already marked it expired.
      p.status = PromptStatus.opened;
      p.openedAt ??= DateTime.now();
      await app.db.update(p);
    }
    for (final q in questions) {
      otherText[q.id] = TextEditingController();
      otherSelected[q.id] = false;
    }
    setState(() => prompt = p);
  }

  Future<void> _submit() async {
    setState(() => submitting = true);
    final p = prompt!;
    final out = <String, dynamic>{};
    for (final q in questions) {
      var v = answers[q.id];
      final other = otherText[q.id]!.text.trim();
      switch (q.type) {
        case QuestionType.single:
          if (otherSelected[q.id] == true) v = 'Other: $other';
        case QuestionType.multi:
          final list = List<String>.from(v ?? const []);
          if (otherSelected[q.id] == true) list.add('Other: $other');
          v = list;
        case QuestionType.text:
          v = other;
        case QuestionType.scale:
          break;
      }
      if (v != null && !(v is String && v.isEmpty) && !(v is List && v.isEmpty)) out[q.id] = v;
    }
    p.answers = out;
    p.status = PromptStatus.answered;
    p.submittedAt = DateTime.now();
    await app.db.update(p);
    await app.notifications.cancel(p.id);
    app.notifyChanged();
    app.uploader.syncAll().then((_) => app.notifyChanged()); // retried later if offline
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Thanks!')));
  }

  @override
  Widget build(BuildContext context) {
    final p = prompt;
    return Scaffold(
      appBar: AppBar(title: const Text('Quick survey')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : alreadyDone
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('This prompt was already answered.')))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final q in questions) _questionCard(q),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: submitting ? null : _submit,
                    child: const Text('Submit'),
                  ),
                  const SizedBox(height: 32),
                ]),
    );
  }

  Widget _questionCard(Question q) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.text, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          switch (q.type) {
            QuestionType.single => _single(q),
            QuestionType.multi => _multi(q),
            QuestionType.text => _textField(q, 'Your answer'),
            QuestionType.scale => _scale(q),
          },
        ]),
      ),
    );
  }

  Widget _single(Question q) => Column(children: [
        for (final o in q.options)
          RadioListTile<String>(
            dense: true,
            title: Text(o),
            value: o,
            groupValue: otherSelected[q.id] == true ? null : answers[q.id] as String?,
            onChanged: (v) => setState(() {
              answers[q.id] = v;
              otherSelected[q.id] = false;
            }),
          ),
        if (q.allowOther) ...[
          RadioListTile<String>(
            dense: true,
            title: const Text('Other'),
            value: '__other__',
            groupValue: otherSelected[q.id] == true ? '__other__' : null,
            onChanged: (_) => setState(() {
              otherSelected[q.id] = true;
              answers.remove(q.id);
            }),
          ),
          if (otherSelected[q.id] == true) _textField(q, 'Please specify'),
        ],
      ]);

  Widget _multi(Question q) {
    final sel = (answers[q.id] as List?)?.cast<String>() ?? <String>[];
    return Column(children: [
      for (final o in q.options)
        CheckboxListTile(
          dense: true,
          title: Text(o),
          value: sel.contains(o),
          onChanged: (v) => setState(() {
            final l = List<String>.from(sel);
            v == true ? l.add(o) : l.remove(o);
            answers[q.id] = l;
          }),
        ),
      if (q.allowOther) ...[
        CheckboxListTile(
          dense: true,
          title: const Text('Other'),
          value: otherSelected[q.id] == true,
          onChanged: (v) => setState(() => otherSelected[q.id] = v == true),
        ),
        if (otherSelected[q.id] == true) _textField(q, 'Please specify'),
      ],
    ]);
  }

  Widget _textField(Question q, String hint) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TextField(
          controller: otherText[q.id],
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
          maxLines: 3,
          minLines: 1,
        ),
      );

  Widget _scale(Question q) {
    final v = (answers[q.id] as num?)?.toDouble();
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${q.scaleMin} ${q.scaleMinLabel}'),
        Text(v == null ? '—' : v.round().toString(), style: Theme.of(context).textTheme.titleLarge),
        Text('${q.scaleMaxLabel} ${q.scaleMax}'),
      ]),
      Slider(
        value: v ?? q.scaleMin.toDouble(),
        min: q.scaleMin.toDouble(),
        max: q.scaleMax.toDouble(),
        divisions: (q.scaleMax - q.scaleMin).clamp(1, 100),
        onChanged: (x) => setState(() => answers[q.id] = x.round()),
      ),
      if (v == null) const Text('Move the slider to answer', style: TextStyle(fontSize: 12)),
    ]);
  }
}
