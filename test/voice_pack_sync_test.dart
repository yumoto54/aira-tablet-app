import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aira_tablet_app/voicepack/voice_pack.dart';
import 'package:aira_tablet_app/voicepack/voice_pack_sync.dart';

const idA = '0123456789abcdef';
const idB = 'fedcba9876543210';

String manifestJson({String version = 'v1', List<String> ids = const [idA]}) => jsonEncode({
      'version': 1,
      'generatedAt': version,
      'clips': {
        'en-US': {for (var i = 0; i < ids.length; i++) 'Text $i': ids[i]},
      },
    });

String clipJson(String marker) => jsonEncode({
      'audioBase64': base64Encode(utf8.encode(marker)),
      'mouthCues': [
        {'mouthShape': 'a', 'fileName': 'a.png', 'audioOffsetMs': 0},
      ],
    });

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('voicepack_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  VoicePackSync build(
    Future<http.Response> Function(http.Request) handler,
  ) =>
      VoicePackSync(
        dir: dir,
        baseUrl: 'https://example.test',
        client: MockClient(handler),
      );

  test('新しい音声を受け取り、目録を最後に置く', () async {
    final result = await build((req) async {
      if (req.url.path == '/api/voicepack/manifest') {
        return http.Response(manifestJson(ids: [idA, idB]), 200);
      }
      return http.Response(clipJson('audio-${req.url.pathSegments.last}'), 200);
    }).sync();

    expect(result, VoicePackSyncResult.updated);
    expect(await File('${dir.path}/$idA.mp3').readAsString(), 'audio-$idA');
    expect(await File('${dir.path}/$idB.json').exists(), isTrue);
    expect(await File('${dir.path}/manifest.json').exists(), isTrue);
  });

  test('版が同じで、クリップも揃っていれば何も取らない', () async {
    var clipCalls = 0;
    Future<http.Response> handler(http.Request req) async {
      if (req.url.path == '/api/voicepack/manifest') return http.Response(manifestJson(), 200);
      clipCalls++;
      return http.Response(clipJson('x'), 200);
    }

    expect(await build(handler).sync(), VoicePackSyncResult.updated);
    expect(clipCalls, 1);
    expect(await build(handler).sync(), VoicePackSyncResult.upToDate);
    expect(clipCalls, 1);
  });

  test('一部のクリップが取れなければ、目録は書き換えない(次回やり直す)', () async {
    final result = await build((req) async {
      if (req.url.path == '/api/voicepack/manifest') {
        return http.Response(manifestJson(ids: [idA, idB]), 200);
      }
      if (req.url.pathSegments.last == idB) return http.Response('boom', 500);
      return http.Response(clipJson('ok'), 200);
    }).sync();

    expect(result, VoicePackSyncResult.partial);
    expect(await File('${dir.path}/manifest.json').exists(), isFalse);
  });

  test('サーバーに無い・通信できないときは unavailable で、何も壊さない', () async {
    expect(
      await build((req) async => http.Response('{}', 404)).sync(),
      VoicePackSyncResult.unavailable,
    );
    expect(
      await build((req) async => throw const SocketException('offline')).sync(),
      VoicePackSyncResult.unavailable,
    );
  });

  test('ファイル名として危険なIDを含む目録は信用しない', () async {
    final bad = jsonEncode({
      'generatedAt': 'v1',
      'clips': {
        'en-US': {'x': '../../etc/passwd'},
      },
    });
    final result = await build((req) async => http.Response(bad, 200)).sync();
    expect(result, VoicePackSyncResult.unavailable);
    expect(await File('${dir.path}/manifest.json').exists(), isFalse);
  });

  test('目録から消えた古いクリップは削除する', () async {
    String current = manifestJson(version: 'v1', ids: [idA, idB]);
    Future<http.Response> handler(http.Request req) async {
      if (req.url.path == '/api/voicepack/manifest') return http.Response(current, 200);
      return http.Response(clipJson('ok'), 200);
    }

    await build(handler).sync();
    current = manifestJson(version: 'v2', ids: [idA]);
    expect(await build(handler).sync(), VoicePackSyncResult.updated);
    expect(await File('${dir.path}/$idA.mp3').exists(), isTrue);
    expect(await File('${dir.path}/$idB.mp3').exists(), isFalse);
    expect(await File('${dir.path}/$idB.json').exists(), isFalse);
  });

  test('受け取った音声は、同梱より先に使われる', () async {
    await build((req) async {
      if (req.url.path == '/api/voicepack/manifest') return http.Response(manifestJson(), 200);
      return http.Response(clipJson('remote-audio'), 200);
    }).sync();

    final pack = VoicePack(
      loadString: (path) async => '{"version":1,"generatedAt":"bundled-v","clips":{"en-US":{"Text 0":"aaaaaaaaaaaaaaaa"}}}',
      loadBytes: (path) async => throw Exception('同梱は読まれないはず'),
    );
    expect(pack.versionLabel, isNull);
    await pack.load();
    expect(pack.versionLabel, 'bundled:bundled-v');

    await pack.attachRemote(dir);
    expect(pack.versionLabel, 'v1');
    final clip = await pack.lookup('en-US', 'Text 0');
    expect(clip, isNotNull);
    expect(utf8.decode(clip!.audioBytes), 'remote-audio');
  });
}
