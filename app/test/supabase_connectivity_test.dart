@Timeout(Duration(minutes: 2))
// 実接続を伴うため既定の `flutter test` からは外す（`dart_test.yaml`）。
@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
// コア SDK（package:supabase）は supabase_flutter が再エクスポートしている。
// 直接 import すると依存に無い扱いになる（depend_on_referenced_packages）ため
// こちら経由で取る。使う型はコア SDK のものだけで、プラグイン層は初期化しない。
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:okada_fit/core/env.dart';

/// Supabase への疎通確認。
///
/// 実行:
///   flutter test test/supabase_connectivity_test.dart \
///     --dart-define-from-file=env/local.json
///
/// ローカルスタック（supabase start）が起動している必要がある。
/// Flutter のプラグイン層（セッション永続化）は使わず、コア SDK だけで
/// 「アプリ → PostgREST → RLS → トリガ」の経路を確かめる。
/// テスト用のクライアントを作る。
///
/// 既定の PKCE フローは認証コードの保管先（asyncStorage）を要求するが、
/// これは Flutter プラグイン層が用意するもの。ここではコア SDK だけを見たいので
/// implicit フローにする。アプリ本体（main.dart）は PKCE のままでよい。
SupabaseClient _newClient() => SupabaseClient(
      Env.supabaseUrl,
      Env.supabasePublishableKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );

void main() {
  late SupabaseClient client;
  late String email;

  setUpAll(() {
    Env.assertConfigured();
    client = _newClient();
    // 実行ごとに別ユーザーを作る。テスト間で状態を持ち越さないため
    email = 'conn-check-${DateTime.now().microsecondsSinceEpoch}@example.test';
  });

  tearDownAll(() async {
    await client.dispose();
  });

  test('1. サインアップできる', () async {
    final res = await client.auth.signUp(
      email: email,
      password: 'test-password-1234',
      data: {'name': '疎通確認ユーザー'},
    );

    expect(res.user, isNotNull, reason: 'auth.users に行ができていない');
    expect(res.session, isNotNull,
        reason: 'セッションが返らない。メール確認が有効になっている可能性');
  });

  test('2. トリガで users 行が自動生成される', () async {
    final userId = client.auth.currentUser!.id;

    final row = await client
        .from('users')
        .select('id, name, target_training_count, weight_kg')
        .eq('id', userId)
        .maybeSingle();

    expect(row, isNotNull,
        reason: 'handle_new_user() トリガが users 行を作っていない');
    expect(row!['id'], userId, reason: 'users.id が auth.uid() と一致しない');
    // signUp の data が raw_user_meta_data 経由で name に入る
    expect(row['name'], '疎通確認ユーザー');
    // 初期設定前なので未入力
    expect(row['target_training_count'], isNull);
    expect(row['weight_kg'], isNull);
  });

  test('3. 本人の行を更新できる（RLS 区分1: 本人のみ）', () async {
    final userId = client.auth.currentUser!.id;

    final updated = await client
        .from('users')
        .update({'weight_kg': 70.5, 'target_training_count': 12})
        .eq('id', userId)
        .select()
        .single();

    expect(updated['weight_kg'], 70.5);
    expect(updated['target_training_count'], 12);
  });

  test('4. CHECK 制約が効く（weight_kg > 0）', () async {
    final userId = client.auth.currentUser!.id;

    await expectLater(
      client.from('users').update({'weight_kg': -1}).eq('id', userId),
      throwsA(isA<PostgrestException>()),
      reason: 'ck_users_weight_kg が効いていない',
    );
  });

  test('5. 共通マスタに書き込める（RLS 区分2）', () async {
    final gym = await client
        .from('gyms')
        .insert({'name': '疎通確認ジム'})
        .select()
        .single();

    expect(gym['id'], isNotNull);

    final machine = await client
        .from('training_machines')
        .insert({'gym_id': gym['id'], 'name': '疎通確認マシン'})
        .select()
        .single();

    expect(machine['gym_id'], gym['id']);
  });

  test('6. 本人所有データを作れる（training_menus）', () async {
    final userId = client.auth.currentUser!.id;

    final menu = await client
        .from('training_menus')
        .insert({'user_id': userId, 'name': 'ベンチプレス', 'body_part': '胸'})
        .select()
        .single();

    expect(menu['body_part'], '胸');
  });

  test('7. enum の CHECK が効く（body_part）', () async {
    final userId = client.auth.currentUser!.id;

    await expectLater(
      client
          .from('training_menus')
          .insert({'user_id': userId, 'name': '不正部位', 'body_part': '腹筋'}),
      throwsA(isA<PostgrestException>()),
      reason: 'ck_training_menus_body_part が効いていない',
    );
  });

  test('8. 他人の行は見えない（RLS 本人分離）', () async {
    // 別ユーザーを作り、その視点で最初のユーザーの行が見えないことを確かめる
    final other = _newClient();
    addTearDown(other.dispose);

    final firstUserId = client.auth.currentUser!.id;

    await other.auth.signUp(
      email: 'conn-check-other-${DateTime.now().microsecondsSinceEpoch}@example.test',
      password: 'test-password-1234',
      data: {'name': '別ユーザー'},
    );

    final rows = await other.from('users').select('id');
    final ids = rows.map((r) => r['id']).toList();

    expect(ids, isNot(contains(firstUserId)),
        reason: '他人の users 行が見えている。RLS が機能していない');
    expect(ids.length, 1, reason: '自分の行だけが見えるはず');
  });

  test('9. 未認証では読めない（anon には権限を与えない）', () async {
    final anonymous = _newClient();
    addTearDown(anonymous.dispose);

    // 空配列ではなく権限エラーになるのが正しい。RLS の手前、
    // テーブルへの GRANT の段階で anon が弾かれる（NFR-SEC-01）
    await expectLater(
      anonymous.from('users').select('id'),
      throwsA(
        isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
      ),
      reason: 'anon から users が読めてしまっている',
    );
  });
}
