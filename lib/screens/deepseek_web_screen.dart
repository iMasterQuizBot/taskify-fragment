import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:webview_flutter/webview_flutter.dart';

import '../app_database.dart';
import '../app_theme.dart';
import '../offline_ai_engine.dart';

class DeepSeekWebScreen extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback? onDatabaseChanged;

  const DeepSeekWebScreen({
    super.key,
    required this.db,
    this.onDatabaseChanged,
  });

  @override
  State<DeepSeekWebScreen> createState() => _DeepSeekWebScreenState();
}

class _DeepSeekWebScreenState extends State<DeepSeekWebScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final OfflineAiEngine _engine;
  late final WebViewController _webController;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<_ChatMsg> _messages = [];
  bool _isListening = false;
  bool _voiceReply = true;
  int _webProgress = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _engine = OfflineAiEngine(widget.db);

    _messages.add(
      const _ChatMsg(
        isUser: false,
        text: 'नमस्ते! मैं आपका सुपरफास्ट Offline Taskify AI हूँ ⚡\n'
            'बोलकर या लिखकर टास्क कंट्रोल करें, या बड़े सवालों के लिए ऊपर "DeepSeek Web" टैब पर जाएं।',
      ),
    );

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
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _tabController.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOffline(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _inputCtrl.clear();
    setState(() {
      _messages.add(_ChatMsg(isUser: true, text: trimmed));
    });
    _scrollToBottom();

    final reply = await _engine.process(trimmed);

    if (reply.dbChanged) {
      widget.onDatabaseChanged?.call();
    }

    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMsg(
          isUser: false,
          text: reply.text,
          deepSeekQuery: reply.suggestDeepSeek ? reply.deepSeekQuery : null,
        ),
      );
    });
    _scrollToBottom();

    if (_voiceReply) {
      try {
        await _tts.stop();
        await _tts.speak(reply.text.replaceAll(RegExp(r'[*#•✅⏳🗑️📊🔥📅⚡🔔🌐👇]'), ''));
      } catch (_) {}
    }
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final ok = await _speech.initialize();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('माइक की अनुमति नहीं मिली या स्पीच उपलब्ध नहीं है।')),
      );
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'hi_IN',
      onResult: (result) {
        if (!mounted) return;
        setState(() => _inputCtrl.text = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          setState(() => _isListening = false);
          _sendOffline(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _openInDeepSeek(String query) async {
    await Clipboard.setData(ClipboardData(text: query));
    _tabController.animateTo(1);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('सवाल कॉपी हो गया है! DeepSeek के बॉक्स में Paste करें।'),
        duration: Duration(seconds: 3),
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
        if (_tabController.index == 1 && await _webController.canGoBack()) {
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
            IconButton(
              tooltip: _voiceReply ? 'Voice Reply ON' : 'Voice Reply OFF',
              icon: Icon(_voiceReply ? Icons.volume_up_rounded : Icons.volume_off_rounded),
              onPressed: () {
                setState(() => _voiceReply = !_voiceReply);
                if (!_voiceReply) _tts.stop();
              },
            ),
            IconButton(
              tooltip: 'Reload DeepSeek',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _webController.reload(),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.cyan,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.bolt_rounded, size: 18), text: 'Offline AI'),
              Tab(icon: Icon(Icons.public_rounded, size: 18), text: 'DeepSeek Web'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildOfflineTab(),
            _buildDeepSeekTab(),
          ],
        ),
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _isListening ? Colors.redAccent : AppColors.cyan,
                  ),
                  onPressed: _toggleMic,
                ),
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
                IconButton(
                  icon: Icon(Icons.send_rounded, color: AppColors.cyan),
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
  final bool isUser;
  final String text;
  final String? deepSeekQuery;

  const _ChatMsg({
    required this.isUser,
    required this.text,
    this.deepSeekQuery,
  });
}
