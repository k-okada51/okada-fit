import 'package:supabase_flutter/supabase_flutter.dart';

/// 利用者に見せる失敗の表現。
///
/// Flutter 側のエラー表現の正本（`07_実装共通設計パターン.md §1`）。
/// Edge Function 側の `AppError`（`supabase/functions/_shared/errors.ts`）と対になる。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 画面への出し方は `ui/error_snack_bar.dart` の担当。
class AppFailure {
  const AppFailure({
    required this.code,
    required this.message,
    required this.retryable,
  });

  /// "ERR-..."（ERR-ID）。調査の手掛かりであり、画面には出さない。
  final String code;

  /// 利用者向け日本語。
  ///
  /// **技術詳細を含めない。** 例外メッセージ・SQL・SQLSTATE・制約名・
  /// スタックトレース・モデルID を転記しない（§1）。
  final String message;

  /// 再試行アクションを出すか。
  ///
  /// 意味は「**利用者が手動で再試行する価値があるか**」（§4）。
  /// アプリが自分で投げ直すことを意味しない。
  /// Flutter 側の自動リトライは実装しない。Edge Function 側と二重になり、
  /// AI の課金が掛け算になるため。
  final bool retryable;

  @override
  String toString() =>
      'AppFailure(code: $code, retryable: $retryable, message: $message)';
}

/// 認証の失敗（ERR-AUTH-001）。未認証・JWT 失効・RLS 拒否のいずれもこれ。
///
/// 拒否の理由を利用者に出さない（§1）。行き先はサインイン画面。
const errAuth = AppFailure(
  code: 'ERR-AUTH-001',
  message: 'サインインの状態が切れました。もう一度サインインしてください。',
  retryable: false,
);

/// 業務エラーの既定（ERR-VALIDATION-001）。
///
/// 予見できる失敗に使う。再送しても入力を直すまで通らないため `retryable: false`。
/// 機能固有の ERR（`ERR-MACHINE-*` 等）は各 FEAT の実装時に足す。ここでは作らない。
AppFailure errValidation(String message) =>
    AppFailure(code: 'ERR-VALIDATION-001', message: message, retryable: false);

/// 通信の失敗。写像先が決まらない例外もここへ落ちる（§1 の「その他」）。
///
/// 時間をおけば通る見込みがあるため `retryable: true`。
/// ただし再試行ボタンが実際に出るのは、呼び出し側が `onRetry` を渡したときだけ。
/// 判断は `ui/error_snack_bar.dart` にある。
///
/// ⚠️ ERR-ID は `[仮]`。ERR の完全列挙は
/// `60_テスト設計/02_RED母集合_受入基準・状態・エラー.md`（段6）で確定する。
const errNetwork = AppFailure(
  code: 'ERR-NETWORK-001',
  message: '通信できませんでした。時間をおいて、もう一度お試しください。',
  retryable: true,
);

/// 想定外の失敗。共通契約に沿わない応答もここへ落ちる。
///
/// **`retryable: false` にする理由。** 応答の中身が読めない以上、再送が安全か
/// 判断できない。AI 呼び出し（FEAT-03 / FEAT-08）は非冪等で、再送がそのまま
/// 二重課金になる（§3・§5）。分からないときは押させない側に倒す。
///
/// ⚠️ ERR-ID は `[仮]`。上の [errNetwork] と同じ扱い。
const errUnknown = AppFailure(
  code: 'ERR-UNKNOWN-001',
  message: 'エラーが発生しました。時間をおいて、もう一度お試しください。',
  retryable: false,
);

/// 例外を利用者向けの失敗へ写像する。写像はこの1か所に閉じる（§1）。
///
/// 受けるのは `supabase_flutter` が throw する4種類。
///
/// | 例外 | 出どころ | 写像 |
/// |---|---|---|
/// | `FunctionException` | Edge Function（FEAT-03 / FEAT-08） | 本文の共通契約をそのまま採用 |
/// | `PostgrestException` | PostgREST・RPC 直接 | SQLSTATE で分岐 |
/// | `AuthException` | Supabase Auth | ERR-AUTH-001 |
/// | その他 | 通信 | 通信エラーの定型文 |
AppFailure mapError(Object e) {
  // `FunctionException` を先に見る。通信断（`FunctionsFetchException`）も
  // この型の派生であり、後ろに置くと拾えない。
  if (e is FunctionException) return _fromFunctionException(e);
  if (e is PostgrestException) return _fromPostgrestException(e);
  if (e is AuthException) return errAuth;
  // `SocketException` 等。例外の中身は利用者に出さない（§1）。
  return errNetwork;
}

