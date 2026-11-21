import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'sound_service.dart';

/// पूरे ऐप में कहीं भी टैप करने पर क्लिक साउंड + हैप्टिक।
/// स्क्रॉल या लंबा प्रेस इसमें नहीं गिना जाता, सिर्फ़ छोटा टैप।
class TapFeedbackLayer extends StatefulWidget {
  final Widget child;
  const TapFeedbackLayer({super.key, required this.child});

  @override
  State<TapFeedbackLayer> createState() => _TapFeedbackLayerState();
}

class _TapFeedbackLayerState extends State<TapFeedbackLayer> {
  int? _pointer;
  Offset _downPos = Offset.zero;
  Duration _downTime = Duration.zero;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _downPos = e.position;
        _downTime = e.timeStamp;
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        final moved = (e.position - _downPos).distance;
        final held = e.timeStamp - _downTime;
        if (moved < 20 && held.inMilliseconds < 500) {
          SoundService.onTap();
        }
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _pointer = null;
      },
      child: widget.child,
    );
  }
}
