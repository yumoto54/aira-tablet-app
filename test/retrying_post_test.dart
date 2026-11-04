import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aira_tablet_app/net/retrying_post.dart';

Future<http.Response> _run(http.Client c, {int maxAttempts = 3}) => retryingPost(
      Uri.parse('https://example.test/api/chat'),
      headers: const {'Content-Type': 'application/json'},
      body: '{}',
      client: c,
      maxAttempts: maxAttempts,
      backoff: const [Duration(milliseconds: 1)],
      timeout: const Duration(milliseconds: 50),
    );

void main() {
  test('成功すればそのまま返す(1回だけ呼ぶ)', () async {
    var calls = 0;
    final r = await _run(MockClient((_) async {
      calls++;
      return http.Response('ok', 200);
    }));
    expect(r.statusCode, 200);
    expect(calls, 1);
  });

  test('接続エラーのあと成功すれば、やり直して成功する', () async {
    var calls = 0;
    final r = await _run(MockClient((_) async {
      calls++;
      if (calls < 3) throw const SocketException('offline');
      return http.Response('ok', 200);
    }));
    expect(r.statusCode, 200);
    expect(calls, 3);
  });

  test('5xxはやり直し、回復すれば成功', () async {
    var calls = 0;
    final r = await _run(MockClient((_) async {
      calls++;
      return calls == 1 ? http.Response('x', 503) : http.Response('ok', 200);
    }));
    expect(r.statusCode, 200);
    expect(calls, 2);
  });

  test('4xxはやり直さない', () async {
    var calls = 0;
    final r = await _run(MockClient((_) async {
      calls++;
      return http.Response('no', 401);
    }));
    expect(r.statusCode, 401);
    expect(calls, 1);
  });

  test('時間切れは回数まで試して、最後は例外', () async {
    var calls = 0;
    await expectLater(
      _run(MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('late', 200);
      })),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 3);
  });

  test('ずっと5xxなら最後の応答を返す', () async {
    var calls = 0;
    final r = await _run(MockClient((_) async {
      calls++;
      return http.Response('x', 500);
    }));
    expect(r.statusCode, 500);
    expect(calls, 3);
  });
}
