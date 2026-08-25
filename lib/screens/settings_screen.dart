import 'package:flutter/material.dart';

import 'package:audioplayers/audioplayers.dart';

import '../app_state.dart';
import '../models/models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final app = AppState.instance;
  AppSettings? s;
  final minC = TextEditingController();
  final maxC = TextEditingController();
  final visC = TextEditingController();
  final urlC = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    app.settingsStore.loadSettings().then((v) {
      minC.text = v.minIntervalMinutes.toString();
      maxC.text = v.maxIntervalMinutes.toString();
      visC.text = v.visibilityMinutes.toString();
      urlC.text = v.sheetUrl;
      setState(() => s = v);
    });
  }

  String? _posInt(String? v) {
    final n = int.tryParse(v ?? '');
    return (n == null || n <= 0) ? 'Enter a whole number > 0' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final minV = int.parse(minC.text), maxV = int.parse(maxC.text);
    if (maxV < minV) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max must be ≥ min')));
      return;
    }
    s!
      ..minIntervalMinutes = minV
      ..maxIntervalMinutes = maxV
      ..visibilityMinutes = int.parse(visC.text)
      ..sheetUrl = urlC.text.trim();
    await app.settingsStore.saveSettings(s!);
    await app.scheduler.rebuild();
    app.uploader.syncAll();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _preview(String sound) async {
    // Play in-app so the preview works regardless of notification settings...
    if (sound != 'default') {
      try {
        await _player.stop();
        await _player.play(AssetSource('sounds/$sound.wav'));
      } catch (_) {}
    }
    // ...and also fire a real notification so the OS behaviour can be checked.
    await app.notifications.previewSound(sound);
    final diag = await app.notifications.diagnostics(sound);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(sound == 'default'
          ? 'Sent a preview notification. $diag'
          : 'Playing ${NotificationSounds.all[sound]} and sent a preview notification. $diag'),
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final cur = start ? s!.windowStart : s!.windowEnd;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute));
    if (t == null) return;
    setState(() {
      final m = MinuteOfDay(t.hour * 60 + t.minute);
      start ? s!.windowStart = m : s!.windowEnd = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = s;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Timing', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: minC,
                  keyboardType: TextInputType.number,
                  validator: _posInt,
                  decoration: const InputDecoration(
                      labelText: 'Minimum interval between prompts (minutes)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: maxC,
                  keyboardType: TextInputType.number,
                  validator: _posInt,
                  decoration: const InputDecoration(
                      labelText: 'Maximum interval between prompts (minutes)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: visC,
                  keyboardType: TextInputType.number,
                  validator: _posInt,
                  decoration: const InputDecoration(
                      labelText: 'Notification stays visible for (minutes)',
                      helperText: 'Unanswered after this → logged as missed. Auto-dismiss is native on Android; on iOS the notification is cleared next time the app is opened.',
                      helperMaxLines: 3,
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                Text('Notification sound', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: NotificationSounds.all.containsKey(st.sound) ? st.sound : 'chime',
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        for (final e in NotificationSounds.all.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => st.sound = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Preview',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => _preview(st.sound),
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Preview sends a short notification; if the phone is on silent you\'ll only feel the buzz.',
                      style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 20),
                Text('Active window (no prompts outside this)', style: Theme.of(context).textTheme.titleMedium),
                Row(children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('Start'),
                      subtitle: Text(st.windowStart.label),
                      onTap: () => _pickTime(true),
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: const Text('End'),
                      subtitle: Text(st.windowEnd.label),
                      onTap: () => _pickTime(false),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Text('Google Sheet', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: urlC,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Apps Script web app URL',
                      helperText: 'See README: deploy apps_script/Code.gs as a web app and paste its URL here.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text('Save & reschedule')),
              ]),
            ),
    );
  }
}
