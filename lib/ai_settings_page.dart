import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'ai_service.dart';
import 'app_database.dart';
import 'app_theme.dart';
import 'live_voice_service.dart';
import 'tts_voice.dart';
import 'tts_voice_labels.dart';

class AiSettingsPage extends StatefulWidget {
  final AppDatabase db;
  const AiSettingsPage({super.key, required this.db});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  // फ़ोन का असली Google TTS "वॉइस डेटा मैनेजर" खोलने के लिए — ताकि यूज़र
  // ख़ुद चुनकर भाषा का डेटा डाउनलोड कर सके (ज़्यादा जानकारी नीचे बटन पर)।
  static const MethodChannel _ttsChannel = MethodChannel('taskify/tts');

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

  final _dsKeyCtrl = TextEditingController();
  String _provider = 'gemini';
  bool _hasDsKey = false;
  bool _showDsKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await AiService.getApiKey();
    final dsKey = await AiService.getDeepseekKey();
    final provider = await widget.db.getSetting('aiProvider');
    final name = await widget.db.getSetting('aiAssistantName');
    final model = await widget.db.getSetting('geminiModel');
    final liveModel = await widget.db.getSetting('liveModel');
    final liveVoice = await widget.db.getSetting('liveVoice');
    final vName = await widget.db.getSetting('ttsVoiceName');
    final rate = await widget.db.getSetting('ttsRate');
    if (!mounted) return;
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _hasDsKey = dsKey != null && dsKey.isNotEmpty;
      _provider = (provider == null || provider.trim().isEmpty) ? 'gemini' : provider.trim();
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

  Future<void> _selectProvider(String p) async {
    await widget.db.setSetting('aiProvider', p);
    setState(() => _provider = p);
    _msg(p == 'deepseek' ? 'अब सवाल DeepSeek से हल होंगे।' : 'अब सवाल Gemini से हल होंगे।');
  }

  Future<void> _saveDsKey() async {
    final v = _dsKeyCtrl.text.trim();
    if (v.isEmpty) return;
    await AiService.saveDeepseekKey(v);
    _dsKeyCtrl.clear();
    await _load();
    _msg('DeepSeek API key सेव हो गई।');
  }

  Future<void> _removeDsKey() async {
    await AiService.clearDeepseekKey();
    await _load();
    _msg('DeepSeek API key हटा दी गई।');
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

    // FIX: पहले यहाँ raw system नाम ("te-IN-language (te-IN)") दिखता था, जिसे
    // पढ़ना मुश्किल था — इसी वजह से गलती से दूसरी भाषा की आवाज़ चुन ली जाती थी।
    // अब देश + भाषा + ऑफ़लाइन/ऑनलाइन साफ़-साफ़ दिखेगा, और भाषा के हिसाब से
    // क्रम में लगा दिया गया है ताकि अपनी भाषा ढूँढना आसान हो।
    final withLabels = voices
        .map((v) => (voice: v, label: TtsVoiceLabels.simpleLabel(v['locale'] ?? '', v['name'] ?? '')))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final chosen = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('बोलने वाली आवाज़ चुनें'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, {'name': '', 'locale': ''}),
            child: const Text('डिफ़ॉल्ट (फ़ोन की आवाज़)', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 6, 24, 2),
            child: Divider(height: 1),
          ),
          for (final item in withLabels)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, item.voice),
              child: Text(item.label, style: const TextStyle(fontSize: 13.5)),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await widget.db.setSetting('ttsVoiceName', chosen['name'] ?? '');
    await widget.db.setSetting('ttsVoiceLocale', chosen['locale'] ?? '');
    final shown = (chosen['name'] ?? '').isEmpty
        ? 'डिफ़ॉल्ट (फ़ोन की आवाज़)'
        : TtsVoiceLabels.simpleLabel(chosen['locale'] ?? '', chosen['name'] ?? '');
    setState(() => _deviceVoice = shown);
    await _preview();
  }

  /// Android किसी भी ऐप को "सिर्फ़ एक" भाषा की आवाज़ चुपचाप डाउनलोड करने की
  /// इजाज़त नहीं देता — यह सीधा Google Text-to-Speech का अपना "डेटा मैनेजर"
  /// खोलता है, जहाँ यूज़र ख़ुद भाषा चुनकर उसका ऑफ़लाइन डेटा डाउनलोड कर सकता है।
  Future<void> _openVoiceDataManager() async {
    try {
      final ok = await _ttsChannel.invokeMethod<bool>('openVoiceData');
      if (ok != true && mounted) {
        _msg('यह फ़ोन पर नहीं खुल पाया। Settings → System → Languages → Text-to-speech में जाकर वहाँ से डाउनलोड करें।');
      }
    } catch (_) {
      if (mounted) {
        _msg('यह फ़ोन पर नहीं खुल पाया। Settings → System → Languages → Text-to-speech में जाकर वहाँ से डाउनलोड करें।');
      }
    }
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
    _dsKeyCtrl.dispose();
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
            title: 'सवाल किससे हल करें?',
            subtitle: 'टाइप करके पूछे गए सवाल (चैट/फ़ोटो) इसी इंजन से हल होंगे। Live बातचीत (बोलकर) अभी भी Gemini से ही होती है — नीचे नोट देखें।',
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Gemini'),
                    selected: _provider == 'gemini',
                    onSelected: (_) => _selectProvider('gemini'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('DeepSeek'),
                    selected: _provider == 'deepseek',
                    onSelected: (_) => _selectProvider('deepseek'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'DeepSeek API Key',
            subtitle: _hasDsKey
                ? 'Key सेव है (सुरक्षित स्टोरेज में)।'
                : 'platform.deepseek.com पर अकाउंट बनाकर, बैलेंस डालकर key बनाएँ, फिर यहाँ डालें। (नोट: DeepSeek मुफ़्त नहीं, पर बहुत सस्ता है; और फ़ोटो वाले सवाल अभी नहीं पढ़ सकता — उसके लिए Gemini चुनें।)',
            child: Column(
              children: [
                TextField(
                  controller: _dsKeyCtrl,
                  obscureText: !_showDsKey,
                  decoration: InputDecoration(
                    hintText: _hasDsKey ? 'नई key डालें (पुरानी बदलने के लिए)' : 'sk-… जैसी key',
                    suffixIcon: IconButton(
                      icon: Icon(_showDsKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showDsKey = !_showDsKey),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(onPressed: _saveDsKey, child: const Text('Save Key')),
                    const SizedBox(width: 10),
                    if (_hasDsKey) TextButton(onPressed: _removeDsKey, child: const Text('Remove')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                const Divider(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openVoiceDataManager,
                    icon: const Icon(Icons.download_rounded, color: AppColors.cyan),
                    label: const Text('आवाज़ डेटा डाउनलोड / मैनेज करें'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 4, right: 4),
                  child: Text(
                    'यह Google Text-to-Speech का अपना पेज खोलता है, जहाँ अपनी भाषा चुनकर उसका ऑफ़लाइन डेटा डाउनलोड करें।',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
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
