import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../models/models.dart';

class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key});
  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final app = AppState.instance;
  List<Question>? qs;

  @override
  void initState() {
    super.initState();
    app.settingsStore.loadQuestions().then((v) => setState(() => qs = v));
  }

  Future<void> _save() => app.settingsStore.saveQuestions(qs!);

  Future<void> _move(int from, int to) async {
    setState(() => qs!.insert(to, qs!.removeAt(from)));
    await _save();
  }

  Future<void> _delete(int i) async {
    final q = qs![i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete question?'),
        content: Text(q.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => qs!.removeAt(i));
    await _save();
  }

  Future<void> _edit([Question? q]) async {
    final result = await Navigator.push<Question>(
        context, MaterialPageRoute(builder: (_) => QuestionEditor(question: q)));
    if (result == null) return;
    setState(() {
      final i = qs!.indexWhere((x) => x.id == result.id);
      i < 0 ? qs!.add(result) : qs![i] = result;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final list = qs;
    return Scaffold(
      appBar: AppBar(title: const Text('Questions')),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('No questions yet. Tap + to add one.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  buildDefaultDragHandles: false,
                  itemCount: list.length,
                  header: const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Drag the handle or use the arrows to change the order questions are asked.',
                        style: TextStyle(fontSize: 12)),
                  ),
                  onReorder: (a, b) => _move(a, b > a ? b - 1 : b),
                  itemBuilder: (_, i) {
                    final q = list[i];
                    return ListTile(
                      key: ValueKey(q.id),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(q.text),
                      subtitle: Text(_subtitle(q)),
                      onTap: () => _edit(q),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: i == 0 ? null : () => _move(i, i - 1),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: i == list.length - 1 ? null : () => _move(i, i + 1),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _delete(i),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }

  String _subtitle(Question q) => switch (q.type) {
        QuestionType.single => 'Single choice: ${q.options.join(', ')}${q.allowOther ? ', Other…' : ''}',
        QuestionType.multi => 'Multiple choice: ${q.options.join(', ')}${q.allowOther ? ', Other…' : ''}',
        QuestionType.text => 'Free text',
        QuestionType.scale => 'Scale ${q.scaleMin}–${q.scaleMax}',
      };
}

class QuestionEditor extends StatefulWidget {
  const QuestionEditor({super.key, this.question});
  final Question? question;
  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late Question q;
  late TextEditingController textC, optionsC, minC, maxC, minLabelC, maxLabelC;

  @override
  void initState() {
    super.initState();
    final src = widget.question;
    q = src == null
        ? Question(id: const Uuid().v4(), text: '')
        : Question.fromJson(src.toJson()); // copy
    textC = TextEditingController(text: q.text);
    optionsC = TextEditingController(text: q.options.join('\n'));
    minC = TextEditingController(text: q.scaleMin.toString());
    maxC = TextEditingController(text: q.scaleMax.toString());
    minLabelC = TextEditingController(text: q.scaleMinLabel);
    maxLabelC = TextEditingController(text: q.scaleMaxLabel);
  }

  void _done() {
    q.text = textC.text.trim();
    if (q.text.isEmpty) return;
    q.options = optionsC.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    q.scaleMin = int.tryParse(minC.text) ?? 1;
    q.scaleMax = int.tryParse(maxC.text) ?? 7;
    if (q.scaleMax <= q.scaleMin) q.scaleMax = q.scaleMin + 1;
    q.scaleMinLabel = minLabelC.text.trim();
    q.scaleMaxLabel = maxLabelC.text.trim();
    Navigator.pop(context, q);
  }

  @override
  Widget build(BuildContext context) {
    final hasOptions = q.type == QuestionType.single || q.type == QuestionType.multi;
    return Scaffold(
      appBar: AppBar(title: Text(widget.question == null ? 'New question' : 'Edit question'), actions: [
        TextButton(onPressed: _done, child: const Text('Done')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: textC,
          decoration: const InputDecoration(labelText: 'Question text', border: OutlineInputBorder()),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<QuestionType>(
          initialValue: q.type,
          decoration: const InputDecoration(labelText: 'Answer type', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: QuestionType.single, child: Text('Single choice')),
            DropdownMenuItem(value: QuestionType.multi, child: Text('Multiple choice (check all that apply)')),
            DropdownMenuItem(value: QuestionType.text, child: Text('Free text')),
            DropdownMenuItem(value: QuestionType.scale, child: Text('Number scale / slider')),
          ],
          onChanged: (v) => setState(() => q.type = v!),
        ),
        const SizedBox(height: 12),
        if (hasOptions) ...[
          TextField(
            controller: optionsC,
            decoration: const InputDecoration(
                labelText: 'Options (one per line)', border: OutlineInputBorder(), alignLabelWithHint: true),
            maxLines: 8,
            minLines: 4,
          ),
          SwitchListTile(
            title: const Text('Include an "Other" option with a text field'),
            value: q.allowOther,
            onChanged: (v) => setState(() => q.allowOther = v),
          ),
        ],
        if (q.type == QuestionType.scale) ...[
          Row(children: [
            Expanded(child: TextField(controller: minC, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: maxC, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: minLabelC,
              decoration: const InputDecoration(labelText: 'Label at min (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: maxLabelC,
              decoration: const InputDecoration(labelText: 'Label at max (optional)', border: OutlineInputBorder())),
        ],
      ]),
    );
  }
}
