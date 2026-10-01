/// アプリの表示・音声の言語。
///
/// 既定は en-US。会場はLAで来場者の多くが英語話者であることと、
/// バックエンドのFAQが英語キーワードで組まれていることによる。
enum AppLocale {
  en(
    tag: 'en-US',
    sttLocaleId: 'en_US',
    switcherLabel: 'EN',
  ),
  ja(
    tag: 'ja-JP',
    sttLocaleId: 'ja_JP',
    switcherLabel: '日本語',
  );

  const AppLocale({
    required this.tag,
    required this.sttLocaleId,
    required this.switcherLabel,
  });

  /// バックエンド(/api/chat, /api/speak, /api/survey)に渡すロケール文字列。
  final String tag;

  /// speech_to_text に渡すロケールID。区切りがハイフンではなくアンダースコア。
  final String sttLocaleId;

  final String switcherLabel;

  bool get isJapanese => this == AppLocale.ja;
}
