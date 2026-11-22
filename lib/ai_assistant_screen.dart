import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ai_service.dart';
import 'ai_settings_page.dart';
import 'app_database.dart';
import 'app_theme.dart';
import 'live_voice_screen.dart';
import 'speech_text.dart';
import 'tts_voice.dart';

class _Msg {
  final int? id;
  final String text;
  final bool isUser;
  final Uint8List? image;
  _Msg(this.text, this.isUser, {this.id, this.image});
}

class AiAssistantScreen extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback onChanged;
  final bool embedded;

  const AiAssistantScreen({
    super.key,
    required this.db,
    required this.onChanged,
    this.embedded = false,
  });

  @override
  State<AiAssistantScreen> createState() => AiAssistantScreenState();
}

class AiAssistantScreenState extends State<AiAssistantScreen>
    with AutomaticKeepAliveClientMixin {
  late final AiService _ai = AiService(widget.db);
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<_Msg> _messages = [];
  bool _busy = false;
  bool _listening = false;
  bool _speakReplies = true;
  bool _speaking = false;
  Uint8List? _pendingImage;
  String _assistantName = 'Taskify AI';

  @override
  bool get wantKeepAlive => widget.embedded;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadSavedMessages();
    _setupTts();
  }

  Future<void> _loadSavedMessages() async {
    final rows = await widget.db.getAiMessages('api');
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(rows.map((r) {
          Uint8List? img;
          final b64 = r['imageBase64']?.toString();
          if (b64 != null && b64.isNotEmpty) {
            try {
              img = base64Decode(b64);
            } catch (_) {}
          }
          return _Msg(
            r['text'].toString(),
            r['role'].toString() == 'user',
            id: r['id'] as int?,
            image: img,
          );
        }));
    });
    _scrollDown();
  }

  Future<void> clearChat() async {
    await widget.db.clearAiMessages('api');
    _ai.resetChat();
    if (!mounted) return;
    setState(() => _messages.clear());
  }

  Future<void> reloadMessages() => _loadSavedMessages();

  Future<void> _setupTts() async {
    _tts.setStartHandler(() {
      if (mounted) setState(() => _speaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
    await TtsVoice.apply(_tts, widget.db);
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
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
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

    await _stopSpeaking();
    final image = _pendingImage;
    final userDisplay = text.isEmpty ? 'सवाल (फ़ोटो)' : text;
    final imgB64 = image != null ? base64Encode(image) : null;
    final userMsgId = await widget.db.addAiMessage(
      channel: 'api',
      role: 'user',
      text: userDisplay,
      imageBase64: imgB64,
    );

    setState(() {
      _messages.add(_Msg(userDisplay, true, id: userMsgId, image: image));
      _busy = true;
      _pendingImage = null;
      _input.clear();
    });
    _scrollDown();

    try {
      final reply = await _ai.send(text: text, image: image, imageMime: 'image/jpeg');
      widget.onChanged();
      final botMsgId = await widget.db.addAiMessage(
        channel: 'api',
        role: 'assistant',
        text: reply,
      );
      if (!mounted) return;
      setState(() => _messages.add(_Msg(reply, false, id: botMsgId)));
      if (_speakReplies) {
        await _tts.speak(TtsVoice.cleanForSpeech(reply));
      }
    } catch (e) {
      final errText = e.toString().replaceFirst('Exception: ', '');
      final errId = await widget.db.addAiMessage(
        channel: 'api',
        role: 'assistant',
        text: errText,
      );
      if (!mounted) return;
      setState(() => _messages.add(_Msg(errText, false, id: errId)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _openLive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveVoiceScreen(db: widget.db, onChanged: widget.onChanged),
      ),
    ).then((_) => _loadSavedMessages());
  }

  Widget _buildBody() {
    return Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Text(
                  _assistantName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.cyan),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Live Voice AI',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.record_voice_over_rounded, size: 19, color: AppColors.emerald),
                  onPressed: _openLive,
                ),
                if (_speaking)
                  IconButton(
                    tooltip: 'बोलना रोकें',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.stop_circle_rounded, size: 19, color: AppColors.rose),
                    onPressed: _stopSpeaking,
                  )
                else
                  IconButton(
                    tooltip: 'जवाब बोलकर सुनाएँ',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 19),
                    onPressed: () => setState(() => _speakReplies = !_speakReplies),
                  ),
                IconButton(
                  tooltip: 'AI Settings (आवाज़ व Key)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.settings_rounded, size: 19),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AiSettingsPage(db: widget.db)));
                    await _loadName();
                    await TtsVoice.apply(_tts, widget.db);
                  },
                ),
                IconButton(
                  tooltip: 'चैट साफ़ करें',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_sweep_rounded, size: 19, color: AppColors.rose),
                  onPressed: _messages.isEmpty ? null : clearChat,
                ),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'मुझसे लिखकर या बोलकर बात करें।\n'
                      '"कल शाम 6 बजे जिम जोड़ो", "आज के टास्क दिखाओ",\n'
                      'या सवाल की फ़ोटो भेजें।\n\n'
                      'आपकी सारी बातचीत यहाँ सेव रहेगी जब तक आप डिलीट न करें।',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _bubble(_messages[i], i),
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
                icon: Icon(
                  _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _listening ? AppColors.rose : null,
                ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.embedded) {
      return SafeArea(top: false, child: _buildBody());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_assistantName, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Live बातचीत (आवाज़ में)',
            icon: const Icon(Icons.record_voice_over_rounded, color: AppColors.emerald),
            onPressed: _openLive,
          ),
          if (_speaking)
            IconButton(
              tooltip: 'बोलना रोकें',
              icon: const Icon(Icons.stop_circle_rounded, color: AppColors.rose),
              onPressed: _stopSpeaking,
            )
          else
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
              await _loadName();
              await TtsVoice.apply(_tts, widget.db);
            },
          ),
          IconButton(
            tooltip: 'चैट साफ़ करें',
            icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.rose),
            onPressed: _messages.isEmpty ? null : clearChat,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _bubble(_Msg m, int index) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: m.id == null
            ? null
            : () async {
                await widget.db.deleteAiMessage(m.id!);
                if (!mounted) return;
                setState(() => _messages.removeAt(index));
              },
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
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
              m.isUser
                  ? SelectableText(m.text, style: const TextStyle(height: 1.4))
                  : SolutionText(m.text, style: const TextStyle(height: 1.5, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
