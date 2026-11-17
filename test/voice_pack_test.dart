import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aira_tablet_app/voicepack/voice_pack.dart';

void main() {
  const manifest = '''
{"version":1,"volumePercent":120,"clips":{
  "en-US":{"Hello there.":"aaa111"},
  "ja-JP":{"こんにちは。":"bbb222"}
}}''';
  const cues = '[{"mouthShape":"a","fileName":"a.png","audioOffsetMs":0},'
      '{"mouthShape":"neutral","fileName":"n.png","audioOffsetMs":300}]';

  VoicePack build({bool withFiles = true, String manifestText = manifest}) {
    return VoicePack(
      loadString: (path) async {
        if (path.endsWith('manifest.json')) return manifestText;
        if (withFiles && path.endsWith('aaa111.json')) return cues;
        throw Exception('not found: $path');
      },
      loadBytes: (path) async {
        if (withFiles && path.endsWith('aaa111.mp3')) {
          return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
        }
        throw Exception('not found: $path');
      },
    );
  }

  group('VoicePack', () {
    test('同梱されている文は、音声と口パクを返す', () async {
      final pack = build();
      final clip = await pack.lookup('en-US', 'Hello there.');
      expect(clip, isNotNull);
      expect(clip!.audioBytes, [1, 2, 3]);
      expect(clip.mouthCuesJson.length, 2);
      expect(
        (clip.mouthCuesJson.last as Map)['audioOffsetMs'],
        300,
      );
    });

    test('前後の空白だけの違いは同じ文として扱う', () async {
      final pack = build();
      expect(await pack.lookup('en-US', '  Hello there.\n'), isNotNull);
    });

    test('一文字でも違う文や、別の言語は見つからない(サーバーに任せる)', () async {
      final pack = build();
      expect(await pack.lookup('en-US', 'Hello there'), isNull);
      expect(await pack.lookup('es-US', 'Hello there.'), isNull);
      expect(await pack.lookup('ja-JP', 'Hello there.'), isNull);
    });

    test('ファイルが欠けていても例外にせず null を返す', () async {
      final pack = build(withFiles: false);
      expect(await pack.lookup('en-US', 'Hello there.'), isNull);
    });

    test('目録が壊れていても空のパックとして動く', () async {
      final pack = build(manifestText: 'not json');
      expect(await pack.lookup('en-US', 'Hello there.'), isNull);
      expect(pack.clipCount, 0);
    });

    test('件数が数えられる', () async {
      final pack = build();
      await pack.load();
      expect(pack.clipCount, 2);
      expect(jsonDecode(manifest), isA<Map>());
    });
  });
}
