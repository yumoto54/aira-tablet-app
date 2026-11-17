import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'voice_pack.dart';

enum VoicePackSyncResult {
  /// 端末の音声パックはすでに最新だった。
  upToDate,

  /// 新しい音声を受け取って、置き換えた。
  updated,

  /// サーバーに音声パックが無い・通信できない・目録が壊れている。何も変えない。
  unavailable,

  /// 一部のクリップが取れなかった。目録は書き換えない(次回やり直す)。
  partial,
}

/// サーバー(/api/voicepack/...)から最新の音声パックを受け取って、端末の保存領域に置く。
///
/// - 目録の版(generatedAt)が端末のものと同じで、クリップも揃っていれば何もしない。
/// - 足りないクリップだけを取る。全部取れたときだけ目録を書き換える(途中の状態を使わない)。
/// - 目録に載らなくなった古いクリップは消す。
/// - どの段階で失敗しても例外は出さない(会話を止めない)。
class VoicePackSync {
  VoicePackSync({
    required this.dir,
    required this.baseUrl,
    this.headers = const {},
    http.Client? client,
    this.manifestTimeout = const Duration(seconds: 10),
    this.clipTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Directory dir;
  final String baseUrl;
  final Map<String, String> headers;
  final Duration manifestTimeout;
  final Duration clipTimeout;
  final http.Client _client;

  static final RegExp _clipId = RegExp(r'^[a-f0-9]{16}$');
  static final RegExp _clipFileName = RegExp(r'^[a-f0-9]{16}\.(mp3|json)$');

  Future<VoicePackSyncResult> sync() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/voicepack/manifest'), headers: headers)
          .timeout(manifestTimeout);
      if (res.statusCode != 200) return VoicePackSyncResult.unavailable;

      final manifestText = utf8.decode(res.bodyBytes);
      final json = jsonDecode(manifestText) as Map<String, dynamic>;
      final generatedAt = json['generatedAt'];
      final clips = parseVoicePackClips(json['clips']);
      final ids = <String>{for (final m in clips.values) ...m.values};
      // 目録の値は端末のファイル名になる。想定外の形があれば、目録ごと信用しない。
      if (generatedAt is! String || ids.any((id) => !_clipId.hasMatch(id))) {
        return VoicePackSyncResult.unavailable;
      }

      await dir.create(recursive: true);

      final manifestFile = File('${dir.path}/manifest.json');
      var sameVersion = false;
      if (await manifestFile.exists()) {
        try {
          final local = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
          sameVersion = local['generatedAt'] == generatedAt;
        } catch (_) {
          sameVersion = false;
        }
      }

      var failed = 0;
      var downloaded = 0;
      for (final id in ids) {
        if (await _hasClip(id)) continue;
        if (await _fetchClip(id)) {
          downloaded++;
        } else {
          failed++;
        }
      }
      if (failed > 0) return VoicePackSyncResult.partial;
      if (sameVersion && downloaded == 0) return VoicePackSyncResult.upToDate;

      await _writeAtomic(manifestFile, utf8.encode(manifestText));
      await _deleteStale(ids);
      return VoicePackSyncResult.updated;
    } catch (_) {
      return VoicePackSyncResult.unavailable;
    }
  }

  Future<bool> _hasClip(String id) async {
    final mp3 = File('${dir.path}/$id.mp3');
    final cues = File('${dir.path}/$id.json');
    return await mp3.exists() && await cues.exists() && await mp3.length() > 0;
  }

  Future<bool> _fetchClip(String id) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/voicepack/clip/$id'), headers: headers)
          .timeout(clipTimeout);
      if (res.statusCode != 200) return false;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final audio = base64Decode(body['audioBase64'] as String);
      final cues = body['mouthCues'];
      if (audio.isEmpty || cues is! List) return false;
      await _writeAtomic(File('${dir.path}/$id.mp3'), audio);
      await _writeAtomic(File('${dir.path}/$id.json'), utf8.encode(jsonEncode(cues)));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 書きかけのファイルを使わないように、別名で書いてから置き換える。
  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  Future<void> _deleteStale(Set<String> keepIds) async {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!_clipFileName.hasMatch(name)) continue;
      if (keepIds.contains(name.substring(0, 16))) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }
}
