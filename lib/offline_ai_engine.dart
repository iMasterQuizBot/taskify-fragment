import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'app_database.dart';

class OfflineAiReply {
  final String text;
  final bool dbChanged;
  final bool suggestDeepSeek;
  final String? deepSeekQuery;

  const OfflineAiReply({
    required this.text,
    this.dbChanged = false,
    this.suggestDeepSeek = false,
    this.deepSeekQuery,
  });
}

class OfflineAiEngine {
  final AppDatabase db;

  // मल्टी-टर्न टास्क मेमोरी (जब तक नाम और समय दोनों पक्के न हों, टास्क नहीं बनेगा)
  bool _awaitingTask = false;
  String? _pendingTitle;
  DateTime? _pendingDate;
  int? _pendingMinutes;
  bool _pendingDaily = false;
  String? _pendingCategory;

  // 10–15 मिनट की लगातार बातचीत के लिए कन्वर्सेशन व क्विज़ मेमोरी
  String _lastTopic = '';
  int _quizIndex = -1;
  bool _awaitingQuizAnswer = false;
  int _quoteIndex = 0;
  int _jokeIndex = 0;
  final List<String> _recentTopics = [];

  static const List<({String q, String a, String hint})> _quizBank = [
    (q: 'सीमेंट में शुरुआती सेटिंग टाइम (Initial Setting Time) सामान्यतः कितना होता है?', a: '30 मिनट', hint: '30'),
    (q: 'भारत के संविधान का जनक किसे कहा जाता है?', a: 'डॉ. भीमराव अंबेडकर', hint: 'अंबेडकर'),
    (q: 'पानी का अधिकतम घनत्व कितने डिग्री सेल्सियस पर होता है?', a: '4 डिग्री सेल्सियस', hint: '4'),
    (q: 'एक दिन में कुल कितने मिनट होते हैं?', a: '1440 मिनट', hint: '1440'),
    (q: 'सौरमंडल का सबसे बड़ा ग्रह कौन सा है?', a: 'बृहस्पति (Jupiter)', hint: 'jupiter'),
    (q: 'कंक्रीट की फुल 28-दिन की स्ट्रेंथ कितने दिन में टेस्ट की जाती है?', a: '28 दिन', hint: '28'),
    (q: 'मनुष्य के शरीर में कुल कितनी हड्डियाँ होती हैं?', a: '206 हड्डियाँ', hint: '206'),
    (q: 'प्रकाश की गति लगभग कितनी होती है?', a: '3 लाख किलोमीटर प्रति सेकंड', hint: '3'),
  ];

  static const List<String> _quotes = [
    'सफलता एक दिन में नहीं मिलती, लेकिन रोज़ की छोटी मेहनत एक दिन सफलता ज़रूर दिलाती है।',
    'जब थक जाओ तो आराम कर लो, लेकिन हार कभी मत मानो — आपका आज का 1 घंटा कल का भविष्य तय करता है।',
    'बड़ा लक्ष्य छोटे-छोटे फोकस सेशन्स से ही पूरा होता है। अभी बस अगले 25 मिनट पर ध्यान दो।',
    'जो समय को सही से व्यवस्थित कर लेता है, समय उसे सबसे आगे खड़ा कर देता है।',
  ];

  static const List<String> _jokes = [
    'एक स्टूडेंट ने अलार्म से कहा: "तू रोज़ सुबह चिल्लाता है, कभी खुद भी उठकर पढ़ लिया कर!"',
    'दिमाग़ परीक्षा से पहले: सब याद है। परीक्षा हॉल में: ये सिलेबस में कब आया भाई?',
    'नींद और पढ़ाई की पुरानी दुश्मनी है — किताब खोलते ही नींद सबसे अच्छी दोस्त बन जाती है!',
  ];

