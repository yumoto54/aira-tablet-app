import 'app_locale.dart';

/// 画面と音声で使う文言。日本語と英語の2言語分を持つ。
///
/// 来場者が選んだ言語で表示・発話するが、APIに保存する回答値は言語に依存しない
/// 正規形(survey_options.dart の apiValue)を使う。表示言語で集計がぶれないようにするため。
abstract class AppStrings {
  const AppStrings();

  static const AppStrings _ja = _JaStrings();
  static const AppStrings _en = _EnStrings();

  static AppStrings of(AppLocale locale) => locale.isJapanese ? _ja : _en;

  // --- メイン画面 ---

  /// メイン画面に常設するアンケート導線のラベル
  String get surveyCta;

  /// 3ターン目の会話が終わったあと、次の返答の末尾に足して読み上げる一文
  String get surveyInvitation;

  /// アイドル(誰も話しかけていない)状態がしばらく続いたときに、AIRAが
  /// 自分から発話して呼び込む「アトラクトモード」のセリフ。
  /// 複数用意してローテーションし、単調にならないようにする。
  List<String> get attractMessages;

  /// マイクで聞き取れなかった(無音/認識失敗)ときに、AIRAが声で聞き返す一言。
  /// 画面上のエラー表示だけだと気づかれにくいため、音声でも案内する。
  String get voiceRetryPrompt;

  // --- ウィザード共通 ---

  String get surveyTitle;
  String stepIndicator(int step, int totalSteps);
  String get back;
  String get next;
  String get submit;
  String get submitting;

  /// 通信自体が失敗したとき(APIの検証エラーとは区別する)
  String get submitNetworkError;

  // --- 各設問 ---

  String get questionFlavor;
  String get questionSatisfaction;
  String get questionHowHeard;
  String get questionName;
  String get questionEmail;

  /// メールアドレス欄の下に小さく出す案内
  String get emailNote;

  /// 販促連絡の同意チェックボックスのラベル(オプトイン)
  String get consentToFollowUp;

  String get nameFieldHint;
  String get emailFieldHint;

  // --- 入力チェック(送信前にアプリ側で見る分) ---

  String get nameRequired;
  String get emailRequired;
  String get emailInvalid;

  // --- 音声入力 ---

  String get voiceHint;
  String get voiceAnswerButton;
  String get voiceListening;
  String get voiceStop;

  /// 聞き取れたがどの選択肢か判断できなかったとき
  String get voiceNoMatch;

  String get voiceUnavailable;

  /// 名前欄の横に置くマイクボタンの読み上げラベル
  String get voiceFillName;

  // --- 満足度の5段階ラベル ---

  /// 1〜5の順に5件。index 0 が「1」。
  List<String> get satisfactionLabels;

  // --- 選択肢ラベル ---

  String get flavorSpicyMiso;
  String get flavorJapaneseCurry;
  String get flavorSeafood;
  String get flavorUndecided;

  String get howHeardSns;
  String get howHeardReferral;
  String get howHeardWalkedBy;
  String get howHeardOther;

  // --- 完了画面 ---

  String get completionTitle;
  String get completionShowStaff;
  String get close;
}

class _JaStrings extends AppStrings {
  const _JaStrings();

  @override
  String get surveyCta => 'アンケートに答えて景品をもらう';

  @override
  String get surveyInvitation => 'ところで、アンケートに答えると景品がもらえますよ。';

  @override
  List<String> get attractMessages => const [
        'こんにちは！フリーダムラーメンのアイラです。マイクを押して、気になることを何でも聞いてくださいね。',
        'ちょっと気になった方、こんにちは！アンケートに答えるとプレゼントがもらえますよ。',
        'おいしいラーメンの話、聞いていきませんか？マイクのボタンを押して話しかけてくださいね。',
        'アンケートに答えるだけで、プレゼントがもらえちゃいます！ぜひ参加してくださいね。',
      ];

  @override
  String get voiceRetryPrompt => 'ごめんなさい、うまく聞き取れませんでした。もう一度、ゆっくりお話しいただけますか？';

  @override
  String get surveyTitle => 'アンケート';

  @override
  String stepIndicator(int step, int totalSteps) => 'ステップ $step / $totalSteps';

  @override
  String get back => '戻る';

  @override
  String get next => '次へ';

  @override
  String get submit => '送信する';

  @override
  String get submitting => '送信中…';

  @override
  String get submitNetworkError => '送信できませんでした。通信状態を確認して、もう一度お試しください。';

  @override
  String get questionFlavor => '気になったフレーバーは？';

  @override
  String get questionSatisfaction => 'また買いたいと思いましたか？';

  @override
  String get questionHowHeard => 'どこでこのブースを知りましたか？';

  @override
  String get questionName => 'お名前を教えてください';

  @override
  String get questionEmail => 'メールアドレスを教えてください';

  @override
  String get emailNote => 'お知らせの送付は、下のチェックに同意いただいた場合のみ行います。';

