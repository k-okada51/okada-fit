import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
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

/// Google に求めるスコープ。
///
/// 認証（本人確認）だけが目的で、Google の API は叩かない。
/// `authenticate()` が返す ID トークンには既に含まれるが、
/// アクセストークンを得るには明示が要る（7.x で認証と認可が分かれたため）。
const _googleScopes = <String>['email', 'profile'];

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

  /// Google のサインインSDKを初期化する。
  ///
  /// `google_sign_in` 7.x は `initialize()` を**起動時にちょうど1回**呼ぶ決まりで、
  /// 2回呼ぶと動作が未定義になる。呼ぶのは `main()` だけにすること。
  ///
  /// `GoogleSignIn` はシングルトン（コンストラクタが非公開）のため差し替えできない。
  /// テストから触らせないよう、ここは静的メソッドとして分けてある。
  static Future<void> initializeGoogleSignIn() {
    // nonce を起動ごとに1つ作る。
    //
    // 使い分けに注意。**同じ値を渡すと通らない**。
    //   Google  … SHA-256 でハッシュした値
    //   Supabase… ハッシュ前の生の値
    // Supabase は受け取った生の値をハッシュし、ID トークン内の nonce と比べる。
    //
    // nonce を渡さないと 400 になる（2026-08-22 実機で確認）。
    //   "Passed nonce and nonce in id_token should either both exist or not."
    // google_sign_in 7.x が ID トークンに nonce を埋めるためで、
    // Supabase 側にも同じものを渡さないと「片方だけある」と判定される。
    //
    // 起動ごとに1つで足りる理由。
    // authenticate() は nonce を受け取らず、initialize() でしか渡せない。
    // 目的は「このアプリの起動が要求したトークンか」を確かめることなので、
    // 起動単位で固定されていれば足りる。
    _rawNonce = _generateNonce();
    return GoogleSignIn.instance.initialize(
      // iOS 用クライアントID。ネイティブのログイン画面がこれで自分を名乗る。
      clientId: Env.googleIosClientId,
      // ウェブ用クライアントID。ID トークンの audience になり、
      // Supabase 側が同じ値で検証する。どちらか欠けると通らない。
      serverClientId: Env.googleWebClientId,
      // Google にはハッシュ済みを渡す。生の値は外へ出さない。
      nonce: sha256.convert(utf8.encode(_rawNonce!)).toString(),
    );
  }

  /// ハッシュ前の nonce。Supabase へはこちらを渡す。
  static String? _rawNonce;

  /// 推測されにくい nonce を作る。
  ///
  /// `Random.secure()` を使う。`Random()` は予測可能で、nonce の意味が消える。
  static String _generateNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }

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
  /// ネイティブのログイン画面で ID トークンを取り、それを Supabase に渡す。
  /// 外部ブラウザを開かないため、アプリ内で完結する。
  ///
  /// 戻った時点でセッションは載っている。画面の切り替えは
  /// [authStateChanges] を購読している `AuthGate` が行う。
  ///
  /// 失敗時は例外がそのまま上がる（`GoogleSignInException` ／ `AuthException`）。
  /// 利用者が選択をキャンセルした場合も例外になる。
  Future<void> signInWithGoogle() async {
    // 1. ネイティブのログイン画面を出す。失敗・キャンセルは例外になる。
    final account = await GoogleSignIn.instance.authenticate(
      // 認可も続けて行うことを伝える。対応しない環境では黙って無視される。
      scopeHint: _googleScopes,
    );

    // 2. ID トークン（本人確認の材料）。Supabase に渡す本体はこれ。
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google から ID トークンが返らなかった');
    }

    // 3. アクセストークン。7.x では認証（authentication）と認可（authorization）が
    //    分かれたため別に取る。まず同意済みか確認し、無ければ同意を求める。
    final authorization =
        await account.authorizationClient.authorizationForScopes(
          _googleScopes,
        ) ??
        await account.authorizationClient.authorizeScopes(_googleScopes);

    // 4. Supabase にトークンを渡してセッションを作る。
    //    成功すると supabase_flutter が端末に保持し、以後は自動更新する。
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
      // ハッシュ前の値を渡す。Supabase 側でハッシュして
      // ID トークン内の nonce と突き合わせる（initializeGoogleSignIn を参照）。
      nonce: _rawNonce,
    );
  }

  /// サインアウトする。端末に保持したセッションも消える。
  ///
  /// Supabase 側を先に落とす。Google 側で失敗しても、
  /// アプリのセッションは確実に消えている状態にするため。
  Future<void> signOut() async {
    await _client.auth.signOut();
    // Google 側も落とす。残すと次回サインイン時にアカウント選択が出ない。
    await GoogleSignIn.instance.signOut();
  }
}
