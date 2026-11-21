import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// एक साउंड स्लॉट = एक इवेंट (टास्क बनाना, टास्क पूरा, सब पूरे, नोटिफिकेशन, अलार्म)।
class SoundSlot {
  final String id;
  final String label;
  final String fallback; // 'builtin:<key>' या 'file:<path>'
  const SoundSlot(this.id, this.label, this.fallback);
}

const List<SoundSlot> soundSlots = [
  SoundSlot('taskCreated', 'टास्क बनाने पर', 'builtin:sound_beep'),
  SoundSlot('taskCompleted', 'टास्क पूरा होने पर', 'builtin:sound_chime'),
  SoundSlot('allCompleted', 'सभी टास्क पूरे होने पर', 'builtin:sound_bell'),
  SoundSlot('reminder', 'नोटिफिकेशन (पहले से सूचना)', 'builtin:sound_chime'),
  SoundSlot('alarm', 'अलार्म (टास्क के समय पर)', 'builtin:sound_alarm'),
];

class SoundService {
  static AppDatabase? db;

  // ---- प्लेयर ----
  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _clickPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  static const MethodChannel _channel = MethodChannel('taskify/sound');

  // ---- assets/sounds/ फ़ोल्डर की सारी फ़ाइलें अपने आप यहाँ आती हैं ----
  static const String _soundsDir = 'assets/sounds/';
  static const String _clickKey = 'sound_click'; // सिर्फ़ टैप-क्लिक के लिए, लिस्ट में नहीं दिखेगा
  static const Set<String> _audioExt = {
    'wav', 'mp3', 'ogg', 'm4a', 'aac', 'flac', 'mp4', 'webm', 'opus',
  };

  static final Map<String, String> _assetByKey = {}; // key -> 'sounds/xyz.mp3'
  static final Map<String, String> _labelByKey = {}; // key -> दिखने वाला नाम
  static String _clickAsset = 'sounds/sound_click.wav';

  // ---- टैप फ़ीडबैक की सेटिंग (मेमोरी में, ताकि हर टैप पर DB न पढ़ना पड़े) ----
  static bool tapSoundOn = true;
  static bool hapticOn = true;

  /// ऐप शुरू होते समय एक बार बुलाएँ।
  static Future<void> init(AppDatabase database) async {
    db = database;
    await _loadCatalog();
    try {
      tapSoundOn = (await db?.getSetting('tapSoundEnabled')) != '0';
      hapticOn = (await db?.getSetting('tapHapticEnabled')) != '0';
    } catch (_) {}
    try {
      final ctx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();
      await _player.setAudioContext(ctx);
      await _clickPlayer.setAudioContext(ctx);
    } catch (_) {}
  }

  /// फ़ाइल के नाम से रिसोर्स-key (Android res/raw के नियम: a-z, 0-9, _)।
  /// build.yml वाली Python स्क्रिप्ट में भी बिल्कुल यही नियम है।
  static String _keyFor(String stem) {
    final k = stem.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (k.isEmpty || RegExp(r'^[0-9]').hasMatch(k)) return 's_$k';
    return k;
  }

  static String _prettyLabel(String stem) {
    var t = stem.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (t.toLowerCase().startsWith('sound ')) t = t.substring(6).trim();
    if (t.isEmpty) return stem;
    return t
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static Future<void> _loadCatalog() async {
    _assetByKey.clear();
    _labelByKey.clear();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest.listAssets().where((p) => p.startsWith(_soundsDir)).toList()..sort();
      for (final path in paths) {
        final name = path.substring(_soundsDir.length);
        if (name.contains('/')) continue; // सब-फ़ोल्डर छोड़ दें
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        final ext = name.substring(dot + 1).toLowerCase();
        if (!_audioExt.contains(ext)) continue;
        final stem = name.substring(0, dot);
        final key = _keyFor(stem);
        final asset = path.substring('assets/'.length); // AssetSource के लिए
        if (key == _clickKey) {
          _clickAsset = asset;
          continue;
        }
        if (_assetByKey.containsKey(key)) continue; // एक ही नाम की दूसरी फ़ाइल छोड़ दें
        _assetByKey[key] = asset;
        _labelByKey[key] = _prettyLabel(stem);
      }
    } catch (_) {}

    if (_assetByKey.isEmpty) {
      // सुरक्षा: अगर लिस्ट न मिले तो कम से कम ये 4 चलें
      const defaults = {
        'sound_chime': 'Chime',
        'sound_bell': 'Bell',
        'sound_beep': 'Beep',
        'sound_alarm': 'Alarm',
      };
      defaults.forEach((k, v) {
        _assetByKey[k] = 'sounds/$k.wav';
        _labelByKey[k] = v;
      });
    }
  }

