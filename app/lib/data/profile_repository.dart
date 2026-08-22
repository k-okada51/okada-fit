import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/profile.dart';

/// `users` の本人1行の読み書き（FEAT-06）。
///
/// **PostgREST を直接叩く。** RPC も Edge Function も挟まない
/// （FEAT-06 §1・`02_API設計.md §3`）。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 例外は写像せずそのまま上へ投げる。利用者向け文言への変換は
/// `data/error_mapper.dart`（W-05）の担当で、呼ぶのは画面側。
/// `auth_repository.dart` と同じ約束にしてある。
class ProfileRepository {
  /// [client] を渡さない場合は初期化済みの共有クライアントを使う。
  /// テストから差し替えられるよう引数に開けてある。
  ProfileRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 読み書きで扱う列。**3列＋PK だけ**。`created_at` は使わないので取らない。
  static const _columns = 'id, name, target_training_count, weight_kg';

  /// 本人のプロフィールを1件読む。
  ///
  /// **`id` を条件に書かない。** 行を本人に絞るのは RLS の `p_users_self`
  /// （`USING (id = auth.uid())`・ADR-0005）であり、ここに条件を足すと
  /// 同じ絞り込みが2か所に散る。JWT は `supabase_flutter` が自動で付ける
  /// （ADR-0004）。未サインインなら RLS が0行にする。
  ///
  /// 失敗すると例外が上がる。
  /// - 0行 … `PostgrestException(PGRST116)`（トリガで行が作られていない＝異常）
  /// - 権限 … `PostgrestException(42501)` → `error_mapper` が ERR-AUTH-001 にする
  Future<Profile> fetchProfile() async {
    final row = await _client.from('users').select(_columns).single();
    return Profile.fromJson(row);
  }

  /// 本人のプロフィールを更新し、更新後の行を返す。
  ///
  /// 指定しなかった列は変わらない（部分更新・FEAT-06 §4.3）。
  /// 対象行の特定は [fetchProfile] と同じく RLS に任せる。
  ///
  /// [patch] が空になる場合は呼ばない。空で呼ぶと PostgREST が全列そのままの
  /// 更新を投げることになり、意味が無い。判断は呼び出し側（画面）で行う。
  Future<Profile> updateProfile(ProfileUpdate input) async {
    final patch = buildProfileUpdate(input);
    // 変更が無いのに往復させない。ERR-PROFILE-005 に当たる状況だが、
    // 画面は3列とも常に送るため、ここへ来るのは実装の誤りである。
    if (patch.isEmpty) {
      throw ArgumentError.value(input, 'input', '更新する項目がありません');
    }

    final row = await _client
        .from('users')
        .update(patch)
        // 更新した行をそのまま受け取る。トリム結果を画面へ返すため
        // （FEAT-06 §7 の「値を応答値で置き換える」）。
        .select(_columns)
        .single();
    return Profile.fromJson(row);
  }
}
