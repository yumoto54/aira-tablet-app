/// 音声認識の結果を選択肢に対応づける。
///
/// 単純な部分一致は使わない。英語では "other" が "brother" に、
/// 日本語では数詞の「に」が助詞の「に」に当たってしまい、
/// 来場者が言っていない選択肢を勝手に選んでしまうため。
///
/// 対応づけに自信が持てないとき(どれにも当たらない/複数に当たる)は null を返す。
/// 呼び出し側はボタンでの選択を促す。
library;

/// 記号を空白に置き換えて小文字化した形。英単語の語境界判定に使う。
String _spaced(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'''[.,!?;:"'（）()、。！？・…]'''), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 空白を取り除き全角数字を半角に寄せた形。日本語の判定に使う。
String _compact(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    // 全角の０-９を半角に寄せる
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buffer.writeCharCode(rune - 0xFF10 + 0x30);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'''[\s.,!?;:"'（）()、。！？・…]'''), '');
}

bool _isAsciiOnly(String value) {
  return value.runes.every((rune) => rune < 0x80);
}

RegExp _asciiWordPattern(String keyword) {
  final words = keyword
      .trim()
      .split(RegExp(r'\s+'))
      .map(RegExp.escape)
      .join(r'\s+');
  return RegExp('\\b$words\\b', caseSensitive: false);
}

bool _keywordMatches(String keyword, String spaced, String compact) {
  if (_isAsciiOnly(keyword)) {
    return _asciiWordPattern(keyword).hasMatch(spaced);
  }
  return compact.contains(_compact(keyword));
}

/// 発話をいずれかの選択肢に対応づける。
///
/// ちょうど1つに絞れたときだけ値を返す。0個でも2個以上でも null を返して、
/// 聞き間違いのまま先に進まないようにする。
T? matchSpokenChoice<T>(String spoken, Map<T, List<String>> keywords) {
  if (spoken.trim().isEmpty) return null;

  final spaced = _spaced(spoken);
  final compact = _compact(spoken);

  final matched = <T>{};
  keywords.forEach((option, optionKeywords) {
    for (final keyword in optionKeywords) {
      if (_keywordMatches(keyword, spaced, compact)) {
        matched.add(option);
        break;
      }
    }
  });

  return matched.length == 1 ? matched.first : null;
}

const Map<String, int> _englishNumberWords = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
};

const Map<String, int> _japaneseNumberWords = {
  'いち': 1,
  '一': 1,
  'ひとつ': 1,
  'に': 2,
  '二': 2,
  'ふたつ': 2,
  'さん': 3,
  '三': 3,
  'みっつ': 3,
  'よん': 4,
  'し': 4,
  '四': 4,
  'よっつ': 4,
  'ご': 5,
  '五': 5,
  'いつつ': 5,
};

const List<String> _japaneseTrailers = [
  'ですね',
  'です',
  'かな',
  'だと思います',
  'と思います',
  'くらい',
  'ぐらい',
  'てん',
  '点',
  '番',
  'ばん',
];

String _stripJapaneseTrailers(String compact) {
  var result = compact;
  var changed = true;
  while (changed) {
    changed = false;
    for (final trailer in _japaneseTrailers) {
      if (result.length > trailer.length && result.endsWith(trailer)) {
        result = result.substring(0, result.length - trailer.length);
        changed = true;
      }
    }
  }
  return result;
}

/// 発話から1〜5の評価を取り出す。判断できなければ null。
int? matchSpokenRating(String spoken) {
  if (spoken.trim().isEmpty) return null;

  final spaced = _spaced(spoken);
  final compact = _compact(spoken);

  // ① 数字が出ていればそれを最優先する。2種類以上あるときは選べない。
  final digits = RegExp(r'[1-5]')
      .allMatches(compact)
      .map((match) => match.group(0)!)
      .toSet();
  if (digits.length > 1) return null;
  if (digits.length == 1) return int.parse(digits.first);

  // ② 英語の数詞は語境界で判定する。
  final englishMatches = <int>{};
  _englishNumberWords.forEach((word, value) {
    if (_asciiWordPattern(word).hasMatch(spaced)) {
      englishMatches.add(value);
    }
  });
  if (englishMatches.length > 1) return null;
  if (englishMatches.length == 1) return englishMatches.first;

  // ③ 日本語の数詞は助詞と同じ形があるので、文全体が数詞のときだけ採る。
  //    「明日にします」の「に」を2点と読み違えないようにするため。
  final candidates = [compact, _stripJapaneseTrailers(compact)];
  for (final candidate in candidates) {
    final value = _japaneseNumberWords[candidate];
    if (value != null) return value;
  }

  return null;
}
