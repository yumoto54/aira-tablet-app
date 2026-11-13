import 'package:flutter_test/flutter_test.dart';

import 'package:aira_tablet_app/l10n/app_locale.dart';
import 'package:aira_tablet_app/l10n/app_strings.dart';

void main() {
  group('スペイン語(米国)', () {
    test('ロケールの設定は es-US', () {
      expect(AppLocale.es.tag, 'es-US');
      expect(AppLocale.es.sttLocaleId, 'es_US');
      expect(AppLocale.es.switcherLabel, 'ES');
      expect(AppLocale.es.flag, '🇪🇸');
      expect(AppLocale.en.flag, '🇺🇸');
      expect(AppLocale.ja.flag, '🇯🇵');
      expect(AppLocale.es.isSpanish, isTrue);
      expect(AppLocale.es.isJapanese, isFalse);
      expect(AppLocale.en.isSpanish, isFalse);
    });

    test('文言が英語と同じ数だけそろっている', () {
      final es = AppStrings.of(AppLocale.es);
      final en = AppStrings.of(AppLocale.en);
      expect(es.attractMessages.length, en.attractMessages.length);
      expect(es.satisfactionLabels.length, 5);
      expect(es.attractMessages.first, contains('AIRA'));
      expect(es.stepIndicator(1, 3), contains('1'));
    });

    test('どの言語の文言にも、無料ギフトの言い回しが残っていない', () {
      final gift = RegExp(r'free gift|giveaway|景品|プレゼント|regalo|贈品', caseSensitive: false);
      for (final locale in AppLocale.values) {
        final s = AppStrings.of(locale);
        final all = [s.surveyCta, s.surveyInvitation, ...s.attractMessages];
        for (final t in all) {
          expect(gift.hasMatch(t), isFalse, reason: '${locale.tag}: $t');
        }
      }
    });
  });
}
