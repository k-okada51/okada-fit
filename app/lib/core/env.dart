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
}