  // बिल्ट-इन ऑफ़लाइन नॉलेज बेस (सामान्य सवालों के तुरंत जवाब के लिए)
  static const List<({List<String> keys, String answer})> _knowledgeBase = [
    (
      keys: ['gravity', 'गुरुत्वाकर्षण', 'g की वैल्यू', 'value of g'],
      answer: 'पृथ्वी पर गुरुत्वाकर्षण त्वरण (g) का मान लगभग 9.81 मीटर प्रति सेकंड स्क्वायर होता है।',
    ),
    (
      keys: ['pi', 'पाई का मान', 'value of pi'],
      answer: 'पाई (π) का मान लगभग 3.14159 या 22/7 होता है।',
    ),
    (
      keys: ['speed of light', 'प्रकाश की गति', 'roshni ki speed'],
      answer: 'निर्वात (vacuum) में प्रकाश की गति लगभग 2,99,792 किलोमीटर प्रति सेकंड (करीब 3 लाख km/s) होती है।',
    ),
    (
      keys: ['photosynthesis', 'प्रकाश संश्लेषण'],
      answer: 'प्रकाश संश्लेषण वह प्रक्रिया है जिससे हरे पौधे सूर्य के प्रकाश, पानी और कार्बन डाइऑक्साइड से अपना भोजन (ग्लूकोज़) और ऑक्सीजन बनाते हैं।',
    ),
    (
      keys: ['newton', 'न्यूटन के नियम', 'laws of motion'],
      answer: 'न्यूटन के तीन नियम हैं: 1) जड़त्व का नियम, 2) बल = द्रव्यमान × त्वरण (F = ma), और 3) हर क्रिया के बराबर और विपरीत प्रतिक्रिया होती है।',
    ),
    (
      keys: ['cpu', 'ram', 'rom', 'कंप्यूटर', 'computer'],
      answer: 'CPU कंप्यूटर का दिमाग़ है जो प्रोसेसिंग करता है, RAM अस्थायी तेज़ मेमोरी है, और ROM/Storage स्थायी डेटा रखती है।',
    ),
    (
      keys: ['पानी कितना', 'how much water', 'paani pina'],
      answer: 'एक वयस्क व्यक्ति को दिन में लगभग 2.5 से 3.5 लीटर (करीब 8–10 गिलास) पानी पीना चाहिए।',
    ),
    (
      keys: ['कितनी नींद', 'how much sleep', 'neend', 'सोना चाहिए'],
      answer: 'दिमाग़ को तेज़ रखने और याददाश्त मज़बूत करने के लिए रोज़ 7 से 8 घंटे की गहरी नींद बहुत ज़रूरी है।',
    ),
    (
      keys: ['भारत की राजधानी', 'capital of india'],
      answer: 'भारत की राजधानी नई दिल्ली (New Delhi) है।',
    ),
    (
      keys: ['संविधान', 'constitution of india'],
      answer: 'भारत का संविधान 26 नवंबर 1949 को अपनाया गया और 26 जनवरी 1950 को लागू हुआ। यह दुनिया का सबसे बड़ा लिखित संविधान है।',
    ),
    (
      keys: ['ओम का नियम', 'ohm law', 'ohms law'],
      answer: 'ओम का नियम कहता है कि स्थिर तापमान पर किसी चालक में बहने वाली धारा (I) वोल्टेज (V) के समानुपाती होती है, यानी V = I × R।',
    ),
    (
      keys: ['पाइथागोरस', 'pythagoras'],
      answer: 'समकोण त्रिभुज में कर्ण का वर्ग, लंब और आधार के वर्गों के योग के बराबर होता है: H² = P² + B²।',
    ),
    (
      keys: ['क्षेत्रफल', 'वृत्त का क्षेत्रफल', 'area of circle'],
      answer: 'वृत्त (Circle) का क्षेत्रफल πr² और परिधि 2πr होती है।',
    ),
  ];

  OfflineAiEngine(this.db);

  void _resetDraft() {
    _awaitingTask = false;
    _pendingTitle = null;
    _pendingDate = null;
    _pendingMinutes = null;
    _pendingDaily = false;
    _pendingCategory = null;
  }

  Future<OfflineAiReply> process(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return const OfflineAiReply(
        text: 'कुछ बोलें या लिखें — जैसे सामान्य बातचीत करें, कोई सवाल पूछें, या कहें: "टास्क जोड़ो: नाम जिम, समय सुबह 7 बजे"।',
      );
    }

    _recentTopics.add(input);
    if (_recentTopics.length > 25) _recentTopics.removeAt(0);

    final lower = input.toLowerCase();

