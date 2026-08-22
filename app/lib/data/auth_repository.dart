import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';

/// 認証状態から決まる行き先。
enum AuthDestination {
  /// 未認証。サインイン画面を出す。
  signIn,

  /// 認証済み。ホームを出す。
  home,
}

/// セッションの有無から、表示すべき画面を決める。
///
/// UI にも `BuildContext` にも依存しない純関数。単体テストの対象（NFR-QUAL-01）。
///
/// 引数を `Session?` のままにした理由。
/// `Session` はテストから素直に組み立てられる（`accessToken` / `tokenType` /
/// `User` の3つで足りる）。`bool` へ落とす必要が無いため落とさない。
///
/// 期限切れのセッションを別扱いしない理由。
/// `supabase_flutter` が期限前にトークンを自動更新する。更新に失敗したときは
/// `signedOut` を流して `session` を `null` にする。
/// つまりアプリに「期限切れのまま残ったセッション」は届かない。
/// アプリ側は**あるか無いか**だけを見れば足りる。
/// ここで `session.isExpired` を見ると、自動更新の最中に一瞬だけサインイン画面へ
/// 落ちる誤検知を自分で作ることになる。見ない。
AuthDestination resolveDestination(Session? session) =>
    session == null ? AuthDestination.signIn : AuthDestination.home;

/// OAuth の戻り先。
///
/// カスタムURLスキームでアプリへ戻す。
/// iOS 側の登録先は `ios/Runner/Info.plist` の `CFBundleURLTypes`。
/// **スキームを変えるときは両方を直すこと。**
const _oauthRedirectUrl = 'jp.co.classlab.okadafit://login-callback/';

/// 認証の入口。サインイン・サインアウト・認証状態の監視を持つ。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 例外は写像せずそのまま上へ投げる。利用者向け文言への変換は
/// W-05（共通エラー処理・`07_実装共通設計パターン.md §1`）の担当。
class AuthRepository {
  /// [client] を渡さない場合は初期化済みの共有クライアントを使う。
  /// テストから差し替えられるよう引数に開けてある。
  AuthRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 認証状態の変化。購読は `StreamBuilder` で行う（ポーリングしない）。
  ///
  /// 実体は `ReplaySubject` のため、購読が遅れても起動時の
  /// `initialSession` を取りこぼさない。
  /// 通信断のときはストリームにエラーが流れる。購読側で受けること。
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// いま保持しているセッション。無ければ `null`。
  Session? get currentSession => _client.auth.currentSession;

  /// いまサインインしている利用者。無ければ `null`。
  User? get currentUser => _client.auth.currentUser;

  /// Google が返した表示名。
  ///
  /// 読む順は DB トリガ `handle_new_user` と同じ（ADR-0023）。
  /// **表示名の正本は `users.name`**（FEAT-06）であり、ここの値は初期値にすぎない。
  /// DB から読む実装は W-06 以降で入る。
  String? get displayName {
    final metadata = currentUser?.userMetadata;
    if (metadata == null) return null;
    for (final key in ['full_name', 'name', 'email']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// Google でサインインする（ADR-0023）。他の方式は持たない。
  ///
  /// この関数が正常に返っても、それは**ブラウザが開いた**ところまでを意味する。
  /// セッションが載るのは戻りのディープリンクを受けた後で、
  /// 完了の通知は [authStateChanges] から届く。
  ///
  /// 前提は iOS / Android（ADR-0010 で iOS 先行）。Web は対象外。
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirectUrl,
    );
  }

  /// サインアウトする。端末に保持したセッションも消える。
  Future<void> signOut() => _client.auth.signOut();
}
