import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aira_tablet_app/l10n/app_locale.dart';
import 'package:aira_tablet_app/survey/survey_api.dart';
import 'package:aira_tablet_app/survey/survey_draft.dart';
import 'package:aira_tablet_app/survey/survey_options.dart';

SurveyDraft _filledDraft() {
  return SurveyDraft()
    ..flavor = FlavorChoice.spicyMiso
    ..satisfaction = 5
    ..howHeard = HowHeardChoice.sns
    ..name = 'Jane Doe'
    ..email = 'jane@example.com';
}

void main() {
  test('送信に成功したら完了コードを返す', () async {
    final client = MockClient((request) async {
      return http.Response('{"code":"6KT9HB"}', 200);
    });

    final result = await submitSurvey(
      draft: _filledDraft(),
      locale: AppLocale.en,
      client: client,
    );

    expect(result, isA<SurveySubmitSuccess>());
    expect((result as SurveySubmitSuccess).code, '6KT9HB');
  });

  test('表示言語を日本語にしても保存される回答値は英語の正規形になる', () async {
    late Map<String, dynamic> sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"code":"ABC234"}', 200);
    });

    await submitSurvey(
      draft: _filledDraft(),
      locale: AppLocale.ja,
      client: client,
    );

    final answers = sentBody['answers'] as Map<String, dynamic>;
    expect(answers['flavorInterest'], 'Spicy Miso');
    expect(answers['howHeard'], 'SNS');
    // バックエンドは整数以外を弾くので、数値のまま送れているかを見る
    expect(answers['satisfaction'], 5);
    expect(sentBody['name'], 'Jane Doe');
    expect(sentBody['email'], 'jane@example.com');
    expect(sentBody['locale'], 'ja-JP');
  });

  test('同意していなければ consentToFollowUp は false で送る', () async {
    late Map<String, dynamic> sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"code":"ABC234"}', 200);
    });

    await submitSurvey(
      draft: _filledDraft(),
      locale: AppLocale.en,
      client: client,
    );

    expect(sentBody['consentToFollowUp'], false);
  });

  test('同意していれば consentToFollowUp は true で送る', () async {
    late Map<String, dynamic> sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"code":"ABC234"}', 200);
    });

    await submitSurvey(
      draft: _filledDraft()..consentToFollowUp = true,
      locale: AppLocale.en,
      client: client,
    );

    expect(sentBody['consentToFollowUp'], true);
  });

  test('メールアドレスが空なら同意が立っていても false で送る', () async {
    late Map<String, dynamic> sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"code":"ABC234"}', 200);
    });

    await submitSurvey(
      draft: _filledDraft()
        ..email = ''
        ..consentToFollowUp = true,
      locale: AppLocale.en,
      client: client,
    );

    expect(sentBody['consentToFollowUp'], false);
  });

  test('400のときはAPIが返したdetailsをそのまま持ち帰る', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'validation_failed',
          'details': [
            'email must be a valid email address',
            'answers.satisfaction must be between 1 and 5',
          ],
        }),
        400,
      );
    });

    final result = await submitSurvey(
      draft: _filledDraft(),
      locale: AppLocale.en,
      client: client,
    );

    expect(result, isA<SurveySubmitInvalid>());
    expect(
      (result as SurveySubmitInvalid).details,
      ['email must be a valid email address', 'answers.satisfaction must be between 1 and 5'],
    );
  });

  test('通信に失敗した場合は検証エラーと区別して返す', () async {
    final client = MockClient((request) async {
      throw http.ClientException('connection refused');
    });

    final result = await submitSurvey(
      draft: _filledDraft(),
      locale: AppLocale.en,
      client: client,
    );

    expect(result, isA<SurveySubmitFailed>());
  });

  test('想定外のステータスコードも通信失敗として扱う', () async {
    final client = MockClient((request) async {
      return http.Response('Internal Server Error', 500);
    });

    final result = await submitSurvey(
      draft: _filledDraft(),
      locale: AppLocale.en,
      client: client,
    );

    expect(result, isA<SurveySubmitFailed>());
  });
}