    // 0. अधूरा टास्क ड्राफ्ट पूरा करना
    if (_awaitingTask) {
      if (_matchesAny(lower, ['cancel', 'रद्द', 'छोड़ो', 'रहने दो', 'मत जोड़ो', 'stop', 'बंद करो'])) {
        _resetDraft();
        return const OfflineAiReply(text: 'ठीक है, टास्क जोड़ना रद्द कर दिया है। बताइए अब किस बारे में बात करें?');
      }

      final extractedTime = _extractMinutesOrNull(lower);
      final extractedDate = _extractDateOrNull(lower);
      if (extractedTime != null) _pendingMinutes = extractedTime;
      if (extractedDate != null) _pendingDate = extractedDate;
      if (_matchesAny(lower, ['daily', 'everyday', 'every day', 'रोज', 'रोज़', 'हर दिन'])) {
        _pendingDaily = true;
      }

      final possibleTitle = _extractCleanTaskTitle(input);
      if ((_pendingTitle == null || _pendingTitle!.isEmpty) && possibleTitle.isNotEmpty) {
        _pendingTitle = possibleTitle[0].toUpperCase() + possibleTitle.substring(1);
        _pendingCategory ??= _detectCategory(lower);
      }

      return _finalizeOrAskDraft();
    }

    // 0.5. क्विज़ जवाब चेक करना
    if (_awaitingQuizAnswer && _quizIndex >= 0) {
      if (_matchesAny(lower, ['नहीं पता', 'बताओ', 'answer', 'skip', 'छोड़ो', 'बंद'])) {
        final ans = _quizBank[_quizIndex].a;
        _awaitingQuizAnswer = false;
        return OfflineAiReply(text: 'सही जवाब है: $ans। एक और सवाल पूछूँ या किसी और विषय पर बात करें?');
      }
      final item = _quizBank[_quizIndex];
      _awaitingQuizAnswer = false;
      if (lower.contains(item.hint.toLowerCase()) || lower.contains(item.a.toLowerCase())) {
        return const OfflineAiReply(text: 'शाबाश! बिल्कुल सही जवाब! 🎉 अगला सवाल पूछूँ?');
      } else {
        return OfflineAiReply(text: 'करीब थे! सही जवाब है: ${item.a}। चलिए अगला सवाल पूछूँ या कोई और बात करें?');
      }
    }

    // 1. क्विज़ / GK मोड
    if (_matchesAny(lower, ['quiz', 'क्विज़', 'सवाल पूछो', 'gk', 'टेस्ट लो', 'अगला सवाल', 'question pucho'])) {
      _quizIndex = (_quizIndex + 1) % _quizBank.length;
      _awaitingQuizAnswer = true;
      _lastTopic = 'quiz';
      return OfflineAiReply(text: 'चलिए एक छोटा सा क्विज़ खेलते हैं! सवाल: ${_quizBank[_quizIndex].q}');
    }

    // 2. यूनिट कन्वर्ज़न और सरल गणित (जैसे "5 km to m", "15% of 200", "25 * 4")
    final conv = _tryUnitConversion(lower);
    if (conv != null) return OfflineAiReply(text: conv);

    final mathReply = _trySimpleMath(lower);
    if (mathReply != null) return OfflineAiReply(text: mathReply);

    // 3. बिल्ट-इन ऑफ़लाइन नॉलेज बेस (Science, Math, GK, Health, Tech)
    for (final entry in _knowledgeBase) {
      if (_matchesAny(lower, entry.keys)) {
        _lastTopic = 'knowledge';
        return OfflineAiReply(text: entry.answer);
      }
    }

    // 4. सामान्य बातचीत, हाल-चाल, बोरियत, थकान, तनाव, नींद
    if (_matchesAny(lower, ['कैसे हो', 'कैसी हो', 'how are you', 'kya haal', 'क्या हाल', 'sab badhiya'])) {
      _lastTopic = 'chat';
      return const OfflineAiReply(
        text: 'मैं बिल्कुल बढ़िया हूँ और आपसे बात करके बहुत अच्छा लगा! बताइए आपका दिन कैसा चल रहा है?',
      );
    }

    if (_matchesAny(lower, ['बोर', 'boring', 'bore', 'मन नहीं', 'अच्छा नहीं लग'])) {
      _lastTopic = 'mood';
      return const OfflineAiReply(
        text: 'कोई बात नहीं, कभी-कभी ऐसा होता है। हम 5 मिनट बात कर सकते हैं, या एक छोटा क्विज़ खेलें, या मैं आपको एक मज़ेदार जोक सुनाऊँ—बताइए क्या पसंद करेंगे?',
      );
    }

    if (_matchesAny(lower, ['थक', 'tired', 'नींद', 'sleepy', 'सिर दर्द', 'टेंशन', 'stress', 'tension'])) {
      _lastTopic = 'relax';
      return const OfflineAiReply(
        text: 'लगता है आपको थोड़ा आराम चाहिए। 4 सेकंड गहरी साँस अंदर लें, 4 सेकंड रोकें और 6 सेकंड में धीरे छोड़ें। थोड़ा पानी पी लें, फिर हल्की शुरुआत करें।',
      );
    }

