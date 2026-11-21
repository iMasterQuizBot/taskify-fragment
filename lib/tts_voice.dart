import 'package:flutter_tts/flutter_tts.dart';

import 'app_database.dart';
import 'speech_text.dart';

/// AI की बोलने वाली आवाज़ (फ़ोन की TTS) सेट करना।
/// यूज़र ने आवाज़ न चुनी हो तो डिफ़ॉल्ट वैसे ही चलेगा।
class TtsVoice {
  static Future<void> apply(FlutterTts tts, AppDatabase db) async {
    final rateStr = await db.getSetting('ttsRate');
    final rate = double.tryParse(rateStr ?? '') ?? 0.5;
    await tts.setSpeechRate(rate);
    await tts.setLanguage('hi-IN');
    final name = await db.getSetting('ttsVoiceName');
    final locale = await db.getSetting('ttsVoiceLocale');
    if (name != null && name.isNotEmpty && locale != null && locale.isNotEmpty) {
      await tts.setVoice({'name': name, 'locale': locale});
    }
  }

  static Future<List<Map<String, String>>> available(FlutterTts tts) async {
    final raw = await tts.getVoices;
    if (raw is! List) return [];
    final out = <Map<String, String>>[];
    for (final v in raw) {
      if (v is Map) {
        out.add({
          'name': v['name']?.toString() ?? '',
          'locale': v['locale']?.toString() ?? '',
        });
      }
    }
    out.sort((a, b) => a['name']!.compareTo(b['name']!));
    return out;
  }

  /// बोलने से पहले चिन्ह हटाकर पढ़ने लायक text
  static String cleanForSpeech(String raw) => SpeechText.forSpeech(raw);
}
