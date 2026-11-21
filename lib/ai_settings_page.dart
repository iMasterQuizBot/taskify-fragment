import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'ai_service.dart';
import 'app_database.dart';
import 'app_theme.dart';
import 'live_voice_service.dart';
import 'tts_voice.dart';

class AiSettingsPage extends StatefulWidget {
  final AppDatabase db;
  const AiSettingsPage({super.key, required this.db});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _keyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _liveModelCtrl = TextEditingController();
  final FlutterTts _tts = FlutterTts();

  bool _hasKey = false;
  bool _showKey = false;
  String _liveVoice = LiveVoiceService.voices.first;
  String _deviceVoice = 'डिफ़ॉल्ट (फ़ोन की आवाज़)';
  double _rate = 0.5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await AiService.getApiKey();
    final name = await widget.db.getSetting('aiAssistantName');
    final model = await widget.db.getSetting('geminiModel');
    final liveModel = await widget.db.getSetting('liveModel');
    final liveVoice = await widget.db.getSetting('liveVoice');
    final vName = await widget.db.getSetting('ttsVoiceName');
    final rate = await widget.db.getSetting('ttsRate');
    if (!mounted) return;
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _nameCtrl.text = (name == null || name.trim().isEmpty) ? 'Taskify AI' : name.trim();
      _modelCtrl.text = (model == null || model.trim().isEmpty) ? 'gemini-2.5-flash' : model.trim();
      _liveModelCtrl.text =
          (liveModel == null || liveModel.trim().isEmpty) ? LiveVoiceService.defaultModel : liveModel.trim();
      _liveVoice = (liveVoice == null || liveVoice.isEmpty) ? LiveVoiceService.voices.first : liveVoice;
      _deviceVoice = (vName == null || vName.isEmpty) ? 'डिफ़ॉल्ट (फ़ोन की आवाज़)' : vName;
      _rate = double.tryParse(rate ?? '') ?? 0.5;
    });
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _saveKey() async {
    final v = _keyCtrl.text.trim();
    if (v.isEmpty) return;
    await AiService.saveApiKey(v);
    _keyCtrl.clear();
    await _load();
    _msg('API key सेव हो गई।');
  }

  Future<void> _removeKey() async {
    await AiService.clearApiKey();
    await _load();
    _msg('API key हटा दी गई।');
  }

  Future<void> _saveName() async {
    final v = _nameCtrl.text.trim();
    await widget.db.setSetting('aiAssistantName', v.isEmpty ? 'Taskify AI' : v);
    _msg('AI असिस्टेंट का नाम सेव हुआ।');
  }

  Future<void> _saveModels() async {
    await widget.db.setSetting('geminiModel', _modelCtrl.text.trim().isEmpty ? 'gemini-2.5-flash' : _modelCtrl.text.trim());
    await widget.db.setSetting(
        'liveModel', _liveModelCtrl.text.trim().isEmpty ? LiveVoiceService.defaultModel : _liveModelCtrl.text.trim());
    _msg('मॉडल सेव हुए।');
  }

  Future<void> _pickLiveVoice() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Live आवाज़ चुनें'),
        children: [
          for (final v in LiveVoiceService.voices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Text(v, style: TextStyle(fontWeight: v == _liveVoice ? FontWeight.w900 : FontWeight.normal)),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await widget.db.setSetting('liveVoice', chosen);
    setState(() => _liveVoice = chosen);
    _msg('Live आवाज़: $chosen');
  }

  Future<void> _pickDeviceVoice() async {
    final voices = await TtsVoice.available(_tts);
    if (!mounted) return;
    if (voices.isEmpty) {
      _msg('फ़ोन पर बोलने वाली आवाज़ें नहीं मिलीं। Google Text-to-Speech इंस्टॉल करें।');
      return;
    }
    final chosen = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('बोलने वाली आवाज़ चुनें'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, {'name': '', 'locale': ''}),
            child: const Text('डिफ़ॉल्ट (फ़ोन की आवाज़)'),
          ),
          for (final v in voices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Text('${v['name']}  (${v['locale']})', style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await widget.db.setSetting('ttsVoiceName', chosen['name'] ?? '');
    await widget.db.setSetting('ttsVoiceLocale', chosen['locale'] ?? '');
    final shown = (chosen['name'] ?? '').isEmpty ? 'डिफ़ॉल्ट (फ़ोन की आवाज़)' : chosen['name']!;
    setState(() => _deviceVoice = shown);
    await _preview();
  }

  Future<void> _setRate(double v) async {
    setState(() => _rate = v);
    await widget.db.setSetting('ttsRate', v.toStringAsFixed(2));
  }

  Future<void> _preview() async {
    await TtsVoice.apply(_tts, widget.db);
    await _tts.speak('नमस्ते, मैं आपका AI सहायक हूँ।');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    _modelCtrl.dispose();
    _liveModelCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            title: 'Gemini API Key',
            subtitle: _hasKey
                ? 'Key सेव है (सुरक्षित स्टोरेज में)।'
                : 'Google AI Studio (aistudio.google.com) से अपनी key बनाकर यहाँ डालें।',
            child: Column(
              children: [
                TextField(
                  controller: _keyCtrl,
                  obscureText: !_showKey,
                  decoration: InputDecoration(
                    hintText: _hasKey ? 'नई key डालें (पुरानी बदलने के लिए)' : 'AIza… जैसी key',
                    suffixIcon: IconButton(
                      icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(onPressed: _saveKey, child: const Text('Save Key')),
                    const SizedBox(width: 10),
                    if (_hasKey) TextButton(onPressed: _removeKey, child: const Text('Remove')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'AI असिस्टेंट का नाम',
            subtitle: 'यही नाम AI स्क्रीन के ऊपर दिखेगा।',
            child: Row(
              children: [
                Expanded(child: TextField(controller: _nameCtrl)),
                const SizedBox(width: 10),
                FilledButton(onPressed: _saveName, child: const Text('Save')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'आवाज़ (लिखे जवाब को बोलने के लिए)',
            subtitle: 'फ़ोन में जो बोलने वाली आवाज़ें हैं, उनमें से चुनें। आवाज़ सुनकर ही तय करें।',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.record_voice_over_rounded, color: AppColors.cyan),
                  title: const Text('आवाज़ चुनें'),
                  subtitle: Text(_deviceVoice, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickDeviceVoice,
                ),
                Row(
                  children: [
                    const Text('गति'),
                    Expanded(
                      child: Slider(
                        value: _rate,
                        min: 0.3,
                        max: 0.9,
                        divisions: 6,
                        label: _rate.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _rate = v),
                        onChangeEnd: _setRate,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _preview,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('आवाज़ सुनें'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Live बातचीत की आवाज़',
            subtitle: 'Live मोड में Gemini की अपनी आवाज़ चुनें।',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.graphic_eq_rounded, color: AppColors.emerald),
              title: const Text('Live आवाज़'),
              subtitle: Text(_liveVoice),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickLiveVoice,
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Gemini मॉडल',
            subtitle: 'टेक्स्ट मॉडल और Live (आवाज़) मॉडल। Google नया नाम दे तो यहाँ बदलें।',
            child: Column(
              children: [
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(labelText: 'टेक्स्ट मॉडल'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _liveModelCtrl,
                  decoration: const InputDecoration(labelText: 'Live (native audio) मॉडल'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: _saveModels, child: const Text('Save')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'नोट: बातचीत और फ़ोटो Google के Gemini API को जाती हैं। Key आपकी है, और उसका उपयोग आपके Google खाते से गिना जाता है।',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required String subtitle, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