    if (_matchesAny(lower, ['अच्छा जा रहा', 'बढ़िया', 'मस्त', 'good', 'great', 'fine', 'ठीक हूँ', 'theek hu'])) {
      _lastTopic = 'chat';
      return const OfflineAiReply(
        text: 'यह सुनकर बहुत अच्छा लगा! आज का सबसे ज़रूरी काम क्या है जिसे आप आज पूरा करना चाहते हैं?',
      );
    }

    if (_matchesAny(lower, ['जोक', 'joke', 'हंसाओ', 'मज़ाक', 'funny'])) {
      final j = _jokes[_jokeIndex % _jokes.length];
      _jokeIndex++;
      _lastTopic = 'joke';
      return OfflineAiReply(text: '$j एक और सुनेंगे या पढ़ाई की बात करें?');
    }

    if (_matchesAny(lower, ['motivat', 'मोटिवेशन', 'quote', 'शायरी', 'सुविचार', 'हिम्मत'])) {
      final q = _quotes[_quoteIndex % _quotes.length];
      _quoteIndex++;
      _lastTopic = 'quote';
      return OfflineAiReply(text: '$q अगर चाहें तो मैं आपका अगला फोकस सेशन प्लान करूँ?');
    }

    if (_matchesAny(lower, ['और बताओ', 'आगे बोलो', 'दूसरा बताओ', 'next', 'more', 'continue'])) {
      if (_lastTopic == 'quiz') {
        _quizIndex = (_quizIndex + 1) % _quizBank.length;
        _awaitingQuizAnswer = true;
        return OfflineAiReply(text: 'अगला सवाल: ${_quizBank[_quizIndex].q}');
      }
      if (_lastTopic == 'joke') {
        final j = _jokes[_jokeIndex % _jokes.length];
        _jokeIndex++;
        return OfflineAiReply(text: j);
      }
      final q = _quotes[_quoteIndex % _quotes.length];
      _quoteIndex++;
      return OfflineAiReply(text: '$q वैसे आज के टास्क चेक करूँ क्या?');
    }

    if (_matchesAny(lower, ['thank', 'thanks', 'धन्यवाद', 'शुक्रिया', 'thnx', 'shukriya'])) {
      return const OfflineAiReply(
        text: 'आपका स्वागत है! जब भी बात करने का मन हो या कोई टास्क प्लान करना हो, मैं यहीं हूँ।',
      );
    }

    if (_matchesAny(lower, ['कौन हो', 'who are you', 'तुम्हारा नाम', 'your name', 'बात करो', 'talk to me'])) {
      _lastTopic = 'intro';
      return const OfflineAiReply(
        text: 'मैं Taskify का स्मार्ट Offline AI दोस्त हूँ! हम बिना इंटरनेट के भी 15 मिनट तक आराम से बात कर सकते हैं—चाहे पढ़ाई की स्ट्रैटेजी हो, विज्ञान/GK के सवाल हों, क्विज़ हो या आपका डेली रूटीन।',
      );
    }

    if (_matchesAny(lower, ['पढ़ाई कैसे', 'study tip', 'याद नहीं रहता', 'रिवीजन', 'revision', 'focus', 'फ़ोकस'])) {
      _lastTopic = 'study';
      return const OfflineAiReply(
        text: 'सबसे असरदार तरीका है 50 मिनट गहरी पढ़ाई और 10 मिनट ब्रेक, फिर 1, 3, 7 और 21 दिन पर रिवीज़न। आप Taskify में Spaced Revision मोड से इसे ऑटोमैटिक सेट कर सकते हैं!',
      );
    }

    if (_matchesAny(lower, ['अभी टाइम', 'क्या समय', 'what time', 'kitne baje', 'कितने बजे', 'आज की तारीख', 'today date', 'कौन सा दिन'])) {
      final now = DateTime.now();
      return OfflineAiReply(
        text: 'अभी समय है ${DateFormat('h:mm a').format(now)}, और आज ${DateFormat('EEEE, d MMMM yyyy').format(now)} है।',
      );
    }

    if (_matchesAny(lower, ['help', 'मदद', 'क्या कर सकते', 'hi', 'hello', 'नमस्ते', 'हेलो', 'hey']) &&
        input.split(RegExp(r'\s+')).length <= 4) {
      return const OfflineAiReply(
        text: 'नमस्ते! मैं आपका Offline Taskify AI हूँ। आज हम किस बारे में बात करें—कोई सवाल, पढ़ाई, क्विज़, या आपका कोई नया टास्क?',
      );
    }

