import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import 'survey_options.dart';

/// 記入途中のアンケート回答。
///
/// 送信に失敗しても捨てずに持ち回る。来場者に最初から答え直させないため。
class SurveyDraft {
  FlavorChoice? flavor;
  int? satisfaction;
  HowHeardChoice? howHeard;
  /// 任意。未回答なら null のまま送らない。
  GenderChoice? gender;
  AgeGroupChoice? ageGroup;
  String name = '';
  String email = '';

  /// 販促連絡を受け取ってよいか。オプトインなので既定は未同意。
  bool consentToFollowUp = false;

  /// 同意を受け付けられる状態か。宛先が無ければ同意のしようがない。
  bool get canConsent => email.trim().isNotEmpty;

  /// バックエンドと同じ簡易判定。送信前に気づける入力ミスは手元で弾く。
  static final RegExp emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// アプリ側で分かる不備を並べる。空ならAPIに送ってよい。
  List<String> validate(AppStrings strings) {
    final errors = <String>[];

    if (name.trim().isEmpty) {
      errors.add(strings.nameRequired);
    }

    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      errors.add(strings.emailRequired);
    } else if (!emailPattern.hasMatch(trimmedEmail)) {
      errors.add(strings.emailInvalid);
    }

    return errors;
  }

  Map<String, dynamic> toRequestBody(AppLocale locale) {
    return {
      'answers': {
        'flavorInterest': flavor?.apiValue ?? '',
        'satisfaction': satisfaction,
        'howHeard': howHeard?.apiValue ?? '',
        // 任意項目は、選んだときだけ送る
        if (gender != null) 'gender': gender!.apiValue,
        if (ageGroup != null) 'ageGroup': ageGroup!.apiValue,
      },
      'name': name.trim(),
      'email': email.trim(),
      'locale': locale.tag,
      // 宛先が無いのに同意だけ立っている状態を送らない
      'consentToFollowUp': canConsent && consentToFollowUp,
    };
  }
}
