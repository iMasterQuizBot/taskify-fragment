import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'notification_service.dart';
import 'sound_service.dart';

class SoundSettingsPage extends StatefulWidget {
  final AppDatabase db;
  const SoundSettingsPage({super.key, required this.db});

  @override
  State<SoundSettingsPage> createState() => _SoundSettingsPageState();
}

class _SoundSettingsPageState extends State<SoundSettingsPage> {
  bool _notifyOn = true;
  bool _alarmOn = true;
  bool _tapSoundOn = SoundService.tapSoundOn;
  bool _hapticOn = SoundService.hapticOn;
  final Map<String, String> _sources = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await widget.db.getSetting('notificationsEnabled');
    final a = await widget.db.getSetting('alarmEnabled');
    final map = <String, String>{};
    for (final s in soundSlots) {
      map[s.id] = await SoundService.getSource(s.id);
    }
    if (!mounted) return;
    setState(() {
      _notifyOn = n != '0';
      _alarmOn = a != '0';
      _sources
        ..clear()
        ..addAll(map);
    });
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _setNotify(bool v) async {
    await widget.db.setSetting('notificationsEnabled', v ? '1' : '0');
    setState(() => _notifyOn = v);
    await widget.db.rescheduleAllReminders();
  }

  Future<void> _setAlarm(bool v) async {
    await widget.db.setSetting('alarmEnabled', v ? '1' : '0');
    setState(() => _alarmOn = v);
    await widget.db.rescheduleAllReminders();
  }

  Future<void> _pickFile(SoundSlot slot) async {
    try {
      final stored = await SoundService.pickAndStoreFile(slot.id);
      if (stored == null) return;
      await SoundService.setSource(slot.id, stored);
      await _load();
      await widget.db.rescheduleAllReminders();
      _msg('${slot.label}: नई फ़ाइल सेट हुई।');
    } catch (e) {
      _msg('फ़ाइल नहीं चुनी जा सकी: $e');
    }
  }

  Future<void> _chooseBuiltin(SoundSlot slot) async {
    final entries = SoundService.builtinLabels.entries.toList();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(slot.label),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              return ListTile(
                dense: true,
                title: Text(e.value),
                trailing: e.key == 'default'
                    ? null
                    : IconButton(
                        tooltip: 'सुनें',
                        icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.cyan),
                        onPressed: () => SoundService.playSource('builtin:${e.key}'),
                      ),
                onTap: () => Navigator.pop(ctx, 'builtin:${e.key}'),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द करें')),
        ],
      ),
    );
    await SoundService.stopPreview();
    if (chosen == null) return;
    await SoundService.setSource(slot.id, chosen);
    await _load();
    await widget.db.rescheduleAllReminders();
  }

  Future<void> _reset(SoundSlot slot) async {
    await SoundService.setSource(slot.id, slot.fallback);
    await _load();
    await widget.db.rescheduleAllReminders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sound & Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle('नोटिफिकेशन और अलार्म'),
          SwitchListTile(
            title: const Text('सभी नोटिफिकेशन चालू'),
            subtitle: const Text('बंद करने पर कोई टास्क नोटिफिकेशन नहीं आएगा। हर टास्क का अलग स्विच भी है।'),
            value: _notifyOn,
            onChanged: _setNotify,
          ),
          SwitchListTile(
            title: const Text('टास्क के समय पर अलार्म'),
            subtitle: const Text('टास्क शुरू होने के ठीक समय पर अलार्म साउंड बजेगा।'),
            value: _alarmOn,
            onChanged: _setAlarm,
          ),
          const SizedBox(height: 8),
          _sectionTitle('टैप फ़ीडबैक'),
          SwitchListTile(
            title: const Text('टैप पर क्लिक साउंड'),
            subtitle: const Text('ऐप में कहीं भी छोटा टैप करने पर हल्की क्लिक आवाज़।'),
            value: _tapSoundOn,
            onChanged: (v) async {
              await SoundService.setTapSound(v);
              setState(() => _tapSoundOn = v);
            },
          ),
          SwitchListTile(
            title: const Text('हैप्टिक (वाइब्रेशन)'),
            subtitle: const Text('टैप, टास्क बनाने और पूरा करने पर हल्का वाइब्रेशन।'),
            value: _hapticOn,
            onChanged: (v) async {
              await SoundService.setHaptic(v);
              setState(() => _hapticOn = v);
            },
          ),
          const SizedBox(height: 8),
          _sectionTitle('साउंड (आपकी फ़ाइल या built-in)'),
          for (final slot in soundSlots)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(slot.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          SoundService.labelFor(_sources[slot.id] ?? slot.fallback),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'सुनें',
                    icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.cyan),
                    onPressed: () => SoundService.playSource(_sources[slot.id] ?? slot.fallback),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'file') _pickFile(slot);
                      if (v == 'builtin') _chooseBuiltin(slot);
                      if (v == 'reset') _reset(slot);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'file', child: Text('फ़ाइल से चुनें (mp3/wav…)')),
                      PopupMenuItem(value: 'builtin', child: Text('ऐप की साउंड लिस्ट से चुनें')),
                      PopupMenuItem(value: 'reset', child: Text('Default पर वापस')),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.notification_add_rounded),
            label: const Text('Test Notification भेजें'),
            onPressed: () async {
              try {
                await NotificationService.requestNotificationPermission();
                await NotificationService.showTest();
                _msg('Test notification भेजा गया।');
              } catch (e) {
                _msg('त्रुटि: $e');
              }
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'नोट: Android में नोटिफिकेशन का साउंड बदलने पर नया चैनल बनता है, इसलिए पहला नोटिफिकेशन पुराने साउंड से आ सकता है।',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      );
}
