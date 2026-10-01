import 'package:flutter_test/flutter_test.dart';

import 'package:aira_tablet_app/survey/survey_options.dart';
import 'package:aira_tablet_app/survey/voice_match.dart';

void main() {
  group('フレーバーの聞き取り', () {
    test('英語でも日本語でも同じ選択肢に対応づく', () {
      expect(
        matchSpokenChoice('I liked the spicy miso', kFlavorVoiceKeywords),
        FlavorChoice.spicyMiso,
      );
      expect(
        matchSpokenChoice('カレーが気になりました', kFlavorVoiceKeywords),
        FlavorChoice.japaneseCurry,
      );
      expect(
        matchSpokenChoice('シーフードかな', kFlavorVoiceKeywords),
        FlavorChoice.seafood,
      );
      expect(
        matchSpokenChoice('まだ決めてないです', kFlavorVoiceKeywords),
        FlavorChoice.undecided,
      );
    });

    test('複数の選択肢に当たる発話は決めつけずnullを返す', () {
      expect(
        matchSpokenChoice('spicy or curry, I am not sure', kFlavorVoiceKeywords),
        isNull,
      );
      expect(
        matchSpokenChoice('シーフードにするかまだ決めてない', kFlavorVoiceKeywords),
        isNull,
      );
    });

    test('どれにも当たらない発話はnullを返す(ボタン操作を促す)', () {
      expect(matchSpokenChoice('where is the restroom', kFlavorVoiceKeywords), isNull);
      expect(matchSpokenChoice('', kFlavorVoiceKeywords), isNull);
    });
  });

  group('ブースを知ったきっかけの聞き取り', () {
    test('代表的な言い回しに対応づく', () {
      expect(
        matchSpokenChoice('I saw it on Instagram', kHowHeardVoiceKeywords),
        HowHeardChoice.sns,
      );
      expect(
        matchSpokenChoice('友達に教えてもらいました', kHowHeardVoiceKeywords),
        HowHeardChoice.referral,
      );
      expect(
        matchSpokenChoice('I just walked by', kHowHeardVoiceKeywords),
        HowHeardChoice.walkedBy,
      );
      expect(
        matchSpokenChoice('その他です', kHowHeardVoiceKeywords),
        HowHeardChoice.other,
      );
    });

    test('単語の内部に埋もれたキーワードでは誤って選ばれない', () {
      // "brother" の中の "other" を拾わないこと
      expect(
        matchSpokenChoice('my brother works here', kHowHeardVoiceKeywords),
        isNot(HowHeardChoice.other),
      );
    });
  });

  group('満足度の聞き取り', () {
    test('数字をそのまま言った場合', () {
      expect(matchSpokenRating('5'), 5);
      expect(matchSpokenRating('I would say 4'), 4);
      expect(matchSpokenRating('５'), 5); // 全角
      expect(matchSpokenRating('5 stars'), 5);
    });

    test('英語の数詞', () {
      expect(matchSpokenRating('five'), 5);
      expect(matchSpokenRating('I think three'), 3);
    });

    test('日本語の数詞', () {
      expect(matchSpokenRating('ご'), 5);
      expect(matchSpokenRating('さんです'), 3);
      expect(matchSpokenRating('四点'), 4);
      expect(matchSpokenRating('ふたつ'), 2);
    });

    test('助詞の「に」を2点と読み違えない', () {
      // 部分一致だと「明日にします」が2点になってしまう
      expect(matchSpokenRating('明日にします'), isNull);
      expect(matchSpokenRating('ブースに来ました'), isNull);
    });

    test('数字が複数出てきたら決めつけない', () {
      expect(matchSpokenRating('between 1 and 5'), isNull);
    });

    test('範囲外の数字や無関係な発話はnull', () {
      expect(matchSpokenRating('9'), isNull);
      expect(matchSpokenRating('I do not know'), isNull);
      expect(matchSpokenRating(''), isNull);
    });
  });
}
