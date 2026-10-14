import 'package:flutter_test/flutter_test.dart';

import 'package:aira_tablet_app/l10n/app_locale.dart';
import 'package:aira_tablet_app/l10n/app_strings.dart';
import 'package:aira_tablet_app/survey/survey_options.dart';
import 'package:aira_tablet_app/survey/voice_match.dart';

void main() {
  group('繁体字中国語(台湾)', () {
    test('ロケールの設定は zh-TW', () {
      expect(AppLocale.zhTw.tag, 'zh-TW');
      expect(AppLocale.zhTw.sttLocaleId, 'zh_TW');
      expect(AppLocale.zhTw.isChinese, isTrue);
      expect(AppLocale.zhTw.isJapanese, isFalse);
      expect(AppLocale.en.isChinese, isFalse);
    });

    test('文言が日本語・英語と同じ数だけそろっている', () {
      final zh = AppStrings.of(AppLocale.zhTw);
      final en = AppStrings.of(AppLocale.en);
      expect(zh.attractMessages.length, en.attractMessages.length);
      expect(zh.satisfactionLabels.length, 5);
      expect(zh.attractMessages.every((m) => m.contains('AIRA')), isTrue);
      expect(zh.stepIndicator(1, 3), contains('1'));
    });

    test('音声で答えた中国語を選択肢に対応づけられる', () {
      expect(
        matchSpokenChoice('我對辣味噌有興趣', kFlavorVoiceKeywords),
        FlavorChoice.spicyMiso,
      );
      expect(
        matchSpokenChoice('日式咖哩', kFlavorVoiceKeywords),
        FlavorChoice.japaneseCurry,
      );
      expect(
        matchSpokenChoice('海鮮口味', kFlavorVoiceKeywords),
        FlavorChoice.seafood,
      );
      expect(
        matchSpokenChoice('朋友介紹的', kHowHeardVoiceKeywords),
        HowHeardChoice.referral,
      );
      expect(
        matchSpokenChoice('剛好路過', kHowHeardVoiceKeywords),
        HowHeardChoice.walkedBy,
      );
    });
  });
}
