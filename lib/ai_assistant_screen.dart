import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ai_service.dart';
import 'ai_settings_page.dart';
import 'app_database.dart';
import 'app_theme.dart';
import 'voice_orb_screen.dart';

class _Msg {
  final String text;
  final bool isUser;
  final Uint8List? image;
  _Msg(this.text, this.isUser, {this.image});
}

class AiAssistantScreen extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback onChanged;
  const AiAssistantScreen({super.key, required this.db, required this.onChanged});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  late final AiService _ai = AiService(widget.db);
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<_Msg> _messages = [];
  bool _busy = false;
  bool _listening = false;
  bool _speakReplies = true;
  Uint8List? _pendingImage;
  String _assistantName = 'Taskify AI';

  @override
  void initState() {
    super.initState();
    _loadName();
    _tts.setSpeechRate(0.5);
  }

  Future<void> _loadName() async {
    final n = (await widget.db.getSetting('aiAssistantName'))?.trim();
    if (!mounted) return;
    setState(() => _assistantName = (n == null || n.isEmpty) ? 'Taskify AI' : n);
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _pendingImage = bytes);
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _stt.initialize();
    if (!ok) {
      _snack('माइक्रोफ़ोन या speech recognition उपलब्ध नहीं है।');
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        setState(() => _input.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || (text.isEmpty && _pendingImage == null)) return;

    final image = _pendingImage;
    setState(() {
      _messages.add(_Msg(text.isEmpty ? 'सवाल (फ़ोटो)' : text, true, image: image));
      _busy = true;
      _pendingImage = null;
      _input.clear();
    });
    _scrollDown();

    try {
      final reply = await _ai.send(
        text: text,
        image: image,
        imageMime: 'image/jpeg',
      );
      widget.onChanged();
      if (!mounted) return;
      setState(() => _messages.add(_Msg(reply, false)));
      if (_speakReplies) {
        await _tts.setLanguage('hi-IN');
        await _tts.speak(reply);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Msg(e.toString().replaceFirst('Exception: ', ''), false)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _openVoiceMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceOrbScreen(ai: _ai, assistantName: _assistantName, onChanged: widget.onChanged),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_assistantName, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Voice mode',
            icon: const Icon(Icons.graphic_eq_rounded, color: AppColors.cyan),
            onPressed: _openVoiceMode,
          ),
          IconButton(
            tooltip: 'जवाब बोलकर सुनाएँ',
            icon: Icon(_speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            onPressed: () => setState(() => _speakReplies = !_speakReplies),
          ),
          IconButton(
            tooltip: 'AI Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => AiSettingsPage(db: widget.db)));
              _loadName();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          'मुझसे लिखकर या बोलकर बात करें।\n'
                          '"कल शाम 6 बजे जिम जोड़ो", "आज के टास्क दिखाओ",\n'
                          'या सवाल की फ़ोटो भेजें।',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
                    ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_pendingImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_pendingImage!, height: 56, width: 56, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('फ़ोटो जुड़ी है', style: TextStyle(color: AppColors.textSecondary))),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _pendingImage = null),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'सवाल की फ़ोटो',
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _busy ? null : _pickImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'लिखें या माइक दबाएँ…',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'बोलें',
                    icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _listening ? AppColors.rose : null),
                    onPressed: _busy ? null : _toggleListen,
                  ),
                  IconButton(
                    tooltip: 'भेजें',
                    icon: const Icon(Icons.send_rounded, color: AppColors.violet),
                    onPressed: _busy ? null : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.isUser ? AppColors.violet.withOpacity(0.25) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(m.image!, fit: BoxFit.cover),
                ),
              ),
            SelectableText(m.text, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
