import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../l10n/app_locale.dart';

/// スロットを1回回した結果。抽選はサーバーで行い、アプリは絵柄を表示するだけ。
class SpinResult {
  const SpinResult({
    required this.result,
    required this.reels,
    required this.playsLeft,
    this.prizeLabel,
    this.couponCode,
    this.expiresAt,
  });

  /// 'jackpot' | 'small' | 'miss'
  final String result;

  /// 3つの絵柄の番号(0〜4)
  final List<int> reels;
  final int playsLeft;
  final String? prizeLabel;
  final String? couponCode;
  final DateTime? expiresAt;

  bool get isWin => result == 'jackpot' || result == 'small';
}

sealed class SpinOutcome {
  const SpinOutcome();
}

class SpinOk extends SpinOutcome {
  const SpinOk(this.result);
  final SpinResult result;
}

/// 今日の挑戦回数の上限に達した
class SpinLimitReached extends SpinOutcome {
  const SpinLimitReached();
}

/// 通信断・サーバー障害・ゲームが無効など。画面には汎用のエラーを出す
class SpinFailed extends SpinOutcome {
  const SpinFailed(this.debugMessage);
  final String debugMessage;
}

Future<SpinOutcome> spinSlot({
  required AppLocale locale,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse('$kApiBaseUrl/api/game/spin'),
          headers: {
            'Content-Type': 'application/json',
            'x-functions-key': kApiFunctionKey,
            if (kTenantId.isNotEmpty) 'x-tenant-id': kTenantId,
          },
          body: jsonEncode({'deviceId': kDeviceId, 'locale': locale.tag}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) return const SpinLimitReached();
    if (response.statusCode != 200) {
      return SpinFailed('HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final reels = (body['reels'] as List?)?.map((e) => (e as num).toInt()).toList();
    final result = body['result'] as String?;
    if (reels == null || reels.length != 3 || result == null) {
      return const SpinFailed('malformed response');
    }
    return SpinOk(
      SpinResult(
        result: result,
        reels: reels,
        playsLeft: (body['playsLeft'] as num?)?.toInt() ?? 0,
        prizeLabel: body['prizeLabel'] as String?,
        couponCode: body['couponCode'] as String?,
        expiresAt: DateTime.tryParse((body['expiresAt'] as String?) ?? '')?.toLocal(),
      ),
    );
  } catch (e) {
    return SpinFailed(e.toString());
  } finally {
    if (client == null) httpClient.close();
  }
}
