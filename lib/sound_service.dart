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
  SoundSlot('taskCreated', 'टास्क बनाने पर', 'builtin:beep'),
  SoundSlot('taskCompleted', 'टास्क पूरा होने पर', 'builtin:chime'),
  SoundSlot('allCompleted', 'सभी टास्क पूरे होने पर', 'builtin:bell'),
  SoundSlot('reminder', 'नोटिफिकेशन (पहले से सूचना)', 'builtin:chime'),
  SoundSlot('alarm', 'अलार्म (टास्क के समय पर)', 'builtin:alarm'),
];

const Map<String, String> builtinLabels = {
  'default': 'System Default',
  'chime': 'Chime',
  'bell': 'Bell',
  'beep': 'Beep',
  'alarm': 'Alarm',
};

class SoundService {
  static AppDatabase? db;
  static final AudioPlayer _player = AudioPlayer();
  static const MethodChannel _channel = MethodChannel('taskify/sound');

  static const Map<String, String> _assets = {
    'chime': 'sounds/sound_chime.wav',
    'bell': 'sounds/sound_bell.wav',
    'beep': 'sounds/sound_beep.wav',
    'alarm': 'sounds/sound_alarm.wav',
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

  /// किसी भी इवेंट पर साउंड बजाना (ऐप के अंदर)। गलती हो तो चुपचाप छोड़ दें।
  static Future<void> play(String slotId) async {
    try {
      await playSource(await getSource(slotId));
    } catch (_) {}
  }

  static Future<void> playSource(String source) async {
    await _player.stop();
    if (source.startsWith('file:')) {
      final path = source.substring(5);
      if (!File(path).existsSync()) return;
      await _player.play(DeviceFileSource(path));
    } else if (source.startsWith('builtin:')) {
      final asset = _assets[source.substring(8)];
      if (asset != null) await _player.play(AssetSource(asset));
    }
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
      allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg', 'aac', 'flac'],
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
      return builtinLabels[source.substring(8)] ?? 'Built-in';
    }
    if (source.startsWith('file:')) {
      final name = source.substring(5).split('/').last;
      return 'फ़ाइल: $name';
    }
    return 'System Default';
  }
}
