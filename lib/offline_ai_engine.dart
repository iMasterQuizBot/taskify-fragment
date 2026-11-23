import 'dart:convert';
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

  // मल्टी-टर्न टास्क मेमोरी
  bool _awaitingTask = false;
  String? _pendingTitle;
  DateTime? _pendingDate;
  int? _pendingMinutes;
  int? _pendingEndMinutes;
  String _pendingRepeatType = 'once';
  String _pendingRepeatDays = '';
  String? _pendingCategory;
  int _pendingPriority = 2;
  bool _pendingReminder = true;
  List<String> _pendingSubtasks = [];
  String _pendingNotes = '';

  // कन्वर्सेशन व क्विज़ मेमोरी
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
    'सफलता एक दिन में नहीं मिलती, लेकिन रोज़ की छोटी मेहनत एक दिन सफलता ज़रूर दिलाती है। आज का 1 फोकस घंटा कल का भविष्य तय करता है!',
    'जब थक जाओ तो थोड़ा आराम कर लो, लेकिन हार कभी मत मानो — आपकी निरंतरता ही आपकी सबसे बड़ी ताकत है!',
    'बड़ा लक्ष्य छोटे-छोटे फोकस सेशन्स से ही पूरा होता है। अभी बस अगले 25 मिनट पूरी ईमानदारी से लगा दो!',
    'जो समय को सही से व्यवस्थित कर लेता है, समय उसे सबसे आगे खड़ा कर देता है। आप कर सकते हो!',
  ];

  static const List<String> _jokes = [
    'एक स्टूडेंट ने अलार्म से कहा: "तू रोज़ सुबह चिल्लाता है, कभी खुद भी उठकर पढ़ लिया कर!"',
    'दिमाग़ परीक्षा से पहले: सब याद है। परीक्षा हॉल में: ये सिलेबस में कब आया भाई?',
    'नींद और पढ़ाई की पुरानी दुश्मनी है — किताब खोलते ही नींद सबसे अच्छी दोस्त बन जाती है!',
  ];

  static const List<({List<String> keys, String answer})> _knowledgeBase = [
    (
      keys: ['gravity', 'गुरुत्वाकर्षण', 'g की वैल्यू', 'value of g'],
      answer: 'पृथ्वी पर गुरुत्वाकर्षण त्वरण (g) का मान लगभग 9.81 मीटर प्रति सेकंड स्क्वायर होता है। लगे रहो, यही छोटे कॉन्सेप्ट एग्जाम में नंबर दिलाते हैं!',
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
      answer: 'एक वयस्क व्यक्ति को दिन में लगभग 2.5 से 3.5 लीटर (करीब 8–10 गिलास) पानी पीना चाहिए। हाइड्रेटेड रहोगे तो दिमाग़ तेज़ चलेगा!',
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

  static DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  String _motivationalTail() => _quotes[_quoteIndex % _quotes.length];

  void _resetDraft() {
    _awaitingTask = false;
    _pendingTitle = null;
    _pendingDate = null;
    _pendingMinutes = null;
    _pendingEndMinutes = null;
    _pendingRepeatType = 'once';
    _pendingRepeatDays = '';
    _pendingCategory = null;
    _pendingPriority = 2;
    _pendingReminder = true;
    _pendingSubtasks = [];
    _pendingNotes = '';
  }

  Future<OfflineAiReply> process(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return const OfflineAiReply(
        text: 'कुछ बोलें या लिखें — जैसे टास्क जोड़ें, एडिट करें, 1–2 महीने का इतिहास देखें, या पढ़ाई की बात करें। आप हर दिन बेहतर बन रहे हैं!',
      );
    }

    _recentTopics.add(input);
    if (_recentTopics.length > 30) _recentTopics.removeAt(0);

    final lower = input.toLowerCase();

    // 0.1. A-to-Z ऐप फ़ीचर गाइड (कहाँ से क्या करना है)
    if (_matchesAny(lower, ['pdf', 'पीडीएफ', 'मंथली रिपोर्ट'])) {
      return const OfflineAiReply(
        text: '📄 PDF मंथली रिपोर्ट निकालने के लिए Settings → Productivity Tools → "Generate Monthly Report File" पर टैप करें।',
      );
    }
    if (_matchesAny(lower, ['फिंगरप्रिंट', 'fingerprint', 'biometric', 'pin lock', 'लॉक'])) {
      return const OfflineAiReply(
        text: '🔒 PIN और Fingerprint लॉक के लिए Settings → Security में जाएँ, वहाँ पहले 4-अंकों का PIN सेट करें और फिर "Fingerprint / Biometric Unlock" चालू करें।',
      );
    }
    if (_matchesAny(lower, ['रिपीट मोड', 'repeat mode', 'kitne repeat', 'कौन-कौन से रिपीट'])) {
      return const OfflineAiReply(
        text: '🔁 Taskifyy में कुल 8 रिपीट मोड हैं: 1) One time, 2) Every day (Daily), 3) Alternate Day (एक दिन छोड़ कर), 4) Weekdays (Mon–Fri), 5) Weekends (Sat–Sun), 6) Custom Days (हफ़्ते के चुने दिन), 7) Custom Dates (कैलेंडर तारीखें), और 8) Spaced Revision (1, 3, 7, 21 दिन)। आप मुझे बोलकर इनमें से कोई भी लगवा सकते हैं!',
      );
    }
    if (_matchesAny(lower, ['बैकअप', 'backup', 'restore', 'import', 'export', 'इम्पोर्ट'])) {
      return const OfflineAiReply(
        text: '💾 बैकअप और रीस्टोर के लिए Settings → Backup & Sync में जाएँ। "Export Backup File (.json)" से पूरा बैकअप (टास्क, कैटेगरी, टेम्पलेट, सेटिंग्स, AI चैट) सेव होगा और "Import Backup File (.json)" से वापस आ जाएगा।',
      );
    }
    if (_matchesAny(lower, ['विजेट', 'widget', 'होम स्क्रीन'])) {
      return const OfflineAiReply(
        text: '📱 फोन की होम स्क्रीन पर खाली जगह दबाकर रखें → Widgets → Taskifyy चुनें। वहाँ आपको 42 Apple Glass विजेट्स (Progress Ring, Bar Chart, Column Chart, Offline AI, API AI आदि) मिलेंगे!',
      );
    }

    // 0. डेवलपर पहचान (Dilkhush Chauhan / दिलखुश चौहान)
    if (_matchesAny(lower, [
      'किसने बनाया', 'किसने डेवलप', 'डेवलपर', 'developer', 'who made', 'who created',
      'who built', 'creator', 'निर्माता', 'तुम्हें किसने', 'app kisne', 'banaya kisne',
    ])) {
      return const OfflineAiReply(
        text: 'मुझे और Taskifyy ऐप को **Dilkhush Chauhan (दिलखुश चौहान)** ने डेवलप किया है! मेरा लक्ष्य है आपकी पढ़ाई और रूटीन को आसान बनाना और आपको हर दिन प्रेरित रखना।',
      );
    }

    // 0.2. अधूरा टास्क ड्राफ्ट पूरा करना
    if (_awaitingTask) {
      if (_matchesAny(lower, ['cancel', 'रद्द', 'छोड़ो', 'रहने दो', 'मत जोड़ो', 'stop', 'बंद करो'])) {
        _resetDraft();
        return const OfflineAiReply(text: 'ठीक है, टास्क जोड़ना रद्द कर दिया है। बताइए अब आगे क्या करना है?');
      }

      final extractedTime = _extractMinutesOrNull(lower);
      final extractedDate = _extractDateOrNull(lower);
      if (extractedTime != null) _pendingMinutes = extractedTime;
      if (extractedDate != null) _pendingDate = extractedDate;
      _parseRepeatFromInput(lower);
      _parsePriorityFromInput(lower);
      _parseReminderFromInput(lower);
      final subs = _extractSubtasks(input);
      if (subs.isNotEmpty) _pendingSubtasks = subs;

      final explicitCat = await _detectExistingOrNamedCategory(input, lower);
      if (explicitCat != null) _pendingCategory = explicitCat;

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
        return OfflineAiReply(text: 'सही जवाब है: $ans। कोई बात नहीं, सीखते रहना ही असली जीत है! अगला सवाल पूछूँ?');
      }
      final item = _quizBank[_quizIndex];
      _awaitingQuizAnswer = false;
      if (lower.contains(item.hint.toLowerCase()) || lower.contains(item.a.toLowerCase())) {
        return const OfflineAiReply(text: 'शाबाश! बिल्कुल सही जवाब! आपकी तैयारी कमाल की है! अगला सवाल पूछूँ?');
      } else {
        return OfflineAiReply(text: 'बहुत करीब थे! सही जवाब है: ${item.a}। लगे रहो, अगला सवाल पूछूँ?');
      }
    }

    // 1. क्विज़ / GK मोड
    if (_matchesAny(lower, ['quiz', 'क्विज़', 'सवाल पूछो', 'gk', 'टेस्ट लो', 'अगला सवाल', 'question pucho'])) {
      _quizIndex = (_quizIndex + 1) % _quizBank.length;
      _awaitingQuizAnswer = true;
      _lastTopic = 'quiz';
      return OfflineAiReply(text: 'चलिए एक छोटा सा क्विज़ खेलते हैं! सवाल: ${_quizBank[_quizIndex].q}');
    }

    // 2. यूनिट कन्वर्ज़न व गणित
    final conv = _tryUnitConversion(lower);
    if (conv != null) return OfflineAiReply(text: conv);

    final mathReply = _trySimpleMath(lower);
    if (mathReply != null) return OfflineAiReply(text: mathReply);

    // 3. बिल्ट-इन नॉलेज बेस
    for (final entry in _knowledgeBase) {
      if (_matchesAny(lower, entry.keys)) {
        _lastTopic = 'knowledge';
        return OfflineAiReply(text: entry.answer);
      }
    }

    // 4. कैटेगरी देखना या जोड़ना
    if (_matchesAny(lower, ['category list', 'categories', 'कैटेगरी दिखाओ', 'कौन सी कैटेगरी'])) {
      final cats = await db.categories();
      final names = cats.map((c) => c['name'].toString()).join(', ');
      return OfflineAiReply(text: 'ऐप में मौजूद कैटेगरी: $names। आप किसी भी नाम से नई कैटेगरी भी बनवा सकते हैं!');
    }
    if (_matchesAny(lower, ['नई कैटेगरी', 'add category', 'create category', 'कैटेगरी जोड़ो', 'कैटेगरी बनाओ'])) {
      final name = _cleanKeywords(input, ['नई', 'कैटेगरी', 'जोड़ो', 'बनाओ', 'add', 'create', 'category', 'name']);
      if (name.isEmpty) {
        return const OfflineAiReply(text: 'नई कैटेगरी का नाम बताइए (जैसे: "नई कैटेगरी MockTest जोड़ो")।');
      }
      final formatted = name[0].toUpperCase() + name.substring(1);
      await db.addCategory(formatted);
      return OfflineAiReply(text: '✅ नई कैटेगरी "$formatted" जोड़ दी गई है!', dbChanged: true);
    }

    // 5. नोटिफिकेशन / ऐप सेटिंग कंट्रोल
    if (_matchesAny(lower, ['नोटिफिकेशन बंद', 'notification off', 'notifications off', 'रिमाइंडर बंद'])) {
      await db.setSetting('notificationsEnabled', '0');
      return const OfflineAiReply(text: '🔕 सभी नोटिफिकेशन बंद कर दिए गए हैं।', dbChanged: true);
    }
    if (_matchesAny(lower, ['नोटिफिकेशन चालू', 'notification on', 'notifications on', 'रिमाइंडर चालू'])) {
      await db.setSetting('notificationsEnabled', '1');
      await db.rescheduleAllReminders();
      return const OfflineAiReply(text: '🔔 सभी नोटिफिकेशन चालू कर दिए गए हैं!', dbChanged: true);
    }

    // 6. Overdue Reschedule
    if (_matchesAny(lower, ['overdue', 'ओवरड्यू', 'छूटे हुए टास्क', 'reschedule overdue'])) {
      final moved = await db.rescheduleOverdueTasks(_nowIst());
      if (moved == 0) {
        return const OfflineAiReply(text: 'आज कोई भी Overdue टास्क नहीं है—आप बिल्कुल समय पर चल रहे हैं! शाबाश!');
      }
      return OfflineAiReply(
        text: '✨ $moved Overdue टास्क अगले खाली स्लॉट में शिफ़्ट कर दिए गए हैं! हार मत मानो, अभी भी दिन जीत सकते हो!',
        dbChanged: true,
      );
    }

    // 7. 1–2 महीने का इतिहास / पुरानी रिपोर्ट / सर्च
    if (_matchesAny(lower, ['1 महीने', 'एक महीने', '2 महीने', 'दो महीने', 'last month', 'two months', '30 दिन', '60 दिन', 'history', 'इतिहास', 'पुराने टास्क', 'पिछले महीने'])) {
      final days = _matchesAny(lower, ['2 महीने', 'दो महीने', 'two months', '60 दिन']) ? 60 : 30;
      final end = _nowIst();
      final start = end.subtract(Duration(days: days));
      final rows = await db.tasksBetween(start, end);
      final total = rows.length;
      final done = rows.where((r) => r['status'] == 'completed').length;
      final pct = total == 0 ? 0 : ((done / total) * 100).round();
      final Map<String, int> catDone = {};
      for (final r in rows.where((r) => r['status'] == 'completed')) {
        final c = r['category'].toString();
        catDone[c] = (catDone[c] ?? 0) + 1;
      }
      final catSummary = catDone.isEmpty
          ? 'कोई पूरा टास्क नहीं'
          : catDone.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      return OfflineAiReply(
        text: '📊 पिछले $days दिनों का पूरा रिकॉर्ड:\n'
            '• कुल टास्क: $total | पूरे हुए: $done ($pct%)\n'
            '• कैटेगरी अनुसार पूरे टास्क: $catSummary\n'
            '💪 हर छोटा कदम मायने रखता है—इसी तरह आगे बढ़ते रहो!',
      );
    }

    if (_matchesAny(lower, ['search ', 'खोजो ', 'ढूंढो ', 'ढूँढो '])) {
      final q = _cleanKeywords(input, ['search', 'खोजो', 'ढूंढो', 'ढूँढो', 'task', 'टास्क']);
      if (q.isNotEmpty) {
        final found = await db.searchAllTasks(q);
        if (found.isEmpty) {
          return OfflineAiReply(text: '"$q" से जुड़ा कोई टास्क आपके इतिहास में नहीं मिला।');
        }
        final lines = found.take(8).map((t) => '• ${t['date']} (${_formatMinutes(t['startMinutes'] as int)}) — ${t['title']} [${t['status']}]').join('\n');
        return OfflineAiReply(text: '🔍 "$q" से मिले टास्क (${found.length}):\n$lines');
      }
    }

    // 8. Stats / Streak / Progress
    if (_matchesAny(lower, ['streak', 'स्ट्रीक', 'progress', 'प्रोग्रेस', 'stats', 'स्टैट्स', 'रिपोर्ट', 'स्कोर'])) {
      final todayTasks = await db.getTasks(_nowIst());
      final total = todayTasks.length;
      final done = todayTasks.where((t) => t['status'] == 'completed').length;
      final pending = total - done;
      final pct = total == 0 ? 0 : ((done / total) * 100).round();
      final streak = await db.calculateCurrentStreak();

      return OfflineAiReply(
        text: '📊 आज की रिपोर्ट: कुल $total में से $done टास्क पूरे ($pct%), $pending बाकी, और 🔥 $streak दिन की स्ट्रीक!\n'
            '🌟 याद रखो: ${_motivationalTail()}',
      );
    }

    // 9. सामान्य बातचीत + मोटिवेशन
    if (_matchesAny(lower, ['कैसे हो', 'कैसी हो', 'how are you', 'kya haal', 'क्या हाल', 'sab badhiya'])) {
      _lastTopic = 'chat';
      return const OfflineAiReply(
        text: 'मैं बिल्कुल बढ़िया हूँ और आपको आगे बढ़ते देखकर बहुत खुश हूँ! बताइए आज पढ़ाई और काम का क्या टारगेट रखा है?',
      );
    }

    if (_matchesAny(lower, ['बोर', 'boring', 'bore', 'मन नहीं', 'अच्छा नहीं लग'])) {
      _lastTopic = 'mood';
      return const OfflineAiReply(
        text: 'जब मन न लगे, तब खुद को बस 10 मिनट का छोटा टारगेट दो—शुरुआत होते ही लय बन जाती है! चाहो तो एक क्विज़ खेलें या कोई जोक सुनाऊँ?',
      );
    }

    if (_matchesAny(lower, ['थक', 'tired', 'नींद', 'sleepy', 'सिर दर्द', 'टेंशन', 'stress', 'tension', 'हार', 'डिमोटिवेट'])) {
      _lastTopic = 'relax';
      return const OfflineAiReply(
        text: 'गहरी साँस लो—आप जितना सोचते हो उससे कहीं ज़्यादा मज़बूत हो! थोड़ा पानी पीकर 5 मिनट आँखें बंद करो, फिर सिर्फ़ एक आसान टास्क से शुरुआत करो। मैं हमेशा आपके साथ हूँ!',
      );
    }

    if (_matchesAny(lower, ['अच्छा जा रहा', 'बढ़िया', 'मस्त', 'good', 'great', 'fine', 'ठीक हूँ', 'theek hu'])) {
      _lastTopic = 'chat';
      return const OfflineAiReply(
        text: 'बहुत बढ़िया! यही सकारात्मक ऊर्जा आपको मंज़िल तक ले जाएगी। बताइए आज का सबसे अहम टास्क कौन सा है?',
      );
    }

    if (_matchesAny(lower, ['जोक', 'joke', 'हंसाओ', 'मज़ाक', 'funny'])) {
      final j = _jokes[_jokeIndex % _jokes.length];
      _jokeIndex++;
      _lastTopic = 'joke';
      return OfflineAiReply(text: '$j 😄 थोड़ा मुस्कुरा लिया हो तो अब अगले गोल पर फोकस करें!');
    }

    if (_matchesAny(lower, ['motivat', 'मोटिवेशन', 'quote', 'शायरी', 'सुविचार', 'हिम्मत'])) {
      final q = _quotes[_quoteIndex % _quotes.length];
      _quoteIndex++;
      _lastTopic = 'quote';
      return OfflineAiReply(text: '🔥 $q');
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
      return OfflineAiReply(text: '$q बताइए आज का कोई टास्क सेट करूँ?');
    }

    if (_matchesAny(lower, ['thank', 'thanks', 'धन्यवाद', 'शुक्रिया', 'thnx', 'shukriya'])) {
      return const OfflineAiReply(
        text: 'आपका स्वागत है! मेहनत करते रहिए, आपकी सफलता पक्की है!',
      );
    }

    if (_matchesAny(lower, ['कौन हो', 'who are you', 'तुम्हारा नाम', 'your name', 'बात करो', 'talk to me'])) {
      _lastTopic = 'intro';
      return const OfflineAiReply(
        text: 'मैं Taskifyy का स्मार्ट Offline AI और आपका स्टडी मेंटर हूँ, जिसे **Dilkhush Chauhan (दिलखुश चौहान)** ने बनाया है! मैं आपके सारे टास्क, कैटेगरी, प्रायोरिटी, रिपीट मोड और मोटिवेशन सब संभालता हूँ।',
      );
    }

    if (_matchesAny(lower, ['पढ़ाई कैसे', 'study tip', 'याद नहीं रहता', 'रिवीजन', 'revision', 'focus', 'फ़ोकस'])) {
      _lastTopic = 'study';
      return const OfflineAiReply(
        text: 'टॉपर्स का नियम: 50 मिनट डीप स्टडी + 10 मिनट ब्रेक, और हर टॉपिक को 1, 3, 7 और 21 दिन पर दोहराएँ। आप मुझसे बोलकर सीधे **Spaced Revision** टास्क लगवा सकते हैं!',
      );
    }

    if (_matchesAny(lower, ['अभी टाइम', 'क्या समय', 'what time', 'kitne baje', 'कितने बजे', 'आज की तारीख', 'today date', 'कौन सा दिन'])) {
      final now = _nowIst();
      return OfflineAiReply(
        text: '🕒 अभी भारतीय समय है ${DateFormat('h:mm a').format(now)}, और आज ${DateFormat('EEEE, d MMMM yyyy').format(now)} है। हर मिनट कीमती है, इसका बेस्ट यूज़ करें!',
      );
    }

    if (_matchesAny(lower, ['help', 'मदद', 'क्या कर सकते', 'hi', 'hello', 'नमस्ते', 'हेलो', 'hey']) &&
        input.split(RegExp(r'\s+')).length <= 4) {
      return const OfflineAiReply(
        text: 'नमस्ते! मैं आपका Taskifyy Offline AI और मोटिवेटर हूँ। आप मुझसे टास्क जोड़ना (कैटेगरी, प्रायोरिटी, रिपीट मोड, सबटास्क सहित), 1–2 महीने का रिकॉर्ड, क्विज़ या पढ़ाई की बात कर सकते हैं—बताइए आज क्या जीत हासिल करनी है?',
      );
    }

    // 10. Edit / Reschedule Task (Time, Priority, Category)
    if (_matchesAny(lower, ['edit', 'change', 'update', 'reschedule', 'बदलो', 'एडिट', 'शिफ्ट', 'टाइम बदल'])) {
      final newTime = _extractMinutesOrNull(lower);
      final cleanTitle = _extractCleanTaskTitle(input);
      if (cleanTitle.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क एडिट करना है? उसका नाम और नया समय/प्रायोरिटी बताएं।');
      }
      final matches = await db.searchAllTasks(cleanTitle);
      if (matches.isEmpty) {
        return OfflineAiReply(text: '"$cleanTitle" नाम का कोई टास्क नहीं मिला।');
      }
      final t = matches.first;
      final newPri = _hasPriorityWord(lower) ? _parsePriorityValue(lower) : (t['priority'] as int);
      final newCat = await _detectExistingOrNamedCategory(input, lower) ?? t['category'].toString();
      final oldStart = t['startMinutes'] as int;
      final oldEnd = t['endMinutes'] as int?;
      final duration = (oldEnd != null && oldEnd > oldStart) ? (oldEnd - oldStart) : 60;
      final finalStart = newTime ?? oldStart;

      await db.updateTask(
        t['id'] as int,
        title: t['title'].toString(),
        description: t['description']?.toString() ?? '',
        startMinutes: finalStart,
        endMinutes: (finalStart + duration) % 1440,
        category: newCat,
        priority: newPri,
        notes: t['notes']?.toString() ?? '',
        reminder: _hasReminderWord(lower) ? _parseReminderValue(lower) : (t['reminder'] == 1),
        subtasks: t['subtasks']?.toString() ?? '',
        attachmentPath: t['attachmentPath']?.toString() ?? '',
      );
      return OfflineAiReply(
        text: '✏️ "${t['title']}" अपडेट हो गया (${_formatMinutes(finalStart)}, $newCat, Priority ${_priorityLabel(newPri)})!',
        dbChanged: true,
      );
    }

    // 11. Complete / Skip Task
    if (_matchesAny(lower, ['skip', 'स्किप', 'छोड़ दो'])) {
      final keyword = _extractCleanTaskTitle(input);
      if (keyword.isNotEmpty) {
        final matches = await db.searchTasks(keyword);
        if (matches.isNotEmpty) {
          await db.updateStatus(matches.first['id'] as int, 'skipped');
          return OfflineAiReply(text: '⏭️ "${matches.first['title']}" को Skipped मार्क कर दिया गया है।', dbChanged: true);
        }
      }
    }

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
        text: '✅ शाबाश चैंपियन! "${task['title']}" पूरा हो गया—ऐसे ही हर लक्ष्य को पार करते रहो!',
        dbChanged: true,
      );
    }

    // 12. Delete Task
    if (_matchesAny(lower, ['delete', 'remove', 'हटाओ', 'डिलीट', 'हटा दो', 'मिटाओ'])) {
      final keyword = _extractCleanTaskTitle(input);
      if (keyword.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क डिलीट करना है? कृपया उसका नाम बताएं।');
      }

      final matches = await db.searchAllTasks(keyword);
      if (matches.isEmpty) {
        return OfflineAiReply(text: '"$keyword" नाम का कोई टास्क नहीं मिला।');
      }

      final task = matches.first;
      await db.deleteTask(task['id'] as int);
      return OfflineAiReply(
        text: '🗑️ "${task['title']}" डिलीट कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 13. List / Show Tasks
    if (_matchesAny(lower, ['show', 'list', 'टास्क दिखाओ', 'बाकी टास्क', 'pending', 'आज के टास्क', 'कल के टास्क'])) {
      final targetDate = _extractDateOrNull(lower) ?? _nowIst();
      final tasks = await db.getTasks(targetDate);
      final dateLabel = _dateLabel(targetDate);

      if (tasks.isEmpty) {
        return OfflineAiReply(text: '$dateLabel कोई टास्क नहीं है। चलिए आज का पहला लक्ष्य सेट करते हैं!');
      }

      final onlyPending = _matchesAny(lower, ['pending', 'बाकी', 'बचे']);
      final filtered = onlyPending ? tasks.where((t) => t['status'] != 'completed').toList() : tasks;

      if (filtered.isEmpty) {
        return OfflineAiReply(text: '🎉 वाह! $dateLabel के सभी टास्क पूरे हो चुके हैं! आपको खुद पर गर्व होना चाहिए!');
      }

      final lines = filtered.map((t) {
        final timeStr = _formatMinutes(t['startMinutes'] as int);
        return '$timeStr — ${t['title']} (${t['category']}, ${_priorityLabel(t['priority'] as int)})';
      }).join('\n');

      return OfflineAiReply(text: '📅 $dateLabel के ${filtered.length} टास्क:\n$lines\n\n💪 एक-एक करके सबको पूरा कर डालो!');
    }

    // 14. Add Task (Priority, Category, Repeat Mode, Subtasks, Reminder सहित)
    final hasAddVerb = _matchesAny(lower, [
      'add', 'create', 'schedule', 'remind', 'जोड़ो', 'जोड़', 'बनाओ', 'लगाओ', 'सेट करो', 'क्रिएट',
    ]);
    final isQuestion = _matchesAny(lower, ['क्या होता', 'किसे कहते', 'क्या है', 'what is', 'explain']);

    if (hasAddVerb && !isQuestion) {
      _resetDraft();
      _pendingDate = _extractDateOrNull(lower) ?? _nowIst();
      _pendingMinutes = _extractMinutesOrNull(lower);
      _parseRepeatFromInput(lower);
      _parsePriorityFromInput(lower);
      _parseReminderFromInput(lower);
      _pendingSubtasks = _extractSubtasks(input);
      _pendingCategory = await _detectExistingOrNamedCategory(input, lower) ?? _detectCategory(lower);

      final title = _extractCleanTaskTitle(input);
      final genericTitles = {'task', 'work', 'kaam', 'something', 'new', 'टास्क', 'काम', 'कुछ'};
      _pendingTitle = (title.isEmpty || genericTitles.contains(title.toLowerCase()) || title.split(' ').length > 6)
          ? null
          : (title[0].toUpperCase() + title.substring(1));
      _awaitingTask = true;

      return _finalizeOrAskDraft();
    }

    // 15. सामान्य बातचीत (मोटिवेशनल दोस्त की तरह)
    if (input.split(RegExp(r'\s+')).length <= 10 &&
        !_matchesAny(lower, ['explain', 'derive', 'essay', 'निबंध', 'इतिहास', 'समीकरण', 'code', 'program'])) {
      _quoteIndex++;
      return OfflineAiReply(
        text: 'जी, मैं आपकी बात समझ रहा हूँ! ${_motivationalTail()} आप चाहें तो कोई सवाल पूछें, क्विज़ खेलें, या कोई नया टास्क शेड्यूल करवाएँ।',
      );
    }

    return OfflineAiReply(
      text: 'यह एक विस्तृत या ऑनलाइन जानकारी वाला सवाल है। नीचे बटन से सीधे DeepSeek Web या API AI पर पूछ सकते हैं 👇',
      suggestDeepSeek: true,
      deepSeekQuery: input,
    );
  }

  void _parseRepeatFromInput(String lower) {
    if (_matchesAny(lower, ['spaced', 'रिवीजन', 'revision', '1 3 7 21'])) {
      _pendingRepeatType = 'spaced';
    } else if (_matchesAny(lower, ['alternate', 'एक दिन छोड़', 'ek din chod'])) {
      _pendingRepeatType = 'alternate';
    } else if (_matchesAny(lower, ['weekday', 'mon-fri', 'सोम से शुक्र', 'monday to friday'])) {
      _pendingRepeatType = 'weekdays';
    } else if (_matchesAny(lower, ['weekend', 'sat-sun', 'शनि रवि', 'सप्ताह के अंत'])) {
      _pendingRepeatType = 'weekends';
    } else if (_matchesAny(lower, ['daily', 'everyday', 'every day', 'routine', 'रोज', 'रोज़', 'हर दिन', 'रूटीन'])) {
      _pendingRepeatType = 'daily';
    } else {
      final days = <String>[];
      const map = {
        'mon': 'Mon', 'सोम': 'Mon',
        'tue': 'Tue', 'मंगल': 'Tue',
        'wed': 'Wed', 'बुध': 'Wed',
        'thu': 'Thu', 'गुरु': 'Thu', 'बृहस्पति': 'Thu',
        'fri': 'Fri', 'शुक्र': 'Fri',
        'sat': 'Sat', 'शनि': 'Sat',
        'sun': 'Sun', 'रवि': 'Sun',
      };
      map.forEach((k, v) {
        if (lower.contains(k) && !days.contains(v)) days.add(v);
      });
      if (days.isNotEmpty) {
        _pendingRepeatType = 'custom_days';
        _pendingRepeatDays = days.join(',');
      }
      final dateMatches = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b').allMatches(lower).map((m) => m.group(1)!).toList();
      if (dateMatches.isNotEmpty) {
        _pendingRepeatType = 'custom_dates';
        _pendingRepeatDays = dateMatches.join(',');
      }
    }
  }

  bool _hasPriorityWord(String lower) => _matchesAny(lower, [
        'critical', 'high', 'normal', 'low', 'क्रिटिकल', 'हाई', 'ज़रूरी', 'जरूरी', 'सामान्य', 'कम',
      ]);

  int _parsePriorityValue(String lower) {
    if (_matchesAny(lower, ['critical', 'क्रिटिकल', 'अति आवश्यक', 'urgent'])) return 4;
    if (_matchesAny(lower, ['high', 'हाई', 'ज़रूरी', 'जरूरी', 'important'])) return 3;
    if (_matchesAny(lower, ['low', 'कम', 'लो'])) return 1;
    return 2;
  }

  void _parsePriorityFromInput(String lower) {
    if (_hasPriorityWord(lower)) _pendingPriority = _parsePriorityValue(lower);
  }

  bool _hasReminderWord(String lower) => _matchesAny(lower, ['reminder', 'रिमाइंडर', 'अलार्म', 'alarm', 'notification']);

  bool _parseReminderValue(String lower) {
    if (_matchesAny(lower, ['off', 'बंद', 'नहीं', 'no reminder', 'मत'])) return false;
    return true;
  }

  void _parseReminderFromInput(String lower) {
    if (_hasReminderWord(lower)) _pendingReminder = _parseReminderValue(lower);
  }

  List<String> _extractSubtasks(String input) {
    final m = RegExp(r'(?:subtasks?|checklist|सबटास्क|चेकलिस्ट)\s*[:\-]\s*(.+)$', caseSensitive: false).firstMatch(input);
    if (m == null) return [];
    return m.group(1)!.split(RegExp(r'[,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<String?> _detectExistingOrNamedCategory(String input, String lower) async {
    final cats = await db.categories();
    for (final c in cats) {
      final n = c['name'].toString();
      if (lower.contains(n.toLowerCase())) return n;
    }
    return null;
  }

  String _priorityLabel(int p) {
    switch (p) {
      case 4:
        return 'Critical';
      case 3:
        return 'High';
      case 2:
        return 'Normal';
      default:
        return 'Low';
    }
  }

  Future<OfflineAiReply> _finalizeOrAskDraft() async {
    if (_pendingTitle == null || _pendingTitle!.trim().isEmpty) {
      return const OfflineAiReply(
        text: 'ज़रूर! इस टास्क का नाम क्या रखना है? (चाहें तो समय, कैटेगरी, प्रायोरिटी या रिपीट मोड भी साथ बोल दें!)',
      );
    }
    if (_pendingMinutes == null) {
      return OfflineAiReply(
        text: 'ठीक है, "$_pendingTitle" किस समय के लिए जोड़ना है? जैसे सुबह 7 बजे या शाम 6:30 बजे।',
      );
    }

    final title = _pendingTitle!;
    final date = _pendingDate ?? _nowIst();
    final startMinutes = _pendingMinutes!;
    final endMinutes = _pendingEndMinutes ?? ((startMinutes + 60) % 1440);
    final category = _pendingCategory ?? 'Personal';
    final pri = _pendingPriority;
    final rem = _pendingReminder;
    final subsJson = _pendingSubtasks.isEmpty
        ? ''
        : jsonEncode(_pendingSubtasks.map((s) => {'title': s, 'done': false}).toList());

    if (_pendingRepeatType == 'spaced') {
      for (final offset in [0, 1, 3, 7, 21]) {
        final target = date.add(Duration(days: offset));
        final suffix = offset == 0 ? '' : ' (Rev +${offset}d)';
        await db.addTask(
          date: target,
          title: '$title$suffix',
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          category: category,
          priority: pri,
          repeatType: 'once',
          notes: _pendingNotes,
          reminder: rem,
          subtasks: subsJson,
        );
      }
    } else if (_pendingRepeatType == 'alternate') {
      for (int i = 0; i < 60; i += 2) {
        await db.addTask(
          date: date.add(Duration(days: i)),
          title: title,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          category: category,
          priority: pri,
          repeatType: 'alternate',
          notes: _pendingNotes,
          reminder: rem,
          subtasks: subsJson,
          playSound: i == 0,
        );
      }
    } else {
      await db.addTask(
        date: date,
        title: title,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        category: category,
        priority: pri,
        repeatType: _pendingRepeatType,
        repeatDays: _pendingRepeatDays,
        notes: _pendingNotes,
        reminder: rem,
        subtasks: subsJson,
      );
      if (_pendingRepeatType != 'once') {
        await db.autoAllocateRollingHabits();
      }
    }

    final timeLabel = _formatMinutes(startMinutes);
    final repLabel = _pendingRepeatType;
    _resetDraft();

    return OfflineAiReply(
      text: '✅ टास्क सेव हो गया!\n'
          '• नाम: $title\n'
          '• समय: ${_dateLabel(date)} $timeLabel | रिपीट: $repLabel\n'
          '• कैटेगरी: $category | प्रायोरिटी: ${_priorityLabel(pri)}\n'
          '🔥 बहुत बढ़िया प्लानिंग—अब बस इसे पूरा कर दिखाओ!',
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
    final now = _nowIst();
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
    if (_matchesAny(lower, ['अभी', 'now', 'इसी वक्त'])) {
      final ist = _nowIst();
      return ist.hour * 60 + ist.minute;
    }

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
    if (_matchesAny(lower, ['family', 'परिवार', 'मम्मी', 'पापा'])) {
      return 'Family';
    }
    if (_matchesAny(lower, ['learning', 'सीखना', 'कोर्स'])) {
      return 'Learning';
    }
    return 'Personal';
  }

  String _extractCleanTaskTitle(String input) {
    var cleaned = input
        .replaceAll(RegExp(r'(?:subtasks?|checklist|सबटास्क|चेकलिस्ट)\s*[:\-].*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d{1,2}(?::\d{2})?\s*(?:बजे|baje)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b'), '');

    return _cleanKeywords(cleaned, [
      'add', 'create', 'remind', 'me', 'to', 'reminder', 'schedule', 'task', 'routine',
      'daily', 'everyday', 'every', 'day', 'today', 'tomorrow', 'at', 'for', 'a', 'an', 'the',
      'new', 'one', 'please', 'pls', 'set', 'make', 'my', 'name', 'time', 'is', 'edit', 'update',
      'delete', 'remove', 'complete', 'done', 'finish', 'change', 'skip',
      'priority', 'low', 'normal', 'high', 'critical', 'repeat', 'alternate', 'weekdays', 'weekends', 'spaced',
      'जोड़ो', 'जोड़', 'बनाओ', 'बना', 'लगाओ', 'लगा', 'करो', 'करना', 'कर', 'दो', 'देना', 'चाहिए',
      'क्रिएट', 'एडिट', 'बदलो', 'डिलीट', 'हटाओ', 'पूरा', 'हो', 'गया', 'स्किप',
      'टास्क', 'रूटीन', 'रिमाइंडर', 'अलार्म', 'नया', 'एक', 'वाला', 'मेरा', 'नाम', 'टाइम', 'समय',
      'प्रायोरिटी', 'क्रिटिकल', 'हाई', 'सामान्य', 'कम', 'रिपीट', 'रोज', 'रोज़', 'हर', 'दिन',
      'आज', 'कल', 'परसों', 'अभी', 'सुबह', 'शाम', 'रात', 'दोपहर',
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
    final now = _nowIst();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'आज';
    if (diff == 1) return 'कल';
    if (diff == 2) return 'परसों';
    return DateFormat('dd MMM').format(date);
  }
}
