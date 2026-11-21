import 'package:flutter/material.dart';

import 'ai_service.dart';
import 'app_database.dart';
import 'app_theme.dart';

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
  bool _hasKey = false;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await AiService.getApiKey();
    final name = await widget.db.getSetting('aiAssistantName');
    final model = await widget.db.getSetting('geminiModel');
    if (!mounted) return;
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _nameCtrl.text = (name == null || name.trim().isEmpty) ? 'Taskify AI' : name.trim();
      _modelCtrl.text = (model == null || model.trim().isEmpty) ? 'gemini-2.5-flash' : model.trim();
    });
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

  Future<void> _saveModel() async {
    final v = _modelCtrl.text.trim();
    await widget.db.setSetting('geminiModel', v.isEmpty ? 'gemini-2.5-flash' : v);
    _msg('मॉडल सेव हुआ।');
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    _modelCtrl.dispose();
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
            title: 'Gemini मॉडल',
            subtitle: 'डिफ़ॉल्ट gemini-2.5-flash है। Google नया मॉडल आने पर यहाँ बदल सकते हैं।',
            child: Row(
              children: [
                Expanded(child: TextField(controller: _modelCtrl)),
                const SizedBox(width: 10),
                FilledButton(onPressed: _saveModel, child: const Text('Save')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'नोट: AI की बातचीत और फ़ोटो Google के Gemini API को भेजी जाती है। '
            'Key आपकी है, और उसका बिल/सीमा आपके Google खाते से लगती है।',
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