  /// पुरानी सेव की हुई key ('chime') और नई key ('sound_chime'), दोनों पहचानता है।
  static String? _resolveKey(String key) {
    if (_assetByKey.containsKey(key)) return key;
    if (_assetByKey.containsKey('sound_$key')) return 'sound_$key';
    return null;
  }

  /// नोटिफिकेशन के लिए res/raw का नाम (या null = सिस्टम डिफ़ॉल्ट)।
  static String? rawResourceFor(String key) => _resolveKey(key);

  /// चुनने वाली लिस्ट: System Default + assets/sounds/ की सारी फ़ाइलें।
  static Map<String, String> get builtinLabels => {
        'default': 'System Default',
        ..._labelByKey,
      };

  static SoundSlot slotById(String id) => soundSlots.firstWhere((s) => s.id == id);

  static Future<String> getSource(String slotId) async {
    final v = await db?.getSetting('sound_$slotId');
    if (v == null || v.isEmpty) return slotById(slotId).fallback;
    return v;
  }

  static Future<void> setSource(String slotId, String source) async {
    final old = await getSource(slotId);
    await db?.setSetting('sound_$slotId', source);
    // पुरानी कॉपी की फ़ाइल हटाएँ (सिर्फ़ ऐप के अपने sounds फ़ोल्डर की)
    if (old.startsWith('file:') && old != source) {
      try {
        await File(old.substring(5)).delete();
      } catch (_) {}
    }
  }

  // ---- टैप: क्लिक साउंड + हैप्टिक ----
  static void onTap() {
    if (hapticOn) {
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }
    if (tapSoundOn) _playClick();
  }

  static Future<void> _playClick() async {
    try {
      await _clickPlayer.play(AssetSource(_clickAsset));
    } catch (_) {}
  }

  static Future<void> setTapSound(bool v) async {
    tapSoundOn = v;
    await db?.setSetting('tapSoundEnabled', v ? '1' : '0');
  }

  static Future<void> setHaptic(bool v) async {
    hapticOn = v;
    await db?.setSetting('tapHapticEnabled', v ? '1' : '0');
  }

  // ---- इवेंट साउंड ----
  /// किसी भी इवेंट पर साउंड + हल्का हैप्टिक। गलती हो तो चुपचाप छोड़ दें।
  static Future<void> play(String slotId) async {
    if (hapticOn) {
      try {
        if (slotId == 'allCompleted') {
          HapticFeedback.heavyImpact();
        } else if (slotId == 'taskCompleted') {
          HapticFeedback.mediumImpact();
        } else if (slotId == 'taskCreated') {
          HapticFeedback.lightImpact();
        }
      } catch (_) {}
    }
    try {
      await playSource(await getSource(slotId));
    } catch (_) {}
  }

  static Future<void> playSource(String source) async {
    try {
      await _player.stop();
      if (source.startsWith('file:')) {
        final path = source.substring(5);
        if (!File(path).existsSync()) return;
        await _player.play(DeviceFileSource(path));
      } else if (source.startsWith('builtin:')) {
        final key = _resolveKey(source.substring(8));
        if (key == null) return; // 'default' = सिस्टम साउंड, ऐप के अंदर कुछ नहीं बजता
        await _player.play(AssetSource(_assetByKey[key]!));
      }
    } catch (_) {}
  }

  static Future<void> stopPreview() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  static Future<String> _storeDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/sounds');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// फ़ोन से आपकी अपनी म्यूज़िक/साउंड फ़ाइल चुनकर ऐप के अंदर कॉपी करता है।
  /// लौटाता है 'file:<path>' या null (अगर कुछ नहीं चुना)।
  static Future<String?> pickAndStoreFile(String slotId) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg', 'aac', 'flac', 'mp4', 'webm', 'opus'],
      withData: false,
    );
    final picked = res?.files.single.path;
    if (picked == null) return null;

    final dir = await _storeDir();
    final dot = picked.lastIndexOf('.');
    final ext = dot == -1 ? '.audio' : picked.substring(dot);
    final dest = '$dir/${slotId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(picked).copy(dest);
    return 'file:$dest';
  }

  /// Notification के लिए: फ़ाइल का content:// URI (Android में FileProvider से)
  static Future<String?> contentUriFor(String path) async {
    try {
      return await _channel.invokeMethod<String>('contentUri', {'path': path});
    } catch (_) {
      return null;
    }
  }

  static String labelFor(String source) {
    if (source.startsWith('builtin:')) {
      final raw = source.substring(8);
      if (raw == 'default') return 'System Default';
      final key = _resolveKey(raw);
      return (key != null ? _labelByKey[key] : null) ?? 'Built-in';
    }
    if (source.startsWith('file:')) {
      final name = source.substring(5).split('/').last;
      return 'फ़ाइल: $name';
    }
    return 'System Default';
  }
}