  @override
  String get consentToFollowUp => 'AIRAからお得な情報や新商品のお知らせを受け取る（任意）';

  @override
  String get nameFieldHint => '例: 山田 太郎';

  @override
  String get emailFieldHint => '例: name@example.com';

  @override
  String get nameRequired => 'お名前を入力してください。';

  @override
  String get emailRequired => 'メールアドレスを入力してください。';

  @override
  String get emailInvalid => 'メールアドレスの形式が正しくないようです。';

  @override
  String get voiceHint => 'ボタンを押すか、声でもお答えいただけます。';

  @override
  String get voiceAnswerButton => '声で答える';

  @override
  String get voiceListening => '聞き取り中…';

  @override
  String get voiceStop => '停止';

  @override
  String get voiceNoMatch => 'うまく聞き取れませんでした。お手数ですがボタンでお選びください。';

  @override
  String get voiceUnavailable => 'マイクが使えませんでした。ボタンでお選びください。';

  @override
  String get voiceFillName => '声で入力';

  @override
  List<String> get satisfactionLabels => const [
        'そう思わない',
        'あまり思わない',
        'どちらとも言えない',
        'そう思う',
        'とてもそう思う',
      ];

  @override
  String get flavorSpicyMiso => 'Spicy Miso';

  @override
  String get flavorJapaneseCurry => 'Japanese Curry';

  @override
  String get flavorSeafood => 'Seafood';

  @override
  String get flavorUndecided => 'まだ決めてない';

  @override
  String get howHeardSns => 'SNS';

  @override
  String get howHeardReferral => '知人の紹介';

  @override
  String get howHeardWalkedBy => '偶然通りがかった';

  @override
  String get howHeardOther => 'その他';

  @override
  String get completionTitle => 'ありがとうございました！';

  @override
  String get completionShowStaff => 'このコードをスタッフにお見せください';

  @override
  String get close => '閉じる';
}

class _EnStrings extends AppStrings {
  const _EnStrings();

  @override
  String get surveyCta => 'Answer a survey and get a gift';

  @override
  String get surveyInvitation =>
      'By the way, if you answer a short survey, you can get a free gift.';

  @override
  List<String> get attractMessages => const [
        "Hi there! I'm AIRA from Freedom Ramen. Press the microphone button and ask me anything!",
        'Come say hello! Answer a quick survey and get a free gift.',
        'Curious about our ramen? Press the mic button and I will tell you all about it.',
        'Just answer a quick survey and get a free giveaway! Come give it a try.',
      ];

  @override
  String get voiceRetryPrompt =>
      "Sorry, I didn't catch that. Could you try again, a little more slowly?";

  @override
  String get surveyTitle => 'Survey';

  @override
  String stepIndicator(int step, int totalSteps) => 'Step $step of $totalSteps';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get submit => 'Submit';

  @override
  String get submitting => 'Submitting…';

  @override
  String get submitNetworkError =>
      'We could not submit your answers. Please check the connection and try again.';

  @override
  String get questionFlavor => 'Which flavor caught your interest?';

  @override
  String get questionSatisfaction => 'Would you buy it again?';

  @override
  String get questionHowHeard => 'How did you hear about this booth?';

  @override
  String get questionName => 'What is your name?';

  @override
  String get questionEmail => 'What is your email address?';

  @override
  String get emailNote =>
      'We will only send you news if you check the box below.';

  @override
  String get consentToFollowUp =>
      'Send me deals and news about new products from AIRA (optional)';

  @override
  String get nameFieldHint => 'e.g. Jane Doe';

  @override
  String get emailFieldHint => 'e.g. name@example.com';

  @override
  String get nameRequired => 'Please enter your name.';

  @override
  String get emailRequired => 'Please enter your email address.';

  @override
  String get emailInvalid => 'That does not look like a valid email address.';

  @override
  String get voiceHint => 'Tap a button, or answer out loud.';

  @override
  String get voiceAnswerButton => 'Answer by voice';

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voiceNoMatch =>
      "Sorry, I didn't catch that. Please tap a button instead.";

  @override
  String get voiceUnavailable =>
      'The microphone is not available. Please tap a button instead.';

  @override
  String get voiceFillName => 'Speak';

  @override
  List<String> get satisfactionLabels => const [
        'Not at all',
        'Probably not',
        'Not sure',
        'Yes',
        'Definitely',
      ];

  @override
  String get flavorSpicyMiso => 'Spicy Miso';

  @override
  String get flavorJapaneseCurry => 'Japanese Curry';

  @override
  String get flavorSeafood => 'Seafood';

  @override
  String get flavorUndecided => "Haven't decided yet";

  @override
  String get howHeardSns => 'Social media';

  @override
  String get howHeardReferral => 'A friend told me';

  @override
  String get howHeardWalkedBy => 'Just walked by';

  @override
  String get howHeardOther => 'Other';

  @override
  String get completionTitle => 'Thank you!';

  @override
  String get completionShowStaff => 'Please show this code to a staff member';

  @override
  String get close => 'Close';
}
