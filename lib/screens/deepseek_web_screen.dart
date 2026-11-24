import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../ai_assistant_screen.dart';
import '../app_database.dart';
import '../app_theme.dart';
import '../helpers.dart';
import '../offline_ai_engine.dart';
import '../tts_voice.dart';

class DeepSeekWebScreen extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback? onDatabaseChanged;
  final int initialTab;

  const DeepSeekWebScreen({
    super.key,
    required this.db,
    this.onDatabaseChanged,
    this.initialTab = 0,
  });

  @override
  State<DeepSeekWebScreen> createState() => _DeepSeekWebScreenState();
}

class _DeepSeekWebScreenState extends State<DeepSeekWebScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final OfflineAiEngine _engine;
  late final WebViewController _webController;

  final GlobalKey<AiAssistantScreenState> _apiAiKey = GlobalKey<AiAssistantScreenState>();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  static const MethodChannel _sttAudio = MethodChannel('taskify/stt_audio');
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<_ChatMsg> _messages = [];
  DateTime _selectedDate = DateTime.now();
  bool _isListening = false;
  bool _isListeningLive = false;
  bool _voiceReply = true;
  bool _speaking = false;
  int _webProgress = 0;

  String get _selectedDateKey => widget.db.dateKey(_selectedDate);
  bool get _isToday => DateUtils.isSameDay(_selectedDate, DateTime.now());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    _engine = OfflineAiEngine(widget.db);
    _setupTts();
    _loadOfflineHistory();

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _webProgress = p);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _webProgress = 100);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://chat.deepseek.com'));

    try {
      if (Platform.isAndroid && _webController.platform is AndroidWebViewController) {
        final androidCtrl = _webController.platform as AndroidWebViewController;
        androidCtrl.setOnShowFileSelector((FileSelectorParams params) async {
          try {
            final res = await FilePicker.platform.pickFiles(
              allowMultiple: params.mode == FileSelectorMode.openMultiple,
              withData: false,
            );
            if (res == null) return <String>[];
            return res.files
                .where((f) => f.path != null)
                .map((f) => Uri.file(f.path!).toString())
                .toList();
          } catch (_) {
            return <String>[];
          }
        });
      }
    } catch (_) {}
  }

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

  Future<void> _loadOfflineHistory() async {
    final rows = await widget.db.getAiMessages('offline', chatDate: _selectedDateKey);
    if (!mounted) return;
    if (rows.isEmpty) {
      setState(() {
        _messages
          ..clear()
          ..add(
            _ChatMsg(
              isUser: false,
              text: _isToday
                  ? 'नमस्ते! मैं आपका सुपरफास्ट Offline Taskify AI हूँ ⚡\n'
                    'बोलकर या लिखकर टास्क कंट्रोल करें। किसी भी संदेश पर Long Press करके सुनें, कॉपी या शेयर करें।'
                  : '${DateFormat("d MMM yyyy").format(_selectedDate)} को कोई Offline AI चैट सेव नहीं है।',
            ),
          );
      });
    } else {
      setState(() {
        _messages
          ..clear()
          ..addAll(rows.map((r) => _ChatMsg(
                id: r['id'] as int?,
                isUser: r['role'].toString() == 'user',
                text: r['text'].toString(),
                deepSeekQuery: r['deepSeekQuery']?.toString(),
              )));
      });
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    try {
      _tts.stop();
    } catch (_) {}
    try {
      _speech.stop();
    } catch (_) {}
    _tabController.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _clearActiveTab() async {
    if (_tabController.index == 0) {
      final hasRealMsgs = _messages.any((m) => m.id != null);
      if (!hasRealMsgs) return;
      final first = await confirm(
        context,
        'चैट डिलीट करें?',
        'क्या आप ${_isToday ? "आज" : DateFormat("d MMM yyyy").format(_selectedDate)} की सभी चैट डिलीट करना चाहते हैं?',
      );
      if (!first || !mounted) return;
      final second = await confirm(
        context,
        'पक्का डिलीट करें?',
        'यह कार्रवाई वापस नहीं होगी। क्या आप पूरी तरह से निश्चित हैं?',
      );
      if (!second) return;
      await widget.db.clearAiMessages('offline', chatDate: _selectedDateKey);
      await _loadOfflineHistory();
    } else if (_tabController.index == 1) {
      await _apiAiKey.currentState?.clearChat();
    } else {
      await _webController.reload();
    }
  }

  Future<void> _speakText(String text) async {
    try {
      await _tts.stop();
      await TtsVoice.apply(_tts, widget.db);
      await _tts.speak(TtsVoice.cleanForSpeech(text));
    } catch (_) {}
  }

  Future<void> _replayFullOfflineConversation() async {
    final realMsgs = _messages.where((m) => m.id != null).toList();
    if (realMsgs.isEmpty) return;
    final combined = realMsgs
        .map((m) => '${m.isUser ? "आपने कहा:" : "जवाब:"} ${TtsVoice.cleanForSpeech(m.text)}')
        .join('। ');
    await _speakText(combined);
  }

  Future<void> _pickOfflineDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadOfflineHistory();
  }

  Future<void> _sendOffline(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _inputCtrl.clear();
    final dateKey = _selectedDateKey;
    final userId = await widget.db.addAiMessage(
      channel: 'offline',
      role: 'user',
      text: trimmed,
      chatDate: dateKey,
    );
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => m.id == null);
      _messages.add(_ChatMsg(id: userId, isUser: true, text: trimmed));
    });
    _scrollToBottom();

    final reply = await _engine.process(trimmed);

    if (reply.dbChanged) {
      widget.onDatabaseChanged?.call();
    }

    final botId = await widget.db.addAiMessage(
      channel: 'offline',
      role: 'assistant',
      text: reply.text,
      deepSeekQuery: reply.suggestDeepSeek ? reply.deepSeekQuery : null,
      chatDate: dateKey,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMsg(
          id: botId,
          isUser: false,
          text: reply.text,
          deepSeekQuery: reply.suggestDeepSeek ? reply.deepSeekQuery : null,
        ),
      );
    });
    _scrollToBottom();

    if (_voiceReply) {
      await _speakText(reply.text);
    }
  }

  Future<void> _toggleMic({required bool autoSend}) async {
    if (_isListening) {
      try {
        try { await _sttAudio.invokeMethod('muteBeep'); } catch (_) {}
      await _speech.stop();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isListening = false;
          _isListeningLive = false;
        });
      }
      return;
    }

    try {
      final ok = await _speech.initialize();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('माइक की अनुमति नहीं मिली या स्पीच उपलब्ध नहीं है।')),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _isListening = true;
        _isListeningLive = autoSend;
      });
      try { await _sttAudio.invokeMethod('muteBeep'); } catch (_) {}
      await _speech.listen(
        localeId: 'hi_IN',
        onResult: (result) {
          if (!mounted) return;
          setState(() => _inputCtrl.text = result.recognizedWords);
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            final shouldSend = _isListeningLive;
            setState(() {
              _isListening = false;
              _isListeningLive = false;
            });
            if (shouldSend) {
              _sendOffline(result.recognizedWords);
            }
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _isListeningLive = false;
        });
      }
    }
  }

  Future<void> _openInDeepSeek(String query) async {
    await Clipboard.setData(ClipboardData(text: query));
    _tabController.animateTo(2);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('सवाल कॉपी हो गया है! DeepSeek के बॉक्स में Paste करें।'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showOfflineMsgActions(_ChatMsg msg, int index) {
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
                _speakText(msg.text);
              },
            ),
            if (_messages.any((m) => m.id != null))
              ListTile(
                leading: const Icon(Icons.record_voice_over_rounded, color: AppColors.emerald),
                title: const Text('पूरी बातचीत सुनें'),
                subtitle: const Text('इस तारीख़ की पूरी बातचीत दोहराएँ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _replayFullOfflineConversation();
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.violet),
              title: const Text('कॉपी करें (Copy)'),
              onTap: () async {
                Navigator.pop(ctx);
                await Clipboard.setData(ClipboardData(text: msg.text));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('टेक्स्ट कॉपी हो गया।')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: AppColors.amber),
              title: const Text('शेयर करें (Share)'),
              onTap: () async {
                Navigator.pop(ctx);
                await Share.share(msg.text);
              },
            ),
            if (msg.id != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.rose),
                title: const Text('यह संदेश डिलीट करें', style: TextStyle(color: AppColors.rose)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final yes = await confirm(context, 'संदेश डिलीट करें?', 'क्या आप यह संदेश हटाना चाहते हैं?');
                  if (!yes) return;
                  await widget.db.deleteAiMessage(msg.id!);
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        if (_tabController.index == 2 && await _webController.canGoBack()) {
          await _webController.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF151A24),
          title: const Text('Taskify AI Hub', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (_speaking)
              IconButton(
                tooltip: 'बोलना रोकें',
                icon: const Icon(Icons.stop_circle_rounded, color: AppColors.rose),
                onPressed: () async {
                  await _tts.stop();
                  if (mounted) setState(() => _speaking = false);
                },
              )
            else
              IconButton(
                tooltip: _voiceReply ? 'Voice Reply ON' : 'Voice Reply OFF',
                icon: Icon(_voiceReply ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                onPressed: () {
                  setState(() => _voiceReply = !_voiceReply);
                  if (!_voiceReply) _tts.stop();
                },
              ),
            IconButton(
              tooltip: 'चैट रिफ्रेश / डिलीट करें',
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.rose),
              onPressed: _clearActiveTab,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.cyan,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.bolt_rounded, size: 18), text: 'Offline AI'),
              Tab(icon: Icon(Icons.auto_awesome_rounded, size: 18), text: 'API AI'),
              Tab(icon: Icon(Icons.public_rounded, size: 18), text: 'DeepSeek Web'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildOfflineTab(),
            AiAssistantScreen(
              key: _apiAiKey,
              db: widget.db,
              onChanged: () => widget.onDatabaseChanged?.call(),
              embedded: true,
            ),
            _buildDeepSeekTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineDateStrip() {
    final label = _isToday
        ? 'आज (${DateFormat('d MMM').format(_selectedDate)})'
        : DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              _loadOfflineHistory();
            },
          ),
          Expanded(
            child: InkWell(
              onTap: _pickOfflineDate,
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
                    _loadOfflineHistory();
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineTab() {
    final quickChips = [
      'आज के टास्क दिखाओ',
      'मेरी प्रोग्रेस बताओ',
      'कल सुबह 7 बजे Gym',
      'रोज सुबह 6 बजे पानी पीना',
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              const Text(
                'Offline Taskify AI',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.cyan),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.rose,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: _messages.any((m) => m.id != null) ? _clearActiveTab : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('चैट डिलीट करें', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        _buildOfflineDateStrip(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: quickChips.map((chip) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(chip, style: const TextStyle(fontSize: 12, color: Colors.white)),
                  backgroundColor: const Color(0xFF1E2636),
                  side: BorderSide(color: AppColors.violet.withOpacity(0.4)),
                  onPressed: () => _sendOffline(chip),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return Align(
                alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: () => _showOfflineMsgActions(msg, index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                    decoration: BoxDecoration(
                      color: msg.isUser ? AppColors.violet.withOpacity(0.85) : const Color(0xFF1B2230),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.text,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                        ),
                        if (msg.deepSeekQuery != null) ...[
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text('DeepSeek पर पूछें', style: TextStyle(fontWeight: FontWeight.w700)),
                            onPressed: () => _openInDeepSeek(msg.deepSeekQuery!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            color: const Color(0xFF151A24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendOffline,
                    decoration: InputDecoration(
                      hintText: _isListening ? 'सुन रहा हूँ...' : 'कमांड लिखें या माइक दबाएं...',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1E2636),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Live बोलें (अपने आप Send होगा)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _toggleMic(autoSend: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_isListening && _isListeningLive)
                            ? Colors.redAccent.withOpacity(0.22)
                            : AppColors.cyan.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (_isListening && _isListeningLive)
                              ? Colors.redAccent
                              : AppColors.cyan.withOpacity(0.45),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.mic_rounded,
                            size: 16,
                            color: (_isListening && _isListeningLive) ? Colors.redAccent : AppColors.cyan,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: (_isListening && _isListeningLive) ? Colors.redAccent : AppColors.cyan,
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
                    (_isListening && !_isListeningLive) ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: (_isListening && !_isListeningLive) ? Colors.redAccent : AppColors.cyan,
                  ),
                  onPressed: () => _toggleMic(autoSend: false),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: AppColors.cyan),
                  onPressed: () => _sendOffline(_inputCtrl.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeepSeekTab() {
    return Column(
      children: [
        if (_webProgress < 100)
          LinearProgressIndicator(
            value: _webProgress / 100,
            color: AppColors.cyan,
            backgroundColor: Colors.transparent,
            minHeight: 3,
          ),
        Expanded(child: _KeepAliveWebView(controller: _webController)),
      ],
    );
  }
}

class _KeepAliveWebView extends StatefulWidget {
  final WebViewController controller;
  const _KeepAliveWebView({required this.controller});

  @override
  State<_KeepAliveWebView> createState() => _KeepAliveWebViewState();
}

class _KeepAliveWebViewState extends State<_KeepAliveWebView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return WebViewWidget(controller: widget.controller);
  }
}

class _ChatMsg {
  final int? id;
  final bool isUser;
  final String text;
  final String? deepSeekQuery;

  const _ChatMsg({
    this.id,
    required this.isUser,
    required this.text,
    this.deepSeekQuery,
  });
}
