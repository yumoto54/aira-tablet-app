// kApiFunctionKey (Azure Functionsの認証キー) は秘密情報なので、
// gitには含めない api_secrets.dart の方に書く。
// このファイルを初めて開く人は api_secrets.example.dart をコピーして
// api_secrets.dart を作り、実際のキーを入れてください。
export 'api_secrets.dart';

/// このタブレットの名前。ダッシュボードの「タブレットの稼働状況」に出る。
/// ビルド時に指定する: flutter run --release -d <端末ID> --dart-define=DEVICE_ID=tablet-3
/// 指定し忘れると、複数台が同じ名前になって区別できなくなるので必ず指定すること。
const String kDeviceId =
    String.fromEnvironment('DEVICE_ID', defaultValue: 'tablet-unknown');

/// ダッシュボードに表示するアプリの版。アプリを更新したら上げる。
const String kAppVersion = '0.2.2';

/// 稼働状況を送る間隔。
const Duration kHeartbeatInterval = Duration(seconds: 60);

/// バックエンド(freedom-ramen-avatar-backend)のベースURL。
///
/// Azure Functions (freedom-ramen-aira-backend) にデプロイ済みのものを指す。
/// 会場PCの有無に関係なく動くよう、ローカルPCのLAN IPではなくこのURLを使う。
const String kApiBaseUrl =
    'https://freedom-ramen-aira-backend-dvhgffckgfffebes.westus3-01.azurewebsites.net';

/// アバターの絵柄。'photo'(実写風・既定)、'anime'(アニメ風)、'male'(男性・ハギワラ用)。
/// 'male' は絵柄が1つだけなので、画面の絵柄切り替えボタンは出さない。
/// ビルド時に指定する: flutter run --release -d <端末ID> --dart-define=AVATAR_STYLE=anime
/// 指定しなければ従来どおり実写風になる。
/// どのクライアント(テナント)として動かすか。ビルド時に --dart-define=TENANT_ID=hagiwara のように指定する。
/// 未指定(空)なら、サーバー側で従来どおりフリーダムラーメンとして扱われる。
const String kTenantId = String.fromEnvironment('TENANT_ID');

const String kAvatarStyle =
    String.fromEnvironment('AVATAR_STYLE', defaultValue: 'photo');

/// 絵柄名から、画像フォルダを返す。
String avatarAssetDirFor(String style) => switch (style) {
      'anime' => 'assets/avatar_anime',
      'male' => 'assets/avatar_male',
      _ => 'assets/avatar',
    };

String get kAvatarAssetDir => avatarAssetDirFor(kAvatarStyle);
