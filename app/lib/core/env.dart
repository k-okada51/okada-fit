/// 接続先の設定値。
///
/// 値はソースに埋め込まず、ビルド時に `--dart-define` で渡す。
/// 例: `flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co ...`
///
/// 反復入力を避けるなら `--dart-define-from-file=env/dev.json` を使う
/// （`env/` は gitignore 対象）。
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// 公開鍵。クライアントに埋め込んでよい値で、保護は RLS が担う。
  /// 旧称は anon key。SDK が `publishableKey` へ移行したため名称を合わせる。
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Google ログインの iOS 用クライアントID（ADR-0023）。
  /// `google_sign_in` の初期化に渡す。公開値であり秘密ではない。
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Google ログインのウェブ用クライアントID（ADR-0023）。
  /// ID トークンの audience になり、Supabase 側が同じ値で検証する。
  /// 公開値であり秘密ではない。
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// 未設定のまま起動すると Supabase の初期化が不可解なエラーになるため、
  /// 起動時点で落として原因を明示する。
  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY が未設定です。'
        '--dart-define または --dart-define-from-file で渡してください。',
      );
    }
  }

  /// Google ログインの設定値を検査する。狙いは [assertConfigured] と同じ。
  ///
  /// 検査を分けてある理由。
  /// Supabase への疎通だけを見るテストに、Google のクライアントIDまで
  /// 要求したくないため。アプリ本体（`main.dart`）は両方を呼ぶ。
  static void assertGoogleConfigured() {
    if (googleIosClientId.isEmpty || googleWebClientId.isEmpty) {
      throw StateError(
        'GOOGLE_IOS_CLIENT_ID / GOOGLE_WEB_CLIENT_ID が未設定です。'
        'Google Cloud Console で発行したクライアントIDを '
        '--dart-define または --dart-define-from-file で渡してください。',
      );
    }
  }
}
