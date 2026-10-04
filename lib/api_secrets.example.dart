/// api_secrets.dart のテンプレート。
///
/// 使い方:
/// 1. このファイルを lib/api_secrets.dart としてコピーする
/// 2. 下の値を、Azure Portal → Function App (freedom-ramen-aira-backend)
///    → 左メニュー「関数」→「アプリ キー」→ `default` の「値の表示」で
///    得られる文字列に置き換える
///
/// lib/api_secrets.dart は.gitignoreで除外されているので、間違って
/// GitHubにキーが上がる心配はありません。
const String kApiFunctionKey = 'PASTE_HOST_KEY_HERE';
