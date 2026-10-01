import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aira_tablet_app/l10n/app_locale.dart';
import 'package:aira_tablet_app/survey/survey_flow_page.dart';

Future<void> _pumpFlow(WidgetTester tester, http.Client client) async {
  // 既定の800x600ではなく、実機に近い横向きタブレットの大きさで確認する
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: SurveyFlowPage(locale: AppLocale.ja, httpClient: client),
    ),
  );
}

/// 選択肢をタップして「次へ」で進む
Future<void> _choose(WidgetTester tester, String label) async {
  // 選択肢が画面に収まらない場合はスクロールして出す
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.tap(find.text('次へ'));
  await tester.pump();
}

Future<void> _fillNameAndEmail(
  WidgetTester tester, {
  required String name,
  required String email,
}) async {
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.text('次へ'));
  await tester.pump();

  await tester.enterText(find.byType(TextField), email);
  await tester.pump();
}

void main() {
  testWidgets('5問すべて答えて送信すると完了コードが大きく表示される', (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"code":"6KT9HB"}', 200);
    });

    await _pumpFlow(tester, client);

    expect(find.text('ステップ 1 / 5'), findsOneWidget);
    expect(find.text('気になったフレーバーは？'), findsOneWidget);

    await _choose(tester, 'Spicy Miso');
    expect(find.text('ステップ 2 / 5'), findsOneWidget);

    await _choose(tester, '5');
    await _choose(tester, 'SNS');

    expect(find.text('ステップ 4 / 5'), findsOneWidget);
    await _fillNameAndEmail(
      tester,
      name: 'Jane Doe',
      email: 'jane@example.com',
    );

    await tester.tap(find.text('送信する'));
    await tester.pumpAndSettle();

    expect(find.text('ありがとうございました！'), findsOneWidget);
    expect(find.text('6KT9HB'), findsOneWidget);
    expect(find.text('このコードをスタッフにお見せください'), findsOneWidget);
  });

  testWidgets('メールアドレス未入力のまま送信するとAPIを呼ばずに案内が出る', (tester) async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      return http.Response('{"code":"XXXXXX"}', 200);
    });

    await _pumpFlow(tester, client);

    await _choose(tester, 'Spicy Miso');
    await _choose(tester, '5');
    await _choose(tester, 'SNS');

    await tester.enterText(find.byType(TextField), 'Jane Doe');
    await tester.pump();
    await tester.tap(find.text('次へ'));
    await tester.pump();

    await tester.tap(find.text('送信する'));
    await tester.pump();

    expect(requestCount, 0);
    expect(find.text('メールアドレスを入力してください。'), findsOneWidget);
  });

  testWidgets('APIが400を返したらその文言を出し、入力済みの回答は残る', (tester) async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode({
            'error': 'validation_failed',
            'details': ['email must be a valid email address'],
          }),
          400,
        );
      }
      return http.Response('{"code":"PUEHZE"}', 200);
    });

    await _pumpFlow(tester, client);

    await _choose(tester, 'Spicy Miso');
    await _choose(tester, '5');
    await _choose(tester, 'SNS');
    await _fillNameAndEmail(
      tester,
      name: 'Jane Doe',
      email: 'jane@example.com',
    );

    await tester.tap(find.text('送信する'));
    await tester.pumpAndSettle();

    expect(find.text('email must be a valid email address'), findsOneWidget);

    // 前の設問に戻っても選択が消えていないこと
    await tester.tap(find.text('戻る'));
    await tester.pump();
    expect(find.text('ステップ 4 / 5'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Jane Doe'), findsOneWidget);

    // 直してもう一度送れば通る
    await tester.tap(find.text('次へ'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'jane@example.com');
    await tester.pump();
    await tester.tap(find.text('送信する'));
    await tester.pumpAndSettle();

    expect(find.text('PUEHZE'), findsOneWidget);
  });

  testWidgets('同意チェックはメールアドレスを入れてから現れ、既定は未チェック', (tester) async {
    late Map<String, dynamic> sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"code":"6KT9HB"}', 200);
    });

    await _pumpFlow(tester, client);

    await _choose(tester, 'Spicy Miso');
    await _choose(tester, '5');
    await _choose(tester, 'SNS');

    await tester.enterText(find.byType(TextField), 'Jane Doe');
    await tester.pump();
    await tester.tap(find.text('次へ'));
    await tester.pump();

    // メールアドレスが空のうちは出さない
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.enterText(find.byType(TextField), 'jane@example.com');
    await tester.pump();

    final checkbox = find.byType(CheckboxListTile);
    expect(checkbox, findsOneWidget);
    expect(find.text('AIRAからお得な情報や新商品のお知らせを受け取る（任意）'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(checkbox).value, false);

    await tester.tap(find.text('送信する'));
    await tester.pumpAndSettle();

    expect(sentBody['consentToFollowUp'], false);
  });

  testWidgets('同意にチェックするとtrueで送られる', (tester) async {
    late Map<String, dynamic> sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"code":"6KT9HB"}', 200);
    });

    await _pumpFlow(tester, client);

    await _choose(tester, 'Spicy Miso');
    await _choose(tester, '5');
    await _choose(tester, 'SNS');
    await _fillNameAndEmail(
      tester,
      name: 'Jane Doe',
      email: 'jane@example.com',
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      true,
    );

    await tester.tap(find.text('送信する'));
    await tester.pumpAndSettle();

    expect(sentBody['consentToFollowUp'], true);
  });

  testWidgets('同意後にメールアドレスを消すとチェックも消える', (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"code":"6KT9HB"}', 200);
    });

    await _pumpFlow(tester, client);

    await _choose(tester, 'Spicy Miso');
    await _choose(tester, '5');
    await _choose(tester, 'SNS');
    await _fillNameAndEmail(
      tester,
      name: 'Jane Doe',
      email: 'jane@example.com',
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);

    // 入れ直しても同意は復活せず、未チェックから始まる
    await tester.enterText(find.byType(TextField), 'jane@example.com');
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
  });

  testWidgets('メールアドレスの設問にはマイクを置かない', (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"code":"XXXXXX"}', 200);
    });

    await _pumpFlow(tester, client);

    await _choose(tester, 'Spicy Miso');
    await _choose(tester, '5');
    await _choose(tester, 'SNS');

    // 名前の設問にはマイクがある
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Jane Doe');
    await tester.pump();
    await tester.tap(find.text('次へ'));
    await tester.pump();

    // メールアドレスの設問には無い
    expect(find.text('メールアドレスを教えてください'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
  });
}
