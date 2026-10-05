import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../l10n/app_locale.dart';
import '../monitoring/device_monitor.dart';
import 'survey_draft.dart';

sealed class SurveySubmitResult {
  const SurveySubmitResult();
}

class SurveySubmitSuccess extends SurveySubmitResult {
  const SurveySubmitSuccess(this.code);

  /// スタッフに見せる完了コード
  final String code;
}

/// APIが返した検証エラー。文言はそのまま画面に出して、どの欄を直せばよいか分かるようにする。
class SurveySubmitInvalid extends SurveySubmitResult {
  const SurveySubmitInvalid(this.details);

  final List<String> details;
}

/// 通信断やサーバー障害など、来場者の入力とは関係なく失敗した場合。
class SurveySubmitFailed extends SurveySubmitResult {
  const SurveySubmitFailed(this.debugMessage);

  /// 画面には出さず、原因追跡用に持っておく文字列
  final String debugMessage;
}

Future<SurveySubmitResult> submitSurvey({
  required SurveyDraft draft,
  required AppLocale locale,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();

  try {
    final response = await httpClient.post(
      Uri.parse('$kApiBaseUrl/api/survey'),
      headers: {
        'Content-Type': 'application/json',
        'x-functions-key': kApiFunctionKey,
      },
      body: jsonEncode(draft.toRequestBody(locale)),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final code = body['code'] as String?;
      if (code == null || code.isEmpty) {
        return const SurveySubmitFailed('200 response without a code');
      }
      return SurveySubmitSuccess(code);
    }

    if (response.statusCode == 400) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final details = (body['details'] as List?)
              ?.map((detail) => detail.toString())
              .toList() ??
          const <String>[];
      if (details.isEmpty) {
        return SurveySubmitFailed('400 ${body['error'] ?? 'validation_failed'}');
      }
      return SurveySubmitInvalid(details);
    }

    DeviceMonitor.instance
        .recordApiFailure('survey: HTTP ${response.statusCode}');
    return SurveySubmitFailed('HTTP ${response.statusCode}');
  } catch (error) {
    DeviceMonitor.instance.recordApiFailure('survey: $error');
    return SurveySubmitFailed('$error');
  } finally {
    // 呼び出し側から渡されたクライアントは、こちらの都合で閉じない。
    if (client == null) httpClient.close();
  }
}
