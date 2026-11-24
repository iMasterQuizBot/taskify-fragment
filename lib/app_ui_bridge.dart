import 'package:flutter/foundation.dart';

/// ग्लोबल UI व AI ब्रिज:
/// 1) किसी भी AI (Offline AI, API AI, Live Voice AI, Floating Bubble) से ऐप की स्क्रीन/टाइमर/डायलॉग कंट्रोल करने के लिए
/// 2) बैक दबाने पर Floating AI Voice Bubble को पूरे ऐप के ऊपर दिखाने/छुपाने के लिए
class AppUiBridge {
  AppUiBridge._();
  static final AppUiBridge instance = AppUiBridge._();

  final ValueNotifier<bool> bubbleVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> bubbleIsApiMode = ValueNotifier<bool>(false);

  Future<String> Function(String action, Map<String, dynamic> params)? onAction;

  void showBubble({required bool isApi}) {
    bubbleIsApiMode.value = isApi;
    bubbleVisible.value = true;
  }

  void hideBubble() {
    bubbleVisible.value = false;
  }

  Future<String> trigger(String action, [Map<String, dynamic> params = const {}]) async {
    final handler = onAction;
    if (handler == null) return 'UI ready नहीं है।';
    return await handler(action, params);
  }
}
