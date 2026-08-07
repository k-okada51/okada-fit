---
status: draft
---

# FEAT-05 ダッシュボード 詳細設計

> **目的**: FEAT-05 を実装が迷わない粒度（入出力・バリデーション・クエリ・エラー・画面挙動・実装単位）まで具体化し、TDDの着手点を固定する。
> **書き方**: 実データは書かない。上位の正本（API契約＝`../../30_データ・IF設計/02_API設計.md` ／ 物理DB＝`../01_DB物理設計.md` ／ シーケンス＝`../../40_機能設計/01_シーケンス設計.md`）と矛盾させず、参照はIDで行う。横断方針（エラー分類・トランザクション・冪等・リトライ）は `../07_実装共通設計パターン.md` を正本とし本書では再定義しない。

> ⚠️ **本書はたたき台（2026-08-02 生成）**。岡田さんのレビューで確定する。

## 目次
1. [概要](#1-概要)
2. [処理フロー](#2-処理フロー)
3. [入出力仕様](#3-入出力仕様)
4. [業務ロジック](#4-業務ロジック)
5. [データアクセス](#5-データアクセス)
6. [エラー処理](#6-エラー処理)
7. [画面挙動・状態別表示](#7-画面挙動状態別表示)
8. [実装単位](#8-実装単位)
9. [テスト観点](#9-テスト観点)
10. [敵対的検証・要確認事項](#10-敵対的検証要確認事項)

## 1. 概要

| 項目 | 内容 |
|---|---|
| 対応要件 | FEAT-05（ダッシュボード表示：タンパク質ゲージ＋トレーニング実施ヒートマップ） |
| 対応画面 | SCR-01 ダッシュボード |
| 対応API | RPC `get_dashboard`（Postgres 関数）。呼び出しは `supabase.rpc('get_dashboard', params: { ... })` |
| 関連ルール | RULE-001（必要量＝体重×2g。**算出ロジックの正本は FEAT-07**、本書では再定義せず共有関数を呼ぶ） |
| 外部連携 | なし（AI不使用。決定的なDB集計のみ） |
| 性能目標 | NFR-PERF-01（初期表示 ≤2秒）／NFR-PERF-02（決定的処理 ≤1秒） |
| 状態 | 本機能は状態を持たない（参照系）。ただし ST-01 `not_done` / ST-02 `done` を**集計対象として読む** |
| 優先度 | MUST |

SCR-01 を開いた時点で、当日のタンパク質達成状況と選択期間のトレーニング実施状況を表示する。取得は RPC 1回。

| 観点 | 方針 |
|---|---|
| 書き込み | 一切しない。読み取り専用 |
| 集計場所 | すべて RPC 内の SQL。Flutter 側で再集計しない |
| 期間切替 | 同じ RPC を `p_period` を変えて呼び直す。表示範囲だけが変わる |
| `period` の意味 | 「表示範囲」のみ。保持範囲ではない（全履歴保持・`../../30_データ・IF設計/01_データモデル.md §7`） |
| 例外 | `target_g` と `rate_pct` だけは Flutter 側で算出する。理由は §10-12 |

- 旧構成の `GET /api/dashboard?period=` は廃止する。
- 段3（`../../30_データ・IF設計/02_API設計.md §4.3`）の契約表は RPC 契約への改訂が要る。

## 2. 処理フロー

`../../40_機能設計/01_シーケンス設計.md §3` を正本とし、本節はそれを **バリデーション位置・日付範囲の解決点・クエリ発行点** まで詳細化する。

```mermaid
sequenceDiagram
  actor U as 岡田さん
  participant F as SCR-01（Flutter）
  participant S as Supabase RPC get_dashboard
  participant D as PostgreSQL（RLS）

  U->>F: SCR-01 を開く／SegmentedButton で期間切替
  F->>F: period を決定（未指定は month）
  F->>F: resolveDateRange(period, now, tz)<br/>→ today / range_start / range_end（案A のみ・§5.1）
  F->>S: supabase.rpc('get_dashboard', params)
  S->>S: JWT を検証（NFR-SEC-01）
  alt 未認証／JWT 無効
    S-->>F: 401
    F->>U: ERR-AUTH-001。ログイン画面へ誘導
  else 認証済
    S->>S: p_period を検証（day/week/month）
    alt enum 外
      S-->>F: raise exception（PT400）
      F->>U: ERR-DASHBOARD-001
    else 妥当
      Note over S,D: 以降は参照のみ。書き込み・明示トランザクションをしない
      S->>D: 本人の users 行を解決（auth.uid() から）
      alt users 行が存在しない
        S-->>F: raise exception（PT409）
        F->>U: ERR-DASHBOARD-002。SCR-05（FEAT-06）へ誘導
      else
        S->>D: Q1 ゲージ集計（users LEFT JOIN meal_logs, eaten_date = p_today）
        D-->>S: weight_kg, intake_g
        S->>D: Q2 ヒートマップ集計（sessions × details × menus を日付で集約）
        D-->>S: date / done / menu_names[] の配列
        S-->>F: json_build_object('protein_gauge', …, 'heatmap', …)
        F->>F: target_g＝RULE-001（FEAT-07 の Dart 関数）／rate_pct＝100%頭打ち
        F->>U: ゲージ ＋ ヒートマップを描画
      end
    end
  end
```

- 往復は**常に1回**。Q1・Q2 は RPC の中で連続実行される。
- クエリは**常に2本以内**（Q1・Q2）。日数やセル数に比例してクエリが増えない（N+1回避は §5）。
- 本人行が無い時点で `raise exception` する。Q1・Q2 とも発行されない（無駄な集計を打ち切る）。

## 3. 入出力仕様

呼び出しは RPC `get_dashboard` の1本のみ。HTTP エンドポイントは持たない。

| 項目 | 内容 |
|---|---|
| 呼び出し | `supabase.rpc('get_dashboard', params: { ... })` |
| 実体 | Postgres 関数 `public.get_dashboard`（`supabase/migrations/*.sql` で版管理） |
| 認証 | 要。JWT は `supabase_flutter` が自動付与（`../../30_データ・IF設計/02_API設計.md §1`） |
| 権限 | `security invoker`。RLS が本人行のみに絞る |
| 冪等性 | 冪等（参照系）。リトライ安全 |
| キャッシュ | しない。呼び出しごとに再集計する（当日値が変わるため） |
| 失敗の返し方 | `raise exception` ＋ `errcode`。PostgREST が HTTP ステータスへ写す（§6） |

### 引数

| 引数 | 型 | 必須 | 内容 |
|---|---|---|---|
| `p_period` | `text` | 任意（既定 `month`） | `day` / `week` / `month`。未指定時は `month`（[仮]・§10-7） |
| `p_today` | `date` | 案A のみ必須 | 「当日」の暦日。Flutter が端末TZで解決して渡す |
| `p_range_start` | `date` | 案A のみ必須 | 表示範囲の開始日（閉区間） |
| `p_range_end` | `date` | 案A のみ必須 | 表示範囲の終了日（閉区間） |

- 案B（RPC 内でTZ固定）を採る場合、`p_today` / `p_range_start` / `p_range_end` は引数から外す。
- 案B では関数内で `p_period` から範囲を導出する。二択の比較は §5.1、確定は §10-1。

```dart
// 案A の呼び出し例
final json = await supabase.rpc('get_dashboard', params: {
  'p_period': 'month',
  'p_today': '2026-08-07',
  'p_range_start': '2026-08-01',
  'p_range_end': '2026-08-31',
}) as Map<String, dynamic>;
```

### 戻り値（`json` 1値）

```jsonc
{
  "protein_gauge": {
    "weight_kg": "float|null",  // users.weight_kg をそのまま返す。未設定は null（[仮]・§10-4）
    "intake_g": "float"         // 当日の meal_logs.protein_g 合計。記録なしは 0
  },
  "heatmap": [
    {
      "date": "date",           // ISO 8601（YYYY-MM-DD）
      "done": "boolean",        // 実施有無の2値
      "menu_names": ["string"]  // ツールチップ用の種目名（重複排除・名前昇順）
    }
  ]
}
```

画面 DTO は Flutter が組み立てる。`{ protein_gauge, heatmap[] }` という形は維持する。

| フィールド | 由来 |
|---|---|
| `protein_gauge.target_g` | `weight_kg` を FEAT-07 の Dart 関数（RULE-001）に渡して算出。null なら null |
| `protein_gauge.intake_g` | RPC の値をそのまま使う |
| `protein_gauge.rate_pct` | `calcGaugeRatePct`（L3・L4）で算出。`target_g` が null なら null |
| `heatmap[]` | RPC の値をそのまま使う |

- `target_g` / `rate_pct` を SQL で計算しない。RULE-001 を SQL に複製しないため（§10-12）。
- `heatmap` は**実施記録のある日だけ**を返す（未実施日は要素を返さない）。
- 未実施セルは Flutter が表示範囲から補完する。
- 表示範囲（`range_start`〜`range_end`）は戻り値に含めない。
- 案A では Flutter が自分の渡した値を使う。案B では Flutter 側で再計算になる（§10-8）。

### エラー時の戻り

```jsonc
// PostgREST 形式（[仮]・実装時に確認）
{ "code": "PT400", "message": "ERR-DASHBOARD-001", "details": "string", "hint": null }
```

- 旧構成の共通エラー契約 `{ error_code, message, retryable }` とは形が違う。
- Flutter 側で `PostgrestException` を捕まえ、共通のエラーモデルへ変換する。
- 変換規則の正本は `../07_実装共通設計パターン.md`。

### 3.1 バリデーション規則

| 項目 | 規則 | 違反時 |
|---|---|---|
| `p_period` | 省略可。指定時は `day` / `week` / `month` のいずれか | ERR-DASHBOARD-001 (400) |
| `p_period` 未指定 | 既定値 `month` を適用（関数の `default`）。エラーにしない | — |
| `p_range_start` / `p_range_end`（案A） | `date` として解釈できること | ERR-DASHBOARD-001 (400)（[仮]） |
| `p_range_start` / `p_range_end`（案A） | `range_start <= range_end` であること | ERR-DASHBOARD-001 (400) |
| 未知の引数 | 関数シグネチャに無い引数は PostgREST が弾く。Flutter から送らない | — |
| 認証セッション | JWT が有効であること | ERR-AUTH-001 (401) |
| プロフィール存在 | `users` に本人行が存在すること | ERR-DASHBOARD-002 (409) |
| `users.weight_kg` | NULL 可。NULL でもエラーにせず `weight_kg: null` で返す（[仮]） | — |

- Flutter 側は `Period` enum で値域を保証する。RPC 側でも同じ検証を行う（二重）。
- 二重にする理由は、RPC が Flutter 以外のクライアントからも呼べるため。検証をクライアントに委ねない。
- Dart には zod が無い。戻り値の検証はモデルクラスの `fromJson` で行う。

## 4. 業務ロジック

| # | ロジック | 定義 | 対応 |
|---|---|---|---|
| L1 | 目標タンパク質量 `target_g` | RULE-001（体重×2g）。**算出の正本は FEAT-07** の Dart 純関数を呼ぶ。本機能では再実装しない | RULE-001 / FEAT-07 |
| L2 | 当日摂取量 `intake_g` | 当日（`eaten_date = p_today`）の `meal_logs.protein_g` の合計。行が無ければ 0 | DM-08 |
| L3 | 達成率 `rate_pct` | `min(100, intake_g / target_g * 100)` を小数第1位に丸める。**100%で頭打ち** | ADR-0002 |
| L4 | 0除算・未設定ガード | `target_g` が `null` または `0` 以下なら `rate_pct` は `null`（除算しない） | §10-4 |
| L5 | 日付範囲 `resolveDateRange` | `day`＝当日のみ／`week`＝当日を含む週の月曜〜日曜／`month`＝当月1日〜末日（[仮]）。**解決する場所は案A／案B の二択**（比較は §5.1） | §10-1 / §10-8 |
| L6 | 実施有無 `done` | その日の `is_done` が **1件以上 true**（＝ST-02 到達）なら `true`。明細が全て ST-01 の日／明細0件の日は `false`（[仮]） | ST-01 / ST-02 / §10-3 |
| L7 | 種目名 `menu_names` | `done=true` の明細の `training_menus.name` を重複排除し名前昇順で返す。`done=false` の日は空配列 | §10-3 |

実行場所の割り当て:

| ロジック | 実行場所 |
|---|---|
| L2・L6・L7 | RPC（SQL） |
| L1・L3・L4 | Flutter（Dart 純関数・単体テスト対象） |
| L5 | 案A＝Flutter（Dart 純関数）／案B＝RPC（SQL） |

疑似コード（純関数として切り出す部分）:

```text
calcGaugeRatePct(intake_g, target_g):
  if target_g is null or target_g <= 0: return null        # L4
  return round(min(100, intake_g / target_g * 100), 1)     # L3

resolveDateRange(period, now, timeZone):                    # L5・案A のみ
  today = 「timeZone における now の暦日」（YYYY-MM-DD）
  day   -> { start: today,               end: today }
  week  -> { start: todayを含む週の月曜, end: todayを含む週の日曜 }
  month -> { start: 当月1日,             end: 当月末日 }
  return { today, start, end }
```

- `intake_g` は `protein_g` の単純合計とする。`meal_logs.intake_count`（摂取数）は**乗じない**。
- 理由は `intake_count` の業務的意味が未確定なため（`../../30_データ・IF設計/01_データモデル.md §8-6`）。
- FEAT-08/FEAT-09 と扱いを揃える（§10-9）。
- AI（EXT-01）は使用しない。全てDB集計の決定的処理（NFR-PERF-02）。

## 5. データアクセス

構成は3段。**Q1 と Q2 を1つの RPC にまとめ、往復を1回にする**。

| 段 | 節 | 内容 |
|---|---|---|
| 前提 | §5.1 | 日付範囲とタイムゾーンの決め方（案A／案B） |
| Q1 | §5.2 | タンパク質ゲージ（当日 SUM） |
| Q2 | §5.3 | ヒートマップ（期間集約・N+1回避） |
| まとめ | §5.4 | RPC `get_dashboard` が Q1・Q2 を1本にする |
| 付帯 | §5.5 | 対象テーブル・INDEX・RLS・トランザクション境界 |

### 5.1 日付範囲とタイムゾーンの決め方

**タイムゾーンの二択は本節だけで扱う。** §3・§4 L5・§5.4・§10-1・§10-8 は本節を参照する。

旧構成は「サーバ（`TZ=UTC`）で `APP_TIMEZONE` を解決し、date をパラメータで渡す」方式だった。新構成にサーバは無い。決め方は次の二択になる。

| 観点 | 案A（本書の [仮]） | 案B |
|---|---|---|
| 決める場所 | Flutter（端末TZ） | RPC 内（固定TZ） |
| 実装 | `resolveDateRange` を Dart 純関数で持つ | `(now() AT TIME ZONE 'Asia/Tokyo')::date` から導出 |
| 引数 | `p_today` / `p_range_start` / `p_range_end` を渡す | 上記3引数を持たない |
| 長所 | 純関数なので単体テストしやすい | 端末設定に左右されない |
| 長所 | 海外滞在時は現地の暦日に追従できる | 全機能で暦日の定義が1つに揃う |
| 短所 | 端末TZを変えると同じ日の集計結果が変わる | 海外滞在時に現地の日付と食い違う |
| 短所 | 記録側と採番TZが揃わないとズレる | TZ変更に関数の再デプロイが要る |

どちらを採っても守ること。

| 項目 | 内容 |
|---|---|
| `CURRENT_DATE` / `now()::date` を素で使わない | Postgres セッションのTZは UTC。JST 00:00〜09:00 の間は前日を返す。案B でも `AT TIME ZONE` を必ず明示する |
| 記録側とTZを揃える | `eaten_date` / `performed_date` は `date` 型でTZを持たない。記録時と集計時のTZ一致が前提（FEAT-04・FEAT-08） |
| 二重定義を避ける | 案A では日付規則が Dart にしか無い。案B では SQL にしか無い。両方には書かない |

- 本書は**案A を `[仮]`** とする。確定は §10-1。

> ⚠️ 要確認（人間判断）: 日付範囲を Flutter（端末TZ・案A）で決めるか、RPC 内の固定TZ（案B）で決めるか。

### 5.2 Q1: タンパク質ゲージ（当日 SUM）

```sql
-- 目的: 目標算出用の体重と、当日のタンパク質摂取合計を1クエリで取得する
-- $1 = user_id, $2 = today（§5.1 で解決した暦日・date）
SELECT u.weight_kg,
       COALESCE(SUM(m.protein_g), 0)::float8 AS intake_g
FROM users u
LEFT JOIN meal_logs m
       ON m.user_id = u.id
      AND m.eaten_date = $2
WHERE u.id = $1
GROUP BY u.id, u.weight_kg;
```

- `LEFT JOIN` により、当日の食事記録が0件でも1行（`intake_g = 0`）が返る。
- 旧構成はこのクエリの0行を ERR-DASHBOARD-002 の判定に使っていた。
- RPC では本人行の解決を先に行う。**判定点が前倒しになる**（§5.4）。判定結果は変わらない。
- `target_g` はこの `weight_kg` を FEAT-07 の Dart 関数に渡して求める。
- SQL で `weight_kg * 2` を計算しない（RULE-001 の重複定義を避ける）。

### 5.3 Q2: ヒートマップ（期間集約・N+1回避）

```sql
-- 目的: 期間内の実施日ごとに「実施有無」と「種目名の配列」を1クエリで集約する
-- $1 = user_id, $2 = range_start（date）, $3 = range_end（date）
SELECT s.performed_date                                   AS date,
       COALESCE(bool_or(d.is_done), false)                AS done,
       COALESCE(
         array_agg(DISTINCT mn.name ORDER BY mn.name)
           FILTER (WHERE d.is_done),
         ARRAY[]::text[]
       )                                                  AS menu_names
FROM training_sessions s
LEFT JOIN training_session_details d ON d.session_id = s.id
LEFT JOIN training_menus          mn ON mn.id = d.menu_id
WHERE s.user_id = $1
  AND s.performed_date BETWEEN $2 AND $3
GROUP BY s.performed_date
ORDER BY s.performed_date;
```

- **N+1回避**: 日付ごと・セッションごとのループ照会をしない。
- `GROUP BY performed_date` の1クエリで全日分を組み立てる。
- `array_agg` により種目名も同一クエリに含める。明細取得の追加クエリを発行しない。
- 同じ日に複数の `training_sessions` があっても `performed_date` で集約され、1日1要素になる。
- PostgREST の埋め込み `select` でも1往復で取れる。ただし日付集約と重複排除が Flutter 側の処理になるので採らない。

### 5.4 RPC `get_dashboard`（Q1・Q2 を1本にまとめる）

Q1・Q2 を1つの関数にまとめ、`json_build_object` で返す。往復は1回になる。

| 項目 | 値 | 理由 |
|---|---|---|
| 言語 | `plpgsql` | `raise exception` でエラーを返すため。旧案の `language sql` では RAISE が書けない |
| 揮発性 | `stable` | 参照のみ。同一トランザクション内で結果が変わらない |
| 権限 | `security invoker` | `security definer` は RLS を迂回するので使わない |
| `search_path` | `public` に固定 | 関数内の名前解決を呼び出し元の設定に依存させない |

```sql
-- supabase/migrations/*.sql
create or replace function public.get_dashboard(
  p_period      text default 'month',
  p_today       date default null,
  p_range_start date default null,
  p_range_end   date default null
)
returns json
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_user_id uuid;          -- users.id は auth.users.id と同値の uuid（案A・ADR-0005）
  v_weight  numeric;
  v_intake  float8;
  v_heatmap json;
begin
  -- (1) 引数検証 → ERR-DASHBOARD-001
  if p_period is null or p_period not in ('day', 'week', 'month') then
    raise exception 'ERR-DASHBOARD-001' using errcode = 'PT400';
  end if;
  if p_range_start > p_range_end then
    raise exception 'ERR-DASHBOARD-001' using errcode = 'PT400';
  end if;

  -- (2) 本人の users 行を解決 → 無ければ ERR-DASHBOARD-002
  --     案A（ADR-0005）により中間列は不要。id を auth.uid() と直接比較する
  select u.id
    into v_user_id
    from users u
   where u.id = auth.uid();
  if not found then
    raise exception 'ERR-DASHBOARD-002' using errcode = 'PT409';
  end if;

  -- (3) Q1（§5.2 と同一。$1 = v_user_id, $2 = p_today）
  select g.weight_kg, g.intake_g
    into v_weight, v_intake
    from (
      SELECT u.weight_kg,
             COALESCE(SUM(m.protein_g), 0)::float8 AS intake_g
      FROM users u
      LEFT JOIN meal_logs m
             ON m.user_id = u.id
            AND m.eaten_date = p_today
      WHERE u.id = v_user_id
      GROUP BY u.id, u.weight_kg
    ) g;

  -- (4) Q2（§5.3 と同一。$1 = v_user_id, $2 = p_range_start, $3 = p_range_end）
  select coalesce(
           json_agg(
             json_build_object('date', c.date, 'done', c.done, 'menu_names', c.menu_names)
             order by c.date
           ),
           '[]'::json
         )
    into v_heatmap
    from (
      SELECT s.performed_date                                   AS date,
             COALESCE(bool_or(d.is_done), false)                AS done,
             COALESCE(
               array_agg(DISTINCT mn.name ORDER BY mn.name)
                 FILTER (WHERE d.is_done),
               ARRAY[]::text[]
             )                                                  AS menu_names
      FROM training_sessions s
      LEFT JOIN training_session_details d ON d.session_id = s.id
      LEFT JOIN training_menus          mn ON mn.id = d.menu_id
      WHERE s.user_id = v_user_id
        AND s.performed_date BETWEEN p_range_start AND p_range_end
      GROUP BY s.performed_date
      ORDER BY s.performed_date
    ) c;

  return json_build_object(
    'protein_gauge', json_build_object('weight_kg', v_weight, 'intake_g', v_intake),
    'heatmap',       v_heatmap
  );
end;
$$;
```

- Q1・Q2 の SQL 本体は §5.2・§5.3 から変えていない。**N+1回避の結論は変わらない。**
- 案B を採る場合、`p_today` / `p_range_start` / `p_range_end` を引数から外す。
- 案B では (1) の直後に `p_period` からの範囲導出を足す（§5.1）。Q1・Q2 の本体は同じ。
- 関数の DDL は `../01_DB物理設計.md` に存在しない。追記が要る（`../07_実装共通設計パターン.md §10-1` と同じ論点）。

### 5.5 対象テーブル・INDEX・RLS

**対象テーブル**（すべて SELECT のみ。INSERT/UPDATE/DELETE は無い）

| テーブル | 用途 |
|---|---|
| `users` | 体重の取得・本人行の解決 |
| `meal_logs` | 当日のタンパク質合計（Q1） |
| `training_sessions` | 実施日の抽出（Q2） |
| `training_session_details` | 実施有無の判定（Q2） |
| `training_menus` | 種目名の解決（Q2） |

**使用INDEX**

| クエリ | INDEX | 使い方 |
|---|---|---|
| Q1 | `ix_meal_logs_user_date` | `user_id, eaten_date` の等値一致 |
| Q2 | `ix_train_sessions_user_date` | `user_id, performed_date` の範囲スキャン |
| Q2 | `uq_tsd_session_menu` | 先頭列 `session_id` で JOIN |
| Q2 | `training_menus` の PK | 種目名の解決 |

- **追加INDEXは現時点で不要**。新規INDEXの追加は `../01_DB物理設計.md` が正本のため本書では行わない。
- `ix_gym_visits_user_date` は使わない。本機能は `gym_visits` を参照しない（§10-2 の論点）。

**RLS・トランザクション**

| 観点 | 内容 |
|---|---|
| RLS | `user_id = auth.uid()` の直接比較で本人行のみ。`security invoker` なので関数内でも効く |
| RLS | `users` 自身の述語は `id = auth.uid()`。`users.id` は `auth.users.id` と同値の uuid（案A・ADR-0005） |
| 往復回数 | 1（RPC 1本）。旧構成は2クエリを個別に発行していた |
| トランザクション | 関数本体が暗黙の単一トランザクション。参照のみのため明示的な `begin` は書かない |
| トランザクション | Q1/Q2 が同一スナップショットで読める。旧構成より改善する |

## 6. エラー処理

| ERR-ID | HTTP | errcode | 発生条件 | 利用者向けメッセージ（意図） | retryable | ログ |
|---|---|---|---|---|---|---|
| ERR-AUTH-001 | 401 | — | JWT が無効／未ログイン（PostgREST が返す） | 再ログインを促す | false | 認証失敗として記録（NFR-SEC-AUDIT-02） |
| ERR-DASHBOARD-001 | 400 | `PT400` | `p_period` が `day` / `week` / `month` 以外。または範囲の前後が逆 | 期間指定が不正である旨（UIからは通常起きない） | false | warn（引数値を記録） |
| ERR-DASHBOARD-002 | 409 | `PT409` | `users` に本人行が存在しない（FEAT-06 の初期設定が未完了） | 初期設定（SCR-05）へ誘導する | false | warn |
| ERR-DASHBOARD-003 | 500 | — | RPC の失敗（DB到達不能・タイムアウト・想定外例外） | 一時的な取得失敗として再試行を促す | true | error（所要時間を記録） |

- `PT4xx` / `PT5xx` を `errcode` に指定すると PostgREST が同じ番号の HTTP ステータスで返す。
- 上記は `[仮]`。実装時に公式ドキュメントで確認する。
- ERR-DASHBOARD-003 は RPC 側で分類できない。Flutter が `PostgrestException`・接続例外を捕まえて割り当てる。
- `users.weight_kg` が NULL のケースは**エラーにしない**。`weight_kg: null` を返す（[仮]・§10-4）。
- 画面側は未設定表示に縮退する（§7）。
- 自動リトライは行わない（参照系のため、利用者操作の [再試行] に委ねる）。
- ログは Supabase 側（Postgres ログ）に出る。Flutter 側のクラッシュ収集はスコープ外。
- 分類・出力の横断方針は `../07_実装共通設計パターン.md` を正本とする。

> ERRの完全列挙の正本は `../../60_テスト設計/02_RED母集合_受入基準・状態・エラー.md`（段6で集約）。本表はその入力とする。

## 7. 画面挙動・状態別表示

| 状態 | 表示 | 操作可否 |
|---|---|---|
| 初期/空（記録0件） | ゲージは `intake_g=0`・`rate_pct=0` で描画。ヒートマップは全セル未実施色＋「まだ記録がありません」 | `SegmentedButton` 操作可 |
| 読込中 | ゲージ・ヒートマップの位置に `shimmer` のプレースホルダ（同サイズでシフト防止） | `SegmentedButton` は `onSelectionChanged: null` |
| 成功（ゲージ） | `CircularProgressIndicator(value: rate_pct / 100)` を `Stack` の中央 `Text`（`intake_g / target_g`）と重ねる | 全操作可 |
| 成功（ヒートマップ） | 各セルを `Tooltip(message: menu_names)` で包む。空配列の日は日付のみ | 全操作可 |
| 体重未設定（`target_g: null`） | ゲージをグレー表示（`value` を渡さない）＋「体重を設定するとゲージが表示されます」＋ SCR-05 への `ElevatedButton` | ゲージ以外は操作可 |
| エラー（4xx/5xx） | ゲージ／ヒートマップ領域をエラー表示（`Icon`＋`Text` の `Card`）に差し替え＋[再試行] `TextButton`＋`SnackBar` | [再試行] のみ |
| 期間切替中 | 直前の表示を保持したまま `Stack` に半透明の `Container`＋`CircularProgressIndicator` を重ねる | 切替完了まで無効 |

- ゲージは `CircularProgressIndicator` で足りる。
- 中央ラベルや太さの調整が要るなら `fl_chart` の `PieChart` に置き換える（[仮]）。
- カレンダー型ヒートマップに相当する標準ウィジェットは無い。
- `GridView.builder` ＋ `Container` の自作とする（[仮]）。ADR-0002 が前提にしていた既製コンポーネントは使えない。
- ダークモードの配色は `Theme.of(context).colorScheme` に追従させる。
- ヒートマップの2値（実施／未実施）のコントラストを両モードで確認する。
- 初期表示 ≤2秒（NFR-PERF-01）は RPC 1往復と描画で満たす。遅延ロードの仕組みは持たない。

## 8. 実装単位

| # | ファイル | 役割 | 主なシグネチャ |
|---|---|---|---|
| 1 | `supabase/migrations/*_get_dashboard.sql` | RPC `get_dashboard` の定義（§5.4）。up/down 対で用意する | `get_dashboard(p_period text, p_today date, p_range_start date, p_range_end date) returns json` |
| 2 | `app/lib/data/dashboard_repository.dart` | RPC 呼び出しと例外分類（Supabase クライアント注入） | `Future<Dashboard> fetch(Period period, DateRange range)` |
| 3 | `app/lib/domain/date_range.dart` | `period` → 集計日付範囲（TZ解決・純関数・案A のみ） | `DateRange resolveDateRange(Period period, DateTime now, String timeZone)` |
| 4 | `app/lib/domain/gauge.dart` | 達成率算出（100%頭打ち・0除算ガード・純関数） | `double? calcGaugeRatePct(double intakeG, double? targetG)` |
| 5 | `app/lib/features/dashboard/dashboard_model.dart` | RPC の JSON → モデル変換 | `factory Dashboard.fromJson(Map<String, dynamic> json)` |
| 6 | `app/lib/features/dashboard/dashboard_page.dart` | SCR-01 のページ（レイアウトと状態分岐） | `class DashboardPage extends StatelessWidget` |
| 7 | `app/lib/features/dashboard/protein_gauge.dart` | ゲージ表示・未設定時の縮退表示 | `class ProteinGauge extends StatelessWidget` |
| 8 | `app/lib/features/dashboard/training_heatmap.dart` | ヒートマップ表示・`Tooltip` で種目名 | `class TrainingHeatmap extends StatelessWidget` |
| 9 | `app/lib/features/dashboard/period_control.dart` | `SegmentedButton`（日/週/月）と再取得 | `class PeriodControl extends StatelessWidget` |

- 目標量の算出関数は **FEAT-07 が定義する `app/lib/domain/nutrition.dart` を import** する。
- 配置・関数名の正本は FEAT-07 の詳細設計。本機能では同等の計算を書かない。
- 純関数（#3・#4）は単体テスト対象（NFR-QUAL-01）。
- 戻り値のスキーマ検証ライブラリは使わない。`fromJson` で型変換し、欠損はモデル側の既定値で吸収する。

## 9. テスト観点

### 9.1 テストケース

| TC-ID | 観点 | 期待 |
|---|---|---|
| TC-FEAT05-01 | 未認証で `get_dashboard` を呼ぶ | 401 / ERR-AUTH-001 |
| TC-FEAT05-02 | `p_period` が enum 外 | 400 / ERR-DASHBOARD-001（`PT400`） |
| TC-FEAT05-03 | `p_period` 未指定 | 成功・`month` の範囲で集計される |
| TC-FEAT05-04 | 当日の `meal_logs` が0件 | `intake_g = 0`・`rate_pct = 0`（エラーにしない） |
| TC-FEAT05-05 | `intake_g > target_g`（過剰摂取） | `rate_pct = 100`（100%頭打ち・ADR-0002） |
| TC-FEAT05-06 | `users.weight_kg` が NULL | 成功・`weight_kg: null`・画面側で `target_g`/`rate_pct` が null（0除算しない） |
| TC-FEAT05-07 | `users` 行なし | 409 / ERR-DASHBOARD-002（`PT409`） |
| TC-FEAT05-08 | 同日に複数 `training_sessions` | ヒートマップ要素は1日1件に集約される |
| TC-FEAT05-09 | 明細が全て `is_done=false` の日 | `done=false`・`menu_names` は空配列 |
| TC-FEAT05-10 | 明細0件の `training_sessions` の日 | `done=false`（L6 の定義どおり） |
| TC-FEAT05-11 | 同一種目を複数明細で実施 | `menu_names` が重複排除され名前昇順 |
| TC-FEAT05-12 | 期間境界（`p_range_start` / `p_range_end` 当日） | 両端が含まれる（BETWEEN の閉区間） |
| TC-FEAT05-13 | 端末TZ=JST・UTC で日付が変わる時刻（JST 00:30） | 当日判定が JST の暦日になる（前日にならない） |
| TC-FEAT05-14 | 発行クエリ数の検証 | RPC 1往復・関数内2クエリ以内（N+1が無い） |
| TC-FEAT05-15 | 初期表示の所要時間 | ≤2秒（NFR-PERF-01） |
| TC-FEAT05-16 | DB到達不能 | ERR-DASHBOARD-003・エラー表示＋[再試行] が出る |

### 9.2 受入基準（G/W/T）の候補

- [AC] Given 当日の食事記録と体重が登録されている When SCR-01 を開く Then タンパク質ゲージが達成率とともに表示される
- [AC] Given 摂取量が目標量を超えている When SCR-01 を開く Then 達成率は100%として表示される
- [AC] Given 体重が未設定である When SCR-01 を開く Then ゲージは未設定表示になり、初期設定（SCR-05）への導線が示される
- [AC] Given 期間内にトレーニング実施日がある When ヒートマップの実施日をタップする Then その日の種目名が表示される
- [AC] Given 月表示でダッシュボードを見ている When `SegmentedButton` で週を選ぶ Then 表示範囲だけが週に切り替わる（記録は削除・変更されない）

> 受入基準・ST・ERR の**正本は段6**（`../../60_テスト設計/02_RED母集合_受入基準・状態・エラー.md`・本PR対象外）。本節はその母集合への入力。

## 10. 敵対的検証・要確認事項

| # | 論点 | 内容 | 重大度 |
|---|---|---|---|
| 1 | 「当日」判定のタイムゾーン | 解決場所は**案A／案B の二択**で未確定（比較と守るべき点は §5.1）。本書は案A を [仮] とする。`meal_logs.eaten_date` は TZ を持たない `date` 型で、記録側（FEAT-04・FEAT-08）と採番TZが揃わないと整合しない | 🔴 高 |
| 2 | `done` の定義が文書間で不一致 | 集計元の記述が3か所で食い違う。入館したが記録が無い日の扱いが決まらない。内訳＝段3 §3 は `gym_visits`／`../01_DB物理設計.md §2.2` は `performed_date`／段3 §4.3 は session→details→menus | 🔴 高 |
| 3 | `done` 判定の粒度 | 「`training_sessions` があれば done」か「`is_done` が1件以上 true なら done」かが未確定。本書は `is_done` 基準を [仮]。前者ではヒートマップが「ジムに行った日」となり ST-02 と乖離する（明細0件の行も同じ論点） | 🔴 高 |
| 4 | 体重未設定時のゲージ | `users.weight_kg` は NULL 可だが段3 §4.3 の `target_g` は null 不可。契約どおりだと初回ログイン直後に必ずエラーになる。本書は null 返却＋画面側の縮退表示を [仮]（§7／`rate_pct` の0除算ガードも契約に無い） | 🔴 高 |
| 5 | ゲージとヒートマップで期間の意味が違う | 同一画面の2つの図が別の期間を表す。`period` は日/週/月だが `protein_gauge.intake_g` は当日固定（段3 §4.3 に期間定義が無い）。「月」でゲージも月合計だと誤解しうるため、週/月は平均達成率にするか当日固定と明記するかの判断が要る | 🔴 高 |
| 6 | 100%頭打ちで過剰摂取が見えない | ADR-0002 で100%頭打ちを確定済みだが、150%摂取と100%摂取が同じ表示になり**摂り過ぎに気づけない**。減量・増量いずれの目的でも過剰は情報として要る。リングは100%で止めつつ中央の数値や `Chip` で超過を示す補助表示が要るか | 🟡 中 |
| 7 | `period` の既定値と `day` の情報価値 | `period` 省略時の既定値が契約に無い（本書は `month` を [仮]）。`period=day` ではヒートマップが1セルになり可視化として成立しない。日表示は当日の種目リストに差し替える等のUI判断が要る（ADR-0002「表示は常に1ヶ月」との関係も整理が必要） | 🟡 中 |
| 8 | 週/月の境界規則がレスポンスに無い | `week`＝暦週か直近7日か、`month`＝当月1日〜末日か直近30日かが未定義（本書は暦基準を [仮]）。案A なら規則は Dart 側1箇所で済む。案B は RPC 内に規則があり Flutter 側で描画範囲を再計算＝二重実装になり、ズレると範囲が食い違う | 🟡 中 |
| 9 | `intake_count` を掛けるか | 本書は `SUM(protein_g)` のみとした（§4 L2）。`intake_count`（摂取数）の業務的意味が未確定（`01_データモデル.md §8-6`）。FEAT-09 が異なる解釈を採ると**同じ当日摂取量が画面ごとに違う値になる** | 🟡 中 |
| 10 | 全履歴保持と集計性能 | 保持期間の制限が無く（`01_データモデル.md §7`）行数は単調増加する。ただし Q1・Q2 とも走査対象は期間内に限定される（§5.5）。**month 表示では既存INDEXで足りるが**、「年」表示・累積統計・複数ユーザー化を足すと前提が変わり再評価が要る | 🟢 低 |
| 11 | ~~`users.id` と `auth.uid()` の紐付け未確定~~（**解決**） | **案A確定**（ADR-0005）。`users.id` を `auth.users.id` と同値の uuid にする。中間列は持たない。§5.4 の本人行解決は `u.id = auth.uid()` になり、`v_user_id` も uuid で確定した | — |
| 12 | RULE-001 の計算場所 | 構成変更で新たに生じた論点。旧構成は `target_g` をサーバ側で算出していた。集計を RPC に寄せると RULE-001（体重×2g）が FEAT-07 と二重定義になるため、本書は Dart 側算出を [仮] とした（戻り値と画面 DTO の形は一致しない） | 🟡 中 |
| 13 | 過去期間の達成率が遡って書き換わる | 体重は現在値1点のみを持つと確定した（ADR-0009）。`weight_kg` に履歴が無いため、過去日・過去期間のゲージも**現在の体重**で `target_g` を計算する。体重を変えると過去の達成率が事後的に変わる。SCR-01 に**誤解を与えないUI表現が要る**（どの体重を基準にした値かの明示・注記） | 🟡 中 |

> ⚠️ 要確認（人間判断）: #1 日付範囲の解決を Flutter（端末TZ・案A）にするか RPC 内の固定TZ（案B）にするか。記録側（FEAT-04・FEAT-08）の日付採番と揃える必要がある。

> ⚠️ 要確認（人間判断）: #2・#3 ヒートマップの「実施有無」の集計元と判定粒度の確定。
> 集計元の候補は `gym_visits` / `training_sessions` / `training_session_details.is_done` の3つ。
> 確定は `../../30_データ・IF設計/02_API設計.md` と `../01_DB物理設計.md` の食い違いの解消を伴う。

> ⚠️ 要確認（人間判断）: #4 体重未設定時に `target_g`・`rate_pct` を null で返す（本書の [仮]）ことを契約（`../../30_データ・IF設計/02_API設計.md §4.3`）に反映してよいか。

> ⚠️ 要確認（人間判断）: #5 `period` がゲージに及ぶか否か。ゲージを当日固定と明記するか、週/月では平均達成率にするか。

> ⚠️ 要確認（人間判断）: #6 100%頭打ちのまま過剰摂取を補助表示（数値・`Chip`）で見せるかどうか。

> ⚠️ 要確認（人間判断）: #7・#8 `period` の既定値、週/月の境界規則、および `period=day` のヒートマップ表現。

> ⚠️ 要確認（人間判断）: #9 `intake_count` を摂取量計算に乗じるか。FEAT-09 と同一の解釈に統一する必要がある。

> ⚠️ 要確認（人間判断）: #12 RULE-001 を Dart 側のみに置き、RPC は `weight_kg` を返すだけとする方針でよいか。

> ⚠️ 要確認（人間判断）: #13 過去期間のゲージを「現在の体重が基準」と分かる表現にするか。ADR-0009 により体重履歴は持たないため、表現でしか解けない。案は次の3つ。
>
> | 案 | 表現 |
> |---|---|
> | i | ゲージ脇に基準体重を併記する（「基準: 現在の体重 ◯kg」） |
> | ii | 期間が当日以外のとき注記を出す（「過去分も現在の体重で計算しています」） |
> | iii | ゲージは当日固定とし、過去期間では達成率を出さない（#5 の結論に依存） |

> ~~⚠️ 要確認（人間判断）: 本書は Flutter + Supabase 構成（Vercel 不使用）で記述している。~~（**解決**・2026-08-08）
> ~~一方 ADR-0001（Vercel AI Gateway 採用）・ADR-0002（Next.js + Mantine 採用）は Vercel 前提のまま。~~
> ~~`30_データ・IF設計/02_API設計.md` も `/api/*` の Route Handler 契約のまま。後継ADRの起票と段3の改訂が必要。~~
> **ADR-0010**（Flutter + Supabase）と **ADR-0011**（Gemini API 直接）を起票した。
> ADR-0001・ADR-0002 は Superseded にした。段3も改訂済み。
> 本機能では `GET /api/dashboard?period=` が RPC `get_dashboard` に置き換わった。

> 関連: API契約＝`../../30_データ・IF設計/02_API設計.md` / 物理DB＝`../01_DB物理設計.md` / 横断方針＝`../07_実装共通設計パターン.md` / シーケンス＝`../../40_機能設計/01_シーケンス設計.md`。
