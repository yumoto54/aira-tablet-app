// kApiFunctionKey (Azure Functionsの認証キー) は秘密情報なので、
// gitには含めない api_secrets.dart の方に書く。
// このファイルを初めて開く人は api_secrets.example.dart をコピーして
// api_secrets.dart を作り、実際のキーを入れてください。
export 'api_secrets.dart';

/// バックエンド(freedom-ramen-avatar-backend)のベースURL。
///
/// Azure Functions (freedom-ramen-aira-backend) にデプロイ済みのものを指す。
/// 会場PCの有無に関係なく動くよう、ローカルPCのLAN IPではなくこのURLを使う。
const String kApiBaseUrl =
    'https://freedom-ramen-aira-backend-dvhgffckgfffebes.westus3-01.azurewebsites.net';
