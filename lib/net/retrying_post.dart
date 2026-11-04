import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 会場のWi-Fiの一瞬の途切れでAIRAが止まらないよう、通信を自動でやり直す。
///
/// やり直すのは「つながらなかった/時間切れ/サーバー側の一時エラー(5xx)」だけ。
/// 4xx(キーの誤り・リクエストの誤り)はやり直しても直らないので、そのまま返す。
/// 全体の待ち時間が [totalBudget] を超えそうなら、それ以上はやり直さない
/// (来場者を待たせすぎないため)。
Future<http.Response> retryingPost(
  Uri uri, {
  required Map<String, String> headers,
  required String body,
  Duration timeout = const Duration(seconds: 8),
  int maxAttempts = 3,
  Duration totalBudget = const Duration(seconds: 20),
  List<Duration> backoff = const [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ],
  http.Client? client,
}) async {
  final stopwatch = Stopwatch()..start();
  final c = client ?? http.Client();
  Object? lastError;
  http.Response? lastResponse;

  try {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        final wait = backoff[(attempt - 1).clamp(0, backoff.length - 1)];
        // 次の試行に十分な時間が残っていなければ諦める。
        if (stopwatch.elapsed + wait + const Duration(seconds: 2) > totalBudget) {
          break;
        }
        await Future<void>.delayed(wait);
      }
      try {
        final response =
            await c.post(uri, headers: headers, body: body).timeout(timeout);
        if (response.statusCode < 500) return response;
        lastResponse = response;
        lastError = 'HTTP ${response.statusCode}';
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      }
    }
  } finally {
    if (client == null) c.close();
  }

  if (lastResponse != null) return lastResponse;
  throw lastError ?? Exception('request failed');
}
