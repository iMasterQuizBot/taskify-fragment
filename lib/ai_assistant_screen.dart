import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ai_service.dart';
import 'ai_settings_page.dart';
import 'app_database.dart';
import 'app_theme.dart';
import 'helpers.dart';
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
  DateTime _selectedDate = DateTime.now();
  bool _busy = false;
  bool _listening = false;
  bool _listeningLive = false;
  bool _speakReplies = true;
  bool _speaking = false;
  Uint8List? _pendingImage;
  String _assistantName = 'Taskify AI';

  @override
  bool get wantKeepAlive => widget.embedded;

  String get _selectedDateKey => widget.db.dateKey(_selectedDate);
  bool get _isToday => DateUtils.isSameDay(_selectedDate, DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadSavedMessages();
    _setupTts();
  }

  Future<void> _loadSavedMessages() async {
    final rows = await widget.db.getAiMessages('api', chatDate: _selectedDateKey);
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
    if (_messages.isEmpty) return;
    final first = await confirm(
      context,
      'चैट डिलीट करें?',
      'क्या आप ${_isToday ? "आज" : DateFormat("d MMM yyyy").format(_selectedDate)} की सभी API AI चैट्स डिलीट करना चाहते हैं?',
    );
    if (!first || !mounted) return;
    final second = await confirm(
      context,
      'पक्का डिलीट करें?',
      'यह कार्रवाई वापस नहीं होगी। क्या आप सच में सभी चैट हटाना चाहते हैं?',
    );
    if (!second) return;
    await widget.db.clearAiMessages('api', chatDate: _selectedDateKey);
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
    try {
      await TtsVoice.apply(_tts, widget.db);
    } catch (_) {}
  }

  Future<void> _loadName() async {
    final n = (await widget.db.getSetting('aiAssistantName'))?.trim();
    if (!mounted) return;
    setState(() => _assistantName = (n == null || n.isEmpty) ? 'Taskify AI' : n);
  }

  @override
  void dispose() {
    try {
      _stt.stop();
    } catch (_) {}
    try {
      _tts.stop();
    } catch (_) {}
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
    try {
      await _tts.stop();
    } catch (_) {}
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _speakText(String text) async {
    try {
      await _tts.stop();
      await TtsVoice.apply(_tts, widget.db);
      await _tts.speak(TtsVoice.cleanForSpeech(text));
    } catch (_) {}
  }

  Future<void> _replayFullConversation() async {
    if (_messages.isEmpty) return;
    final combined = _messages
        .map((m) => '${m.isUser ? "आपने पूछा:" : "उत्तर:"} ${TtsVoice.cleanForSpeech(m.text)}')
        .join('। ');
    await _speakText(combined);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadSavedMessages();
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _pendingImage = bytes);
    } catch (_) {}
  }

  Future<void> _toggleListen({required bool autoSend}) async {
    if (_listening) {
      try {
        await _stt.stop();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _listening = false;
          _listeningLive = false;
        });
      }
      return;
    }
    try {
      final ok = await _stt.initialize();
      if (!ok) {
        _snack('माइक्रोफ़ोन या speech recognition उपलब्ध नहीं है।');
        return;
      }
      if (!mounted) return;
      setState(() {
        _listening = true;
        _listeningLive = autoSend;
      });
      await _stt.listen(
        localeId: 'hi_IN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        onResult: (r) {
          if (!mounted) return;
          setState(() => _input.text = r.recognizedWords);
          if (r.finalResult) {
            final shouldSend = _listeningLive;
            setState(() {
              _listening = false;
              _listeningLive = false;
            });
            if (shouldSend && r.recognizedWords.trim().isNotEmpty) {
              _send();
            }
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _listeningLive = false;
        });
      }
    }
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
    final dateKey = _selectedDateKey;

    final userMsgId = await widget.db.addAiMessage(
      channel: 'api',
      role: 'user',
      text: userDisplay,
      imageBase64: imgB64,
      chatDate: dateKey,
    );

    if (!mounted) return;
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
        chatDate: dateKey,
      );
      if (!mounted) return;
      setState(() => _messages.add(_Msg(reply, false, id: botMsgId)));
      if (_speakReplies) {
        await _speakText(reply);
      }
    } catch (e) {
      final errText = e.toString().replaceFirst('Exception: ', '');
      final errId = await widget.db.addAiMessage(
        channel: 'api',
        role: 'assistant',
        text: errText,
        chatDate: dateKey,
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

  void _showMessageActions(_Msg m, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
            ),
            ListTile(
              leading: const Icon(Icons.volume_up_rounded, color: AppColors.cyan),
              title: const Text('आवाज़ में सुनें / दोहराएँ'),
              subtitle: const Text('Taskify AI इसे बोलकर सुनाएगा'),
              onTap: () {
                Navigator.pop(ctx);
                _speakText(m.text);
              },
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over_rounded, color: AppColors.emerald),
              title: const Text('पूरी बातचीत सुनें'),
              subtitle: const Text('इस तारीख़ के सभी सवाल-जवाब दोहराएँ'),
              onTap: () {
                Navigator.pop(ctx);
                _replayFullConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.violet),
              title: const Text('कॉपी करें (Copy)'),
              onTap: () async {
                Navigator.pop(ctx);
                await Clipboard.setData(ClipboardData(text: m.text));
                _snack('टेक्स्ट कॉपी हो गया।');
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: AppColors.amber),
              title: const Text('शेयर करें (Share)'),
              onTap: () async {
                Navigator.pop(ctx);
                await Share.share(m.text);
              },
            ),
            if (m.id != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.rose),
                title: const Text('यह संदेश डिलीट करें', style: TextStyle(color: AppColors.rose)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final yes = await confirm(context, 'संदेश डिलीट करें?', 'क्या आप यह संदेश हटाना चाहते हैं?');
                  if (!yes) return;
                  await widget.db.deleteAiMessage(m.id!);
                  if (!mounted) return;
                  setState(() => _messages.removeAt(index));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDateStrip() {
    final label = _isToday
        ? 'आज (${DateFormat('d MMM').format(_selectedDate)})'
        : DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: () {
              setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
              _loadSavedMessages();
            },
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.cyan),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _isToday ? Colors.white24 : Colors.white,
            ),
            onPressed: _isToday
                ? null
                : () {
                    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                    _loadSavedMessages();
                  },
          ),
        ],
      ),
    );
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
        _buildDateStrip(),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      _isToday
                          ? 'मुझसे लिखकर या बोलकर बात करें।\n'
                            '"कल शाम 6 बजे जिम जोड़ो", "आज के टास्क दिखाओ",\n'
                            'या सवाल की फ़ोटो भेजें।\n\n'
                            'किसी भी संदेश पर Long Press करके सुनें, कॉपी या शेयर करें।'
                          : '${DateFormat("d MMM yyyy").format(_selectedDate)} को कोई बातचीत सेव नहीं है।',
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
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          _input.text =
                              'इस टाइमटेबल / शेड्यूल की फ़ोटो को पढ़कर सभी टास्क add_task tool से मेरे कैलेंडर में जोड़ दो।';
                          _send();
                        },
                  icon: const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.cyan),
                  label: const Text('Timetable → Tasks', style: TextStyle(fontSize: 11.5, color: AppColors.cyan)),
                ),
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
              Tooltip(
                message: 'Live बोलें (अपने आप Send होगा)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _busy ? null : () => _toggleListen(autoSend: true),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_listening && _listeningLive)
                          ? AppColors.rose.withOpacity(0.22)
                          : AppColors.cyan.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: (_listening && _listeningLive)
                            ? AppColors.rose
                            : AppColors.cyan.withOpacity(0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          size: 16,
                          color: (_listening && _listeningLive) ? AppColors.rose : AppColors.cyan,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Live',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: (_listening && _listeningLive) ? AppColors.rose : AppColors.cyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'बोलकर लिखें (Manual Send)',
                icon: Icon(
                  (_listening && !_listeningLive) ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: (_listening && !_listeningLive) ? AppColors.rose : null,
                ),
                onPressed: _busy ? null : () => _toggleListen(autoSend: false),
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
        onLongPress: () => _showMessageActions(m, index),
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
                  ? Text(m.text, style: const TextStyle(height: 1.4))
                  : SolutionText(m.text, style: const TextStyle(height: 1.5, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
