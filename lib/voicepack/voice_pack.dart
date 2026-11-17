import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// 同梱の音声パックから取り出した1本分。
class VoicePackClip {
  VoicePackClip({required this.audioBytes, required this.mouthCuesJson});

  /// MP3の音声データ。
  final Uint8List audioBytes;

  /// 口パクの指示。/api/speak の mouthCues と同じ形(mouthShape / fileName / audioOffsetMs)。
  final List<dynamic> mouthCuesJson;
}

/// タブレットに同梱した「事前生成の音声」の置き場。
///
/// FAQの回答やアプリの定型文は文面が決まっているので、あらかじめ音声と口パクの
/// 指示を作って assets/voicepack/ に入れておく(作り方は backend の
/// scripts/build-voice-pack.js)。読み上げる文がここにあれば、/api/speak を
/// 呼ばずにすぐ再生できる。無ければ null を返し、呼び出し側が従来どおりサーバーで作る。
///
/// 文は一文字でも違えば見つからない(=サーバーに任せる)。誤って別の文の音声を
/// 読み上げることはない。
class VoicePack {
  VoicePack({
    Future<String> Function(String path)? loadString,
    Future<ByteData> Function(String path)? loadBytes,
    this.assetDir = 'assets/voicepack',
  })  : _loadString = loadString ?? rootBundle.loadString,
        _loadBytes = loadBytes ?? rootBundle.load;

  static final VoicePack instance = VoicePack();

  final Future<String> Function(String path) _loadString;
  final Future<ByteData> Function(String path) _loadBytes;
  final String assetDir;

  Map<String, Map<String, String>> _clips = const {};
  Future<void>? _loading;

  /// 同梱の音声が何本あるか(読み込み前は 0)。
  int get clipCount => _clips.values.fold(0, (sum, m) => sum + m.length);

  /// 目録(manifest.json)を読む。何度呼んでも読み込みは1回。失敗しても例外は出さず、空のパックとして扱う。
  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final raw = await _loadString('$assetDir/manifest.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final clips = json['clips'];
      final parsed = <String, Map<String, String>>{};
      if (clips is Map<String, dynamic>) {
        clips.forEach((locale, value) {
          if (value is Map<String, dynamic>) {
            parsed[locale] = {
              for (final e in value.entries)
                if (e.value is String) e.key: e.value as String,
            };
          }
        });
      }
      _clips = parsed;
    } catch (_) {
      _clips = const {};
    }
  }

  /// [locale](例: en-US)で[text]を読み上げる音声が同梱されていれば返す。無い・読めないときは null。
  Future<VoicePackClip?> lookup(String locale, String text) async {
    await load();
    final byLocale = _clips[locale];
    if (byLocale == null) return null;
    final id = byLocale[text] ?? byLocale[text.trim()];
    if (id == null) return null;
    try {
      final audio = await _loadBytes('$assetDir/$id.mp3');
      final cues = jsonDecode(await _loadString('$assetDir/$id.json')) as List<dynamic>;
      return VoicePackClip(
        audioBytes: audio.buffer.asUint8List(audio.offsetInBytes, audio.lengthInBytes),
        mouthCuesJson: cues,
      );
    } catch (_) {
      return null;
    }
  }
}
