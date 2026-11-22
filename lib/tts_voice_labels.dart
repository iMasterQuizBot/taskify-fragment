/// फ़ोन के TTS engine से मिलने वाली raw आवाज़ें बहुत उलझी हुई दिखती हैं, जैसे:
///   "te-IN-language (te-IN)"  या  "ar-xa-x-arc-network (ar)"
/// इससे पहले यूज़र ने कोई आवाज़ चुनी तो असल में दूसरी भाषा चुन बैठा, क्योंकि कोड
/// पढ़ पाना मुश्किल था।
///
/// यह फ़ाइल हर raw locale/नाम को एक साफ़, सीधा label बना देती है:
///   "🇮🇳 भारत · तेलुगु  ·  ऑफ़लाइन (फ़ोन में पहले से है)"
///   "🌍 Arabic (सामान्य)  ·  ऑनलाइन (डाउनलोड ज़रूरी हो सकता है)"
/// ताकि देश + भाषा + "यह आवाज़ ऑफ़लाइन है या नेट/डाउनलोड चाहिए" — तीनों एक नज़र में दिखें।
class TtsVoiceLabels {
  // locale का भाषा-भाग (जैसे "te", "hi", "en") -> पढ़ने लायक नाम
  static const Map<String, String> _lang = {
    'hi': 'हिंदी', 'en': 'अंग्रेज़ी (English)', 'bn': 'बंगाली', 'te': 'तेलुगु',
    'ta': 'तमिल', 'mr': 'मराठी', 'gu': 'गुजराती', 'kn': 'कन्नड़', 'ml': 'मलयालम',
    'pa': 'पंजाबी', 'ur': 'उर्दू', 'or': 'ओड़िया', 'as': 'असमिया',
    'ar': 'अरबी (Arabic)', 'bg': 'बल्गेरियाई', 'zh': 'चीनी (Chinese)',
    'ja': 'जापानी', 'ko': 'कोरियाई', 'fr': 'फ़्रेंच', 'de': 'जर्मन',
    'es': 'स्पैनिश', 'pt': 'पुर्तगाली', 'ru': 'रूसी', 'it': 'इतालवी',
    'th': 'थाई', 'vi': 'वियतनामी', 'id': 'इंडोनेशियाई', 'tr': 'तुर्की',
    'nl': 'डच', 'pl': 'पोलिश', 'uk': 'यूक्रेनी', 'ro': 'रोमानियाई',
    'el': 'ग्रीक', 'he': 'हिब्रू', 'fa': 'फ़ारसी', 'sw': 'स्वाहिली',
    'fil': 'फ़िलिपीनो', 'ms': 'मलय', 'cs': 'चेक', 'sk': 'स्लोवाक',
    'hu': 'हंगेरियन', 'fi': 'फ़िनिश', 'sv': 'स्वीडिश', 'nb': 'नॉर्वेजियन',
    'da': 'डैनिश', 'km': 'खमेर', 'my': 'बर्मीज़', 'ne': 'नेपाली', 'si': 'सिंहली',
  };

  // locale का देश-भाग (जैसे "IN", "US") -> झंडा + नाम
  static const Map<String, String> _country = {
    'IN': '🇮🇳 भारत', 'US': '🇺🇸 US', 'GB': '🇬🇧 UK', 'AU': '🇦🇺 Australia',
    'CA': '🇨🇦 Canada', 'PK': '🇵🇰 Pakistan', 'BD': '🇧🇩 Bangladesh',
    'LK': '🇱🇰 Sri Lanka', 'NP': '🇳🇵 Nepal', 'FR': '🇫🇷 France', 'DE': '🇩🇪 Germany',
    'ES': '🇪🇸 Spain', 'BR': '🇧🇷 Brazil', 'PT': '🇵🇹 Portugal', 'RU': '🇷🇺 Russia',
    'CN': '🇨🇳 China', 'JP': '🇯🇵 Japan', 'KR': '🇰🇷 Korea', 'SA': '🇸🇦 Saudi Arabia',
    'AE': '🇦🇪 UAE', 'EG': '🇪🇬 Egypt', 'XA': '🌍 सामान्य (कोई देश तय नहीं)',
  };

  /// raw locale (जैसे "te-IN", "ar-xa-x-arc-network", "hi_IN") से
  /// {language, country, engineNote} निकालता है।
  static ({String language, String country, String engineNote}) parse(String rawLocale, String rawName) {
    final cleaned = rawLocale.replaceAll('_', '-');
    final parts = cleaned.split('-');
    final langCode = parts.isNotEmpty ? parts[0].toLowerCase() : '';
    final countryCode = parts.length > 1 ? parts[1].toUpperCase() : '';

    final language = _lang[langCode] ?? (langCode.isEmpty ? 'अज्ञात भाषा' : langCode.toUpperCase());
    final country = _country[countryCode] ?? (countryCode.isEmpty ? '' : '🌐 $countryCode');

    // नाम/locale में "-network" = ऑनलाइन/डाउनलोड-निर्भर आवाज़, "-local" = फ़ोन में
    // पहले से मौजूद ऑफ़लाइन आवाज़। यही असली वजह थी कि यूज़र को सही भाषा चुनने के
    // बावजूद "गलत" जैसा अनुभव हुआ — आवाज़ असल में डाउनलोड नहीं हुई थी।
    final lower = '$rawLocale $rawName'.toLowerCase();
    String engineNote;
    if (lower.contains('network')) {
      engineNote = '🌐 ऑनलाइन (डाउनलोड/इंटरनेट ज़रूरी हो सकता है)';
    } else if (lower.contains('local')) {
      engineNote = '📴 ऑफ़लाइन (फ़ोन में पहले से मौजूद)';
    } else {
      engineNote = '📴 ऑफ़लाइन';
    }

    return (language: language, country: country, engineNote: engineNote);
  }

  /// पूरा, एक-लाइन, दिखाने लायक label।
  static String simpleLabel(String rawLocale, String rawName) {
    final p = parse(rawLocale, rawName);
    final place = p.country.isNotEmpty ? '${p.country} · ' : '';
    return '$place${p.language}  •  ${p.engineNote}';
  }
}
