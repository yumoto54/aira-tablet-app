import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';

/// 送信完了画面。スタッフが少し離れた位置からでも読めるよう、コードを大きく出す。
class SurveyCompletePage extends StatelessWidget {
  const SurveyCompletePage({
    super.key,
    required this.code,
    required this.locale,
  });

  final String code;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(locale);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.card_giftcard,
                  size: 96,
                  color: colors.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  strings.completionTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      // 口頭で伝えたり書き写したりするので、字間を広めに取る
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 12,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  strings.completionShowStaff,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 20,
                    ),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: Text(strings.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
