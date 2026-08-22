import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:okada_fit/data/error_mapper.dart';

/// 共通エラー処理（W-05）の単体テスト。
///
/// ネットワークを使わない。Supabase の初期化もしない。
/// 例外を手で組み立て、写像の結果だけを見る。

/// 利用者向け文言に技術詳細が混ざっていないことを確かめる。
///
/// 設計（`07_実装共通設計パターン.md §1`）にこうある。
/// > システムエラーの利用者向けメッセージは**定型文のみ**。
/// > 例外メッセージ・SQL・モデル名を転記しない。
void expectNoLeak(AppFailure failure, List<String> forbidden) {
  for (final fragment in forbidden) {
    expect(
      failure.message.contains(fragment),
      isFalse,
      reason: '「$fragment」が利用者向け文言に混ざっている: ${failure.message}',
    );
  }
}

void main() {
  test('1. SQLSTATE 42501（RLS 拒否）は ERR-AUTH-001 になる', () {
    // 認証済みなら 403、未認証なら 401 で返る。写像先はどちらも同じ。
    final failure = mapError(
      const PostgrestException(
        message: 'permission denied for table training_menus',
        code: '42501',
      ),
    );

    expect(failure.code, 'ERR-AUTH-001');
    // 再サインインするまで通らない。手動再試行に意味が無い（§4 リトライ非対象）。
    expect(failure.retryable, isFalse);
  });

  test('2. SQLSTATE 23503（FK 違反）は業務エラーとして扱う。500 に落とさない', () {
    // 履歴のある種目は物理削除できない（ON DELETE NO ACTION・ADR-0006）。
    // 「使用中で削除できません」という予見可能な失敗であり、想定外の例外ではない。
    final failure = mapError(
      const PostgrestException(
        message:
            'update or delete on table "training_menus" violates foreign key '
            'constraint "training_session_details_menu_id_fkey"',
        code: '23503',
      ),
    );

    // 業務エラーの既定 ERR に収まる。想定外（ERR-UNKNOWN-001）へ落ちていない。
    expect(failure.code, 'ERR-VALIDATION-001');
    expect(failure.code, isNot(errUnknown.code));
    expect(failure.message, isNot(errUnknown.message));
    expect(failure.retryable, isFalse);

    // HTTP も 500 ではない。**409 が正しい**（§1 の写像表・2026-08-08 確定）。
    expect(httpStatusForSqlState('23503'), 409);
  });

  test('3. PTxyz は 3桁がそのまま HTTP ステータスになる', () {
    // PostgREST の規約。RPC が errcode で指定した独自コードに使う（FEAT-05）。
    expect(httpStatusForSqlState('PT409'), 409);
    expect(httpStatusForSqlState('PT400'), 400);
    expect(httpStatusForSqlState('PT500'), 500);

    // UNIQUE 違反も 409。FK 違反（テスト2）と同じ。
    expect(httpStatusForSqlState('23505'), 409);

    // 一意に決まらないものは null。
    // 42501 は認証済みかで 401 / 403 に分かれる。23514 は公式に記載が無い（`[仮]`）。
    expect(httpStatusForSqlState('42501'), isNull);
    expect(httpStatusForSqlState('23514'), isNull);
    expect(httpStatusForSqlState('PT40'), isNull, reason: '3桁でないものを拾わない');
    expect(httpStatusForSqlState(null), isNull);
  });

  test('4. FunctionException は本文の retryable がそのまま通る', () {
    // Edge Function は共通契約 { error_code, message, retryable } を返す
    // （`02_API設計.md §5`）。Flutter 側で判断し直さない。

    // (a) レート制限。時間をおけば通る。
    final rate = mapError(
      const FunctionsHttpException(
        status: 429,
        details: {
          'error_code': 'ERR-AI-RATE',
          'message': '混み合っています。時間をおいて、もう一度お試しください。',
          'retryable': true,
        },
      ),
    );
    expect(rate.code, 'ERR-AI-RATE');
    expect(rate.retryable, isTrue);
    expect(rate.message, '混み合っています。時間をおいて、もう一度お試しください。');

    // (b) タイムアウト。**false のまま通す。**
    // 再送は EXT-01 への二重課金になるため（§4 リトライ非対象）。
    // ここで true に持ち上げると UI に再試行ボタンが出てしまう。
    final timeout = mapError(
      const FunctionsHttpException(
        status: 504,
        details: {
          'error_code': 'ERR-AI-TIMEOUT',
          'message': '解析が時間内に終わりませんでした。',
          'retryable': false,
        },
      ),
    );
    expect(timeout.code, 'ERR-AI-TIMEOUT');
    expect(timeout.retryable, isFalse);

    // (c) retryable が欠けている本文。false に倒す。
    // 既定で再試行させない側にする（二重課金を招かない方向）。
    final broken = mapError(
      const FunctionsHttpException(
        status: 500,
        details: {'error_code': 'ERR-AI-FAIL', 'message': '解析できませんでした。'},
      ),
    );
    expect(broken.code, 'ERR-AI-FAIL');
    expect(broken.retryable, isFalse);
  });

  test('5. 未知の例外は定型文になる', () {
    // 写像先が決まらない例外。中身は一切見せない。
    final failure = mapError(StateError('GEMINI_API_KEY=sk-live-abc が不正です'));

    expect(failure.code, errNetwork.code);
    expect(failure.message, errNetwork.message);
    expectNoLeak(failure, ['GEMINI_API_KEY', 'sk-live-abc', 'StateError']);

    // 通信断も同じ扱い。応答が届く前に落ちるため本文が無い。
    final fetchFailed = mapError(
      const FunctionsFetchException(details: 'SocketException: Failed host lookup'),
    );
    expect(fetchFailed.message, errNetwork.message);
    expectNoLeak(fetchFailed, ['SocketException', 'Failed host lookup']);
  });

  test('6. 例外メッセージ・SQL・モデル名が利用者向け文言に混ざらない', () {
    // 共通契約に沿う本文だけは、Edge Function が作った利用者向け文言として
    // そのまま採用する（テスト4）。ここで見るのは**それ以外の全経路**である。
    final cases = <String, (Object, List<String>)>{
      'PostgREST（テーブル名・SQL）': (
        const PostgrestException(
          message: 'relation "secret_table" does not exist',
          code: '42P01',
          details: 'SELECT * FROM secret_table WHERE user_id = \$1',
          hint: 'Perhaps you meant to reference the table "public.foods".',
        ),
        ['secret_table', 'relation', 'SELECT', 'foods', '42P01'],
      ),
      'PostgREST（制約名・キー値）': (
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
          details: 'Key (name)=(サラダチキン) already exists.',
          hint: null,
        ),
        ['unique constraint', 'Key (name)', '23505', 'duplicate'],
      ),
      'Edge Function（契約外の本文・HTML）': (
        const FunctionsHttpException(
          status: 500,
          details:
              '<html><body>TypeError: Cannot read properties of undefined '
              'at /srv/functions/analyze-meal/index.ts:42</body></html>',
          reasonPhrase: 'Internal Server Error',
        ),
        ['html', 'TypeError', 'index.ts', '/srv/functions'],
      ),
      'Edge Function（契約外の本文・モデルID）': (
        const FunctionsHttpException(
          status: 502,
          details: {'error': 'gemini-3.5-flash returned an invalid schema'},
        ),
        ['gemini-3.5-flash', 'schema', 'error'],
      ),
      'Auth（JWT の詳細）': (
        const AuthException(
          'invalid JWT: unable to parse or verify signature, token is expired '
          'by 3h0m0s',
          statusCode: '401',
          code: 'bad_jwt',
        ),
        ['JWT', 'signature', 'bad_jwt', '401'],
      ),
      'その他（環境変数の値）': (
        StateError('SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx が不正です'),
        ['SUPABASE_PUBLISHABLE_KEY', 'sb_publishable_xxx'],
      ),
    };

    cases.forEach((label, testCase) {
      final (error, forbidden) = testCase;
      final failure = mapError(error);

      expect(failure.code.startsWith('ERR-'), isTrue, reason: '$label: ERR-ID でない');
      expect(failure.message, isNotEmpty, reason: '$label: 文言が空');
      expectNoLeak(failure, forbidden);
    });
  });
}
