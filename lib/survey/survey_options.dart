import '../l10n/app_strings.dart';

/// 気になったフレーバー。
///
/// apiValue は表示言語に関係なく固定する。画面を日本語に切り替えただけで
/// 集計値が「Seafood」と「シーフード」に割れるのを避けるため。
enum FlavorChoice {
  spicyMiso('Spicy Miso'),
  japaneseCurry('Japanese Curry'),
  seafood('Seafood'),
  undecided('Undecided');

  const FlavorChoice(this.apiValue);

  final String apiValue;

  String label(AppStrings strings) => switch (this) {
        FlavorChoice.spicyMiso => strings.flavorSpicyMiso,
        FlavorChoice.japaneseCurry => strings.flavorJapaneseCurry,
        FlavorChoice.seafood => strings.flavorSeafood,
        FlavorChoice.undecided => strings.flavorUndecided,
      };
}

/// ブースを知ったきっかけ。apiValue を固定する理由は FlavorChoice と同じ。
enum HowHeardChoice {
  sns('SNS'),
  referral('Referral'),
  walkedBy('Walked by'),
  other('Other');

  const HowHeardChoice(this.apiValue);

  final String apiValue;

  String label(AppStrings strings) => switch (this) {
        HowHeardChoice.sns => strings.howHeardSns,
        HowHeardChoice.referral => strings.howHeardReferral,
        HowHeardChoice.walkedBy => strings.howHeardWalkedBy,
        HowHeardChoice.other => strings.howHeardOther,
      };
}

/// 音声入力を選択肢に対応づけるためのキーワード。
///
/// 表示言語で絞らず日英まとめて持たせている。日本語表示のまま英語で
/// 商品名を言う来場者(逆も同様)がいるため。
const Map<FlavorChoice, List<String>> kFlavorVoiceKeywords = {
  FlavorChoice.spicyMiso: [
    'spicy miso',
    'spicy',
    'miso',
    'スパイシー',
    'ミソ',
    'みそ',
    '味噌',
  ],
  FlavorChoice.japaneseCurry: [
    'japanese curry',
    'curry',
    'カレー',
    'かれー',
  ],
  FlavorChoice.seafood: [
    'seafood',
    'sea food',
    'シーフード',
    '海鮮',
    'かいせん',
  ],
  FlavorChoice.undecided: [
    'not decided',
    "haven't decided",
    'have not decided',
    'undecided',
    'not sure yet',
    'まだ決めてない',
    'まだ決めていない',
    'きめてない',
    '決まってない',
    'わからない',
  ],
};

const Map<HowHeardChoice, List<String>> kHowHeardVoiceKeywords = {
  HowHeardChoice.sns: [
    'sns',
    'social media',
    'instagram',
    'insta',
    'facebook',
    'tiktok',
    'twitter',
    'エスエヌエス',
    'インスタ',
    'フェイスブック',
    'ティックトック',
    'ツイッター',
    'エックス',
  ],
  HowHeardChoice.referral: [
    'friend',
    'a friend told me',
    'referral',
    'word of mouth',
    'someone told me',
    '知人',
    '友人',
    '友達',
    'ともだち',
    '紹介',
    '口コミ',
  ],
  HowHeardChoice.walkedBy: [
    'walked by',
    'walking by',
    'passed by',
    'passing by',
    'just walked',
    'saw the booth',
    '通りがかり',
    '通りがかった',
    '偶然',
    'たまたま',
    '歩いてて',
  ],
  HowHeardChoice.other: [
    'other',
    'something else',
    'その他',
    'そのほか',
    'ほかの',
  ],
};