/// SQLSTATE から、PostgREST が返す HTTP ステータスを求める（§1 の写像表・2026-08-08 確定）。
///
/// 一意に決まらないものは `null` を返す。
/// - `42501` は認証済みなら 403、未認証なら 401 になる。写像先はどちらも ERR-AUTH-001。
/// - `23514`（CHECK 違反）は公式の写像表に記載が無い（`[仮]`）。
///
/// `23503`（FK 違反）が **409** である点に注意する。400 系ではないし、
/// 500 でもない。「使用中で削除できない」という業務エラーである（§2）。
int? httpStatusForSqlState(String? sqlState) {
  if (sqlState == null) return null;
  switch (sqlState) {
    case '23505': // UNIQUE 違反
    case '23503': // FK 違反
      return 409;
  }
  // `PTxyz` は PostgREST の規約。**`PT` に続く3桁がそのまま HTTP ステータスになる。**
  // 例: PT400 → 400 ／ PT409 → 409 ／ PT500 → 500。
  // RPC が `RAISE EXCEPTION ... USING errcode = 'PT409'` と書けば 409 が返る。
  final pt = _ptCode.firstMatch(sqlState);
  if (pt != null) return int.parse(pt.group(1)!);
  return null;
}

/// `PTxyz`（PostgREST の独自コード）の判別。
final _ptCode = RegExp(r'^PT(\d{3})$');

/// Edge Function 経由の失敗（FEAT-03 / FEAT-08）。
AppFailure _fromFunctionException(FunctionException e) {
  // 応答が届く前に落ちた場合は `status` が 0 になる（`FunctionsFetchException`）。
  // 本文が無い。`details` には元の例外が入っているが、利用者には出さない。
  if (e.status == 0) return errNetwork;

  // 本文は `Content-Type: application/json` のとき Map になる。
  final body = e.details;
  if (body is Map) {
    final code = body['error_code'];
    final message = body['message'];
    if (code is String &&
        code.isNotEmpty &&
        message is String &&
        message.isNotEmpty) {
      // 共通契約（`02_API設計.md §5`）に沿う本文。**そのまま採用する。**
      // 文言も `retryable` もここで書き換えない。判断はサーバ側に閉じている。
      //
      // 例: ERR-AI-TIMEOUT(504) は `retryable: false` で返る。
      //     再送は EXT-01 への二重課金になり、NFR-PERF-03/04 の時間予算も
      //     超えるため（§4）。**ここで true に持ち上げない。**
      //     結果として UI にも再試行ボタンが出ない。
      return AppFailure(
        code: code,
        message: message,
        // 欠落・型違いは false に倒す。既定で再試行させない側にする。
        retryable: body['retryable'] == true,
      );
    }
  }

  // 共通契約に沿わない本文（プロキシの HTML・空応答など）。
  // 本文を利用者へ転記しない（§1）。定型文に倒す。
  return errUnknown;
}

/// PostgREST・RPC 直接の失敗（FEAT-01 / 02 / 04 / 05 / 06 / 09 / 10）。
///
/// この経路に Edge Function は挟まらない。共通契約の JSON も来ない。
/// サーバが返すのは PostgREST 形式の `{ code, message, details, hint }` で、
/// **4つとも技術詳細である。** どれも利用者向け文言に転記しない。
AppFailure _fromPostgrestException(PostgrestException e) {
  // `code` に入るのは SQLSTATE か PostgREST 独自コード（`PGRST…`）。
  // 本文が JSON として読めなかったときだけ HTTP ステータスの文字列が入る。
  switch (e.code) {
    case '42501': // 権限不足・RLS 拒否（401 または 403）
    case 'PGRST301': // JWT 失効・未ログイン
      return errAuth;

    case '23505': // UNIQUE 違反（409）
      return errValidation('すでに登録されています。');

    case '23503': // FK 違反（409）。**業務エラー。500 に落とさない**（§2）
      return errValidation('ほかの記録で使われているため、削除できません。');

    case '23514': // CHECK 違反。HTTP は `[仮]`（公式の写像表に記載が無い）
      return errValidation('入力できない値が含まれています。');

    case 'PGRST204': // 更新に未知の列を送った
      return errValidation('この内容は保存できません。');
  }

  // `PTxyz` は RPC が自分で raise した独自コード（FEAT-05 の PT400 / PT409）。
  // 4xx は業務エラーの枠に収める。5xx は想定外として扱う。
  final status = httpStatusForSqlState(e.code);
  if (status != null && status < 500) {
    return errValidation('この操作は行えません。');
  }

  // 機能固有の写像（`PGRST116` の不在・`P0001` の ERR-ID 採用・制約名による
  // FK の切り分け）は各 FEAT の実装時に足す。ここには置かない。
  return errUnknown;
}