    // 5. Stats / Streak / Progress
    if (_matchesAny(lower, ['streak', 'स्ट्रीक', 'progress', 'प्रोग्रेस', 'stats', 'स्टैट्स', 'रिपोर्ट', 'स्कोर'])) {
      final todayTasks = await db.getTasks(DateTime.now());
      final total = todayTasks.length;
      final done = todayTasks.where((t) => t['status'] == 'completed').length;
      final pending = total - done;
      final pct = total == 0 ? 0 : ((done / total) * 100).round();
      final streak = await db.calculateCurrentStreak();

      return OfflineAiReply(
        text: 'आज की रिपोर्ट: कुल $total टास्क में से $done पूरे हो चुके हैं यानी $pct प्रतिशत। $pending टास्क बाकी हैं, और आपकी स्ट्रीक $streak दिन की है।',
      );
    }

    // 6. Edit / Reschedule Task
    if (_matchesAny(lower, ['edit', 'change', 'update', 'reschedule', 'बदलो', 'एडिट', 'शिफ्ट', 'टाइम बदल'])) {
      final newTime = _extractMinutesOrNull(lower);
      final cleanTitle = _extractCleanTaskTitle(input);
      if (cleanTitle.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क एडिट करना है? उसका नाम और नया समय बताएं।');
      }
      final matches = await db.searchTasks(cleanTitle);
      if (matches.isEmpty) {
        return OfflineAiReply(text: '"$cleanTitle" नाम का कोई आने वाला टास्क नहीं मिला।');
      }
      final t = matches.first;
      if (newTime == null) {
        return OfflineAiReply(text: '"${t['title']}" का नया समय क्या रखना है?');
      }
      final oldStart = t['startMinutes'] as int;
      final oldEnd = t['endMinutes'] as int?;
      final duration = (oldEnd != null && oldEnd > oldStart) ? (oldEnd - oldStart) : 60;
      await db.updateTask(
        t['id'] as int,
        title: t['title'].toString(),
        description: t['description']?.toString() ?? '',
        startMinutes: newTime,
        endMinutes: (newTime + duration) % 1440,
        category: t['category'].toString(),
        priority: t['priority'] as int,
        notes: t['notes']?.toString() ?? '',
        reminder: (t['reminder'] as int) == 1,
        subtasks: t['subtasks']?.toString() ?? '',
        attachmentPath: t['attachmentPath']?.toString() ?? '',
      );
      return OfflineAiReply(
        text: '"${t['title']}" का समय बदलकर ${_formatMinutes(newTime)} कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 7. Complete Task
    if (_matchesAny(lower, ['complete', 'done', 'finish', 'पूरा', 'खत्म', 'हो गया', 'कर लिया'])) {
      final keyword = _extractCleanTaskTitle(input);
      if (keyword.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क पूरा हुआ? कृपया टास्क का नाम बताएं।');
      }

      final matches = await db.searchTasks(keyword);
      final pendingMatch = matches.where((t) => t['status'] != 'completed').toList();
      if (pendingMatch.isEmpty) {
        return OfflineAiReply(text: '"$keyword" नाम का कोई पेंडिंग टास्क नहीं मिला।');
      }

      final task = pendingMatch.first;
      await db.updateStatus(task['id'] as int, 'completed');
      return OfflineAiReply(
        text: 'शाबाश! "${task['title']}" को पूरा मार्क कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 8. Delete Task
    if (_matchesAny(lower, ['delete', 'remove', 'हटाओ', 'डिलीट', 'हटा दो', 'मिटाओ'])) {
      final keyword = _extractCleanTaskTitle(input);
      if (keyword.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क डिलीट करना है? कृपया उसका नाम बताएं।');
      }

      final matches = await db.searchTasks(keyword);
      if (matches.isEmpty) {
        return OfflineAiReply(text: '"$keyword" नाम का कोई टास्क नहीं मिला।');
      }

      final task = matches.first;
      await db.deleteTask(task['id'] as int);
      return OfflineAiReply(
        text: '"${task['title']}" डिलीट कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 9. List / Show Tasks
    if (_matchesAny(lower, ['show', 'list', 'टास्क दिखाओ', 'बाकी टास्क', 'pending', 'आज के टास्क', 'कल के टास्क'])) {
      final targetDate = _extractDateOrNull(lower) ?? DateTime.now();
      final tasks = await db.getTasks(targetDate);
      final dateLabel = _dateLabel(targetDate);

      if (tasks.isEmpty) {
        return OfflineAiReply(text: '$dateLabel कोई टास्क नहीं है। आप नया टास्क जोड़ सकते हैं!');
      }

      final onlyPending = _matchesAny(lower, ['pending', 'बाकी', 'बचे']);
      final filtered = onlyPending ? tasks.where((t) => t['status'] != 'completed').toList() : tasks;

      if (filtered.isEmpty) {
        return OfflineAiReply(text: '$dateLabel के सभी टास्क पूरे हो चुके हैं!');
      }

      final lines = filtered.map((t) {
        final timeStr = _formatMinutes(t['startMinutes'] as int);
        return '$timeStr — ${t['title']}';
      }).join('\n');

      return OfflineAiReply(text: '$dateLabel के ${filtered.length} टास्क:\n$lines');
    }

    // 10. Add Task — सिर्फ़ तभी जब स्पष्ट Create/Add क्रिया हो (अकेले "टास्क" शब्द पर कभी नहीं!),
    // और नाम + समय दोनों मिलने पर ही सेव करेगा, वरना पहले पूछेगा!
    final hasAddVerb = _matchesAny(lower, [
      'add', 'create', 'schedule', 'remind', 'जोड़ो', 'जोड़', 'बनाओ', 'लगाओ', 'सेट करो', 'क्रिएट',
    ]);
    final isQuestion = _matchesAny(lower, ['क्या होता', 'किसे कहते', 'क्या है', 'what is', 'explain']);

    if (hasAddVerb && !isQuestion) {
      _pendingDate = _extractDateOrNull(lower) ?? DateTime.now();
      _pendingMinutes = _extractMinutesOrNull(lower);
      _pendingDaily = _matchesAny(lower, ['daily', 'everyday', 'every day', 'routine', 'रोज', 'रोज़', 'हर दिन', 'रूटीन']);
      _pendingCategory = _detectCategory(lower);

      final title = _extractCleanTaskTitle(input);
      _pendingTitle = title.isEmpty ? null : (title[0].toUpperCase() + title.substring(1));
      _awaitingTask = true;

      return _finalizeOrAskDraft();
    }

    // 11. सामान्य बातचीत का स्वाभाविक जवाब (छोटे/नॉर्मल वाक्यों पर DeepSeek नहीं थोपना)
    if (input.split(RegExp(r'\s+')).length <= 10 &&
        !_matchesAny(lower, ['explain', 'derive', 'essay', 'निबंध', 'इतिहास', 'समीकरण', 'code', 'program'])) {
      return const OfflineAiReply(
        text: 'जी, मैं सुन रहा हूँ! इस विषय पर हम आगे बात कर सकते हैं—आप कोई सवाल पूछ सकते हैं, क्विज़ खेल सकते हैं, या किसी टास्क का नाम और समय बताकर उसे शेड्यूल करवा सकते हैं।',
      );
    }

    return OfflineAiReply(
      text: 'यह एक विस्तृत या ऑनलाइन जानकारी वाला सवाल है। नीचे बटन से सीधे DeepSeek Web या API AI पर पूछ सकते हैं 👇',
      suggestDeepSeek: true,
      deepSeekQuery: input,
    );
  }

  Future<OfflineAiReply> _finalizeOrAskDraft() async {
    if (_pendingTitle == null || _pendingTitle!.trim().isEmpty) {
      return const OfflineAiReply(
        text: 'ज़रूर! इस टास्क का नाम क्या रखना है? और कितने बजे का समय सेट करूँ?',
      );
    }
    if (_pendingMinutes == null) {
      return OfflineAiReply(
        text: 'ठीक है, "$_pendingTitle" किस समय के लिए जोड़ना है? जैसे सुबह 7 बजे या शाम 6:30 बजे।',
      );
    }

    final title = _pendingTitle!;
    final date = _pendingDate ?? DateTime.now();
    final startMinutes = _pendingMinutes!;
    final isDaily = _pendingDaily;
    final category = _pendingCategory ?? 'Personal';

    await db.addTask(
      date: date,
      title: title,
      startMinutes: startMinutes,
      endMinutes: (startMinutes + 60) % 1440,
      category: category,
      priority: 2,
      repeatType: isDaily ? 'daily' : 'once',
      reminder: true,
    );

    if (isDaily) {
      await db.autoAllocateRollingHabits();
    }

    final dateLabel = isDaily ? 'रोज़' : _dateLabel(date);
    final timeLabel = _formatMinutes(startMinutes);
    _resetDraft();

    return OfflineAiReply(
      text: 'टास्क सेव हो गया! नाम: $title, समय: $dateLabel $timeLabel, कैटेगरी: $category।',
      dbChanged: true,
    );
  }

  String? _tryUnitConversion(String lower) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(km|m|cm|kg|g|hr|hrs|hour|hours|min|mins|gb|mb|c|f)\s+(?:to|in|में)\s+(km|m|cm|kg|g|hr|hrs|hour|hours|min|mins|gb|mb|c|f)\b')
        .firstMatch(lower);
    if (m == null) return null;
    final val = double.tryParse(m.group(1)!);
    if (val == null) return null;
    final from = m.group(2)!;
    final to = m.group(3)!;

    double? out;
    if (from == 'km' && to == 'm') out = val * 1000;
    if (from == 'm' && to == 'km') out = val / 1000;
    if (from == 'm' && to == 'cm') out = val * 100;
    if (from == 'cm' && to == 'm') out = val / 100;
    if (from == 'kg' && to == 'g') out = val * 1000;
    if (from == 'g' && to == 'kg') out = val / 1000;
    if ((from.startsWith('hr') || from.startsWith('hour')) && to.startsWith('min')) out = val * 60;
    if (from.startsWith('min') && (to.startsWith('hr') || to.startsWith('hour'))) out = val / 60;
    if (from == 'gb' && to == 'mb') out = val * 1024;
    if (from == 'mb' && to == 'gb') out = val / 1024;
    if (from == 'c' && to == 'f') out = (val * 9 / 5) + 32;
    if (from == 'f' && to == 'c') out = (val - 32) * 5 / 9;

    if (out == null) return null;
    final fmt = out == out.roundToDouble() ? out.toInt().toString() : out.toStringAsFixed(2);
    return '$val $from बराबर $fmt $to होता है।';
  }

  String? _trySimpleMath(String lower) {
    final pct = RegExp(r'(\d+(?:\.\d+)?)\s*%\s*(?:of|का)\s*(\d+(?:\.\d+)?)').firstMatch(lower);
    if (pct != null) {
      final p = double.tryParse(pct.group(1)!);
      final base = double.tryParse(pct.group(2)!);
      if (p != null && base != null) {
        final res = (p / 100) * base;
        final fmt = res == res.roundToDouble() ? res.toInt().toString() : res.toStringAsFixed(2);
        return '$base का $p% बराबर $fmt होता है।';
      }
    }

    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*([+\-*/x×÷])\s*(-?\d+(?:\.\d+)?)\s*$').firstMatch(lower);
    if (m != null) {
      final a = double.tryParse(m.group(1)!);
      final op = m.group(2)!;
      final b = double.tryParse(m.group(3)!);
      if (a != null && b != null) {
        double res;
        switch (op) {
          case '+':
            res = a + b;
            break;
          case '-':
            res = a - b;
            break;
          case '*':
          case 'x':
          case '×':
            res = a * b;
            break;
          case '/':
          case '÷':
            if (b == 0) return '0 से भाग नहीं किया जा सकता।';
            res = a / b;
            break;
          default:
            return null;
        }
        final formatted = res == res.roundToDouble() ? res.toInt().toString() : res.toStringAsFixed(2);
        return 'उत्तर: $formatted';
      }
    }
    final sq = RegExp(r'(?:sqrt|वर्गमूल)\s*\(?\s*(\d+(?:\.\d+)?)\s*\)?').firstMatch(lower);
    if (sq != null) {
      final n = double.tryParse(sq.group(1)!);
      if (n != null) {
        final r = math.sqrt(n);
        final formatted = r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(3);
        return 'वर्गमूल $n बराबर $formatted';
      }
    }
    return null;
  }

  bool _matchesAny(String text, List<String> words) {
    for (final w in words) {
      if (text.contains(w)) return true;
    }
    return false;
  }

  DateTime? _extractDateOrNull(String lower) {
    final now = DateTime.now();
    if (lower.contains('परसों') || lower.contains('day after tomorrow')) {
      return now.add(const Duration(days: 2));
    }
    if (lower.contains('कल') || lower.contains('tomorrow')) {
      return now.add(const Duration(days: 1));
    }
    if (lower.contains('आज') || lower.contains('today')) {
      return now;
    }
    return null;
  }

  int? _extractMinutesOrNull(String lower) {
    final amPmRegex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)');
    final m1 = amPmRegex.firstMatch(lower);
    if (m1 != null) {
      int h = int.parse(m1.group(1)!);
      final min = int.tryParse(m1.group(2) ?? '0') ?? 0;
      final mer = m1.group(3)!;
      if (mer == 'pm' && h < 12) h += 12;
      if (mer == 'am' && h == 12) h = 0;
      return (h.clamp(0, 23) * 60) + min.clamp(0, 59);
    }

    final hindiRegex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:बजे|baje)');
    final m2 = hindiRegex.firstMatch(lower);
    if (m2 != null) {
      int h = int.parse(m2.group(1)!);
      final min = int.tryParse(m2.group(2) ?? '0') ?? 0;
      if (_matchesAny(lower, ['शाम', 'रात', 'दोपहर', 'evening', 'night', 'afternoon']) && h < 12) {
        h += 12;
      }
      return (h.clamp(0, 23) * 60) + min.clamp(0, 59);
    }

    final twentyFour = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(lower);
    if (twentyFour != null) {
      final h = int.parse(twentyFour.group(1)!);
      final min = int.parse(twentyFour.group(2)!);
      return h * 60 + min;
    }

    return null;
  }

  String _detectCategory(String lower) {
    if (_matchesAny(lower, ['study', 'exam', 'test', 'mock', 'revision', 'notes', 'pyq', 'पढ़ाई', 'पढ़ना', 'नोट्स'])) {
      return 'Study';
    }
    if (_matchesAny(lower, ['gym', 'workout', 'run', 'walk', 'yoga', 'exercise', 'जिम', 'व्यायाम', 'दौड़'])) {
      return 'Exercise';
    }
    if (_matchesAny(lower, ['water', 'medicine', 'health', 'sleep', 'पानी', 'दवा', 'सोना', 'सेहत'])) {
      return 'Health';
    }
    if (_matchesAny(lower, ['work', 'office', 'meeting', 'project', 'ऑफिस', 'मीटिंग', 'काम'])) {
      return 'Work';
    }
    return 'Personal';
  }

  String _extractCleanTaskTitle(String input) {
    var cleaned = input
        .replaceAll(RegExp(r'\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d{1,2}(?::\d{2})?\s*(?:बजे|baje)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b'), '');

    return _cleanKeywords(cleaned, [
      'add', 'create', 'remind', 'me', 'to', 'reminder', 'schedule', 'task', 'routine',
      'daily', 'everyday', 'every', 'day', 'today', 'tomorrow', 'at', 'for', 'a', 'an', 'the',
      'new', 'one', 'please', 'pls', 'set', 'make', 'my', 'name', 'time', 'is', 'edit', 'update',
      'delete', 'remove', 'complete', 'done', 'finish', 'change',
      'जोड़ो', 'जोड़', 'बनाओ', 'बना', 'लगाओ', 'लगा', 'करो', 'करना', 'कर', 'दो', 'देना', 'चाहिए',
      'क्रिएट', 'एडिट', 'बदलो', 'डिलीट', 'हटाओ', 'पूरा', 'हो', 'गया',
      'टास्क', 'रूटीन', 'रिमाइंडर', 'अलार्म', 'नया', 'एक', 'वाला', 'मेरा', 'नाम', 'टाइम', 'समय',
      'आज', 'कल', 'परसों', 'रोज', 'रोज़', 'हर', 'दिन', 'सुबह', 'शाम', 'रात', 'दोपहर',
      'का', 'की', 'के', 'को', 'में', 'पर', 'से', 'है', 'हूं', 'हूँ', 'ये', 'यह', 'रखना', 'रखो',
    ]);
  }

  String _cleanKeywords(String input, List<String> stopWords) {
    final stopSet = stopWords.map((e) => e.toLowerCase()).toSet();
    final parts = input.split(RegExp(r'\s+')).where((w) {
      final clean = w.replaceAll(RegExp(r'[,.!?।:]'), '').toLowerCase();
      return clean.isNotEmpty && !stopSet.contains(clean);
    });
    return parts.join(' ').trim();
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final dt = DateTime(2026, 1, 1, h, m);
    return DateFormat('h:mm a').format(dt);
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'आज';
    if (diff == 1) return 'कल';
    if (diff == 2) return 'परसों';
    return DateFormat('dd MMM').format(date);
  }
}
