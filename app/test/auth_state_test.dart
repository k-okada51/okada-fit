import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:okada_fit/data/auth_repository.dart';

/// 認証状態から行き先が決まるロジックの単体テスト。
///
/// ネットワークを使わない。Supabase の初期化もしない。
/// 見るのは `resolveDestination` という純関数1つだけ。

/// `exp` だけを持つ署名なしの JWT。
///
/// `Session.isExpired` は `accessToken` の `exp` を読む。
/// 期限切れを再現するにはこの形が要る。署名は検証されないためダミーでよい。
String _fakeJwt(DateTime expiresAt) {
  String encode(Map<String, dynamic> payload) =>
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  final header = encode({'alg': 'none', 'typ': 'JWT'});
  final body = encode({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000});
  return '$header.$body.dummy-signature';
}

/// テスト用の `Session`。必須なのは3つ（`accessToken` / `tokenType` / `user`）だけ。
Session _session({required DateTime expiresAt}) => Session(
  accessToken: _fakeJwt(expiresAt),
  tokenType: 'bearer',
  user: const User(
    id: '00000000-0000-4000-8000-000000000001',
    appMetadata: {},
    userMetadata: {'full_name': 'テスト利用者'},
    aud: 'authenticated',
    createdAt: '2026-08-22T00:00:00.000Z',
  ),
);

void main() {
  final now = DateTime.now();

  test('1. セッションが無ければサインイン画面へ', () {
    expect(resolveDestination(null), AuthDestination.signIn);
  });

  test('2. セッションがあればホームへ', () {
    final session = _session(expiresAt: now.add(const Duration(hours: 1)));

    expect(resolveDestination(session), AuthDestination.home);
  });

  test('3. 期限切れのセッションでもホームへ（更新は SDK の担当）', () {
    final session = _session(expiresAt: now.subtract(const Duration(hours: 1)));

    // 前提の確認。この Session は確かに期限切れである。
    expect(session.isExpired, isTrue, reason: '期限切れを再現できていない');

    // 期待は「ホームへ」。サインイン画面へは戻さない。
    //
    // 理由。`supabase_flutter` が期限前にトークンを自動更新する。
    // 更新に失敗したときだけ `signedOut` が流れ、`session` が `null` になる。
    // つまり「期限切れのまま残ったセッション」はアプリの判断材料にならない。
    // アプリ側は **あるか無いか** だけを見れば足りる。
    //
    // ここで `isExpired` を見て signIn に落とすと、自動更新の最中に一瞬だけ
    // サインイン画面が出る誤検知を自分で作ることになる。だから見ない。
    expect(resolveDestination(session), AuthDestination.home);
  });
}
