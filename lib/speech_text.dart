import 'package:flutter/material.dart';

/// AI के जवाब को दो तरह से साफ़ करता है:
/// 1) forDisplay: LaTeX ($...$, \gamma, ^3 आदि) को सुंदर Unicode में बदलकर स्क्रीन पर दिखाने के लिए।
/// 2) forSpeech: बोलते समय चिन्ह (*, #, $, \ आदि) हटाकर, इंसान की तरह पढ़ने के लिए।
class SpeechText {
  static const Map<String, String> _commands = {
    r'\gamma': 'γ', r'\rho': 'ρ', r'\phi': 'φ', r'\sigma': 'σ', r'\mu': 'μ',
    r'\theta': 'θ', r'\pi': 'π', r'\Delta': 'Δ', r'\alpha': 'α', r'\beta': 'β',
    r'\omega': 'ω', r'\lambda': 'λ', r'\eta': 'η', r'\epsilon': 'ε',
    r'\approx': '≈', r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±',
    r'\leq': '≤', r'\geq': '≥', r'\neq': '≠', r'\rightarrow': '→', r'\to': '→',
    r'\%': '%', r'\,': ' ', r'\ ': ' ', r'\left': '', r'\right': '',
  };

  static const Map<String, String> _sup = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '-': '⁻', '+': '⁺',
  };

  static const Map<String, String> _sub = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  };

  static String _script(String text, Map<String, String> map) {
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      final mapped = map[ch];
      if (mapped == null) return text; // पूरी तरह बदल न सके तो वैसा ही रखें
      buf.write(mapped);
    }
    return buf.toString();
  }

  /// एक math टुकड़े को Unicode बनाएँ
  static String _mathToUnicode(String m) {
    var s = m;
    s = s.replaceAllMapped(RegExp(r'\\text\{([^}]*)\}'), (x) => x.group(1)!);
    s = s.replaceAllMapped(RegExp(r'\\frac\{([^}]*)\}\{([^}]*)\}'), (x) => '(${x.group(1)})/(${x.group(2)})');
    s = s.replaceAllMapped(RegExp(r'\\sqrt\{([^}]*)\}'), (x) => '√(${x.group(1)})');
    _commands.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAllMapped(RegExp(r'\^\{([^}]*)\}'), (x) {
      final t = _script(x.group(1)!, _sup);
      return t == x.group(1)! ? '^(${x.group(1)})' : t;
    });
    s = s.replaceAllMapped(RegExp(r'\^(\d)'), (x) => _sup[x.group(1)!] ?? '^${x.group(1)}');
    s = s.replaceAllMapped(RegExp(r'_\{([^}]*)\}'), (x) {
      final t = _script(x.group(1)!, _sub);
      return t == x.group(1)! ? '_(${x.group(1)})' : t;
    });
    s = s.replaceAllMapped(RegExp(r'_(\d)'), (x) => _sub[x.group(1)!] ?? '_${x.group(1)}');
    s = s.replaceAll('{', '').replaceAll('}', '');
    return s.trim();
  }

  static String forDisplay(String raw) {
    var s = raw.replaceAll('\r', '');
    // $$...$$ और $...$ के अंदर का math
    s = s.replaceAllMapped(RegExp(r'\$\$([\s\S]+?)\$\$'), (m) => _mathToUnicode(m.group(1)!));
    s = s.replaceAllMapped(RegExp(r'\$([^$\n]+?)\$'), (m) => _mathToUnicode(m.group(1)!));
    // बाकी बचे LaTeX commands
    if (s.contains('\\')) s = _mathToUnicode(s);
    // Markdown headings को बोल्ड लाइन बनाएँ, bullets को • करें
    final lines = s.split('\n').map((l) {
      var t = l;
      if (RegExp(r'^\s*#{1,6}\s').hasMatch(t)) t = '**${t.replaceFirst(RegExp(r'^\s*#{1,6}\s'), '')}**';
      t = t.replaceFirstMapped(RegExp(r'^(\s*)[\*\-]\s+'), (m) => '${m.group(1)}• ');
      return t.trimRight();
    }).toList();
    // लगातार खाली लाइनें एक तक
    final out = <String>[];
    for (final l in lines) {
      if (l.isEmpty && out.isNotEmpty && out.last.isEmpty) continue;
      out.add(l);
    }
    return out.join('\n').trim();
  }

  static String forSpeech(String raw) {
    var s = forDisplay(raw);
    const Map<String, String> words = {
      '%': ' प्रतिशत ',
      '=': ' बराबर ',
      '×': ' गुणा ',
      '·': ' गुणा ',
      '÷': ' भाग ',
      '/': ' बटा ',
      '+': ' जोड़ ',
      '≈': ' लगभग ',
      '≤': ' कम या बराबर ',
      '≥': ' ज़्यादा या बराबर ',
      '→': ' ',
      '²': ' वर्ग ',
      '³': ' घन ',
      '√': ' वर्गमूल ',
      'γ': ' गामा ',
      'ρ': ' रो ',
      'φ': ' फ़ाई ',
      'σ': ' सिग्मा ',
      'μ': ' म्यू ',
      'θ': ' थीटा ',
      'π': ' पाई ',
      'Δ': ' डेल्टा ',
      'α': ' अल्फ़ा ',
      'β': ' बीटा ',
      'ω': ' ओमेगा ',
      'λ': ' लैम्डा ',
    };
    words.forEach((k, v) => s = s.replaceAll(k, v));
    // सिर्फ़ अक्षर, अंक, स्पेस और वाक्य-विराम रखें (बाकी चिन्ह हटें)
    s = s.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s.,?!।:;\-]', unicode: true), ' ');
    s = s.replaceAll(RegExp(r'(?<=\d)-(?=\d)'), ' से ');
    s = s.replaceAll(RegExp(r'\s*-\s*'), ' ');
    s = s.replaceAll(RegExp(r'\s+([.,?!।:;])'), r'$1');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n');
    return s.trim();
  }
}

/// स्क्रीन पर साफ़ जवाब: **bold**, • बुलेट, खाली लाइनें।
class SolutionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const SolutionText(this.text, {super.key, this.style});

  List<TextSpan> _spans(String line, TextStyle base) {
    final spans = <TextSpan>[];
    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w800) : base,
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style.copyWith(height: 1.5, fontSize: 15);
    final lines = SpeechText.forDisplay(text).split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          if (l.trim().isEmpty)
            const SizedBox(height: 6)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(TextSpan(children: _spans(l, base))),
            ),
      ],
    );
  }
}
