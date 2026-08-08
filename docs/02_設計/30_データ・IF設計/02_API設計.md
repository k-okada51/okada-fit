---
status: draft
---

# API設計（IF契約） — okada-fit

> **目的**: 各IF（EXT-01〜）の**契約（リクエスト／レスポンス／エラー）**を定義し、契約テストの基準とする。
> **書き方**:（記入例は example-suido-fax の対応ファイル参照）実データは書かず、型（スキーマ）の枠だけ示す。契約はスキーマ（zod等）を単一ソースとし、エラーは共通契約で統一する。EXT-ID は不変（`../../01_要件定義/00_用語定義.md §3` ID付番規則）。実装ワイヤ・詳細は `50_詳細設計/03_外部連携IF/README.md` を正本とする。

> ⚠️ **本書はたたき台（2026-07-25 生成／2026-08-08 全面改訂）**。岡田さんのレビューで最終確定する。前提: Flutter アプリ（`supabase_flutter`）＋ Supabase（ADR-0004 / ADR-0005）。使うのは Auth / PostgreSQL + RLS / Edge Functions。AI（EXT-01）は Edge Function から Google Gemini API を直接呼ぶ。**Vercel・Next.js は使わない**（2026-08-07 決定）。旧版の `/api/*`（Next.js Route Handler）契約は本改訂で全廃した。対比表は §3 末尾。

## 目次
1. [API共通規約](#1-api共通規約)
2. [想定API一覧](#2-想定api一覧)
3. [エンドポイント一覧](#3-エンドポイント一覧)
4. [IF別 契約](#4-if別-契約)
5. [共通エラー応答契約](#5-共通エラー応答契約)

## 1. API共通規約
> 📝 ここに全APIに共通する規約を記載。個別IFではなく横断ルールを固定する。{ベースURL・バージョニング（/v1等）／認証・認可（方式・トークン所在・スコープ）／共通リクエスト/レスポンスヘッダ（相関ID・冪等キー等）／ページング・ソート・フィルタの様式／日時・数値・enumの表現規約／冪等性・リトライの扱い／レート制限}。詳細な型は `../50_詳細設計/06_DB設計規約.md` の物理命名規約・`01_データモデル.md` のデータ契約に従う。

**共通のベースURLは無い。** 呼び出しは3方式に分かれる。

| 方式 | Flutter からの呼び方 | 実体（HTTP） | 使う機能 |
|---|---|---|---|
| PostgREST | `supabase.from('<table>').select()` 等 | `{SUPABASE_URL}/rest/v1/<table>` | FEAT-01 / 02 / 04 / 06 / 08 |
| RPC | `supabase.rpc('<function>', params: {...})` | `{SUPABASE_URL}/rest/v1/rpc/<function>` | FEAT-01 / 04 / 05 / 09 / 10 |
| Edge Function | `supabase.functions.invoke('<name>')` | `POST {SUPABASE_URL}/functions/v1/<name>` | FEAT-03 / 08 |

- パスの形は Supabase が決める。設計側で決められるのは**表名・関数名・Edge Function 名だけ**。
- 機能ごとの割り当ては §2・§3。旧契約との対比は §3 末尾。

| 規約 | 方針 |
|---|---|
| バージョニング | 共通ベースURLを持たない（上表）。単一クライアント（自アプリ）のためバージョンパスも持たない |
| 認証・認可 | **Supabase Auth**（ADR-0004）。3方式すべてで認証必須 |
| トークンの所在 | 端末。`supabase_flutter` が JWT を保持し、期限前に自動リフレッシュする |
| トークンの付与 | `Authorization: Bearer <JWT>` を**全リクエストに自動付与**。アプリでヘッダを組み立てない |
| 一次防御 | **RLS**（`user_id = auth.uid()`）。PostgREST・RPC は Edge Function を通らない |
| 認証主体 | `users.id` は **uuid**。`auth.users.id`・`auth.uid()` と同値（ADR-0005）。対応表は持たない |
| Edge Function の認証 | 関数内で JWT を明示検証する（`requireUser`）。`--no-verify-jwt` を付けない |
| 共通ヘッダ | 相関ID（任意・ログ用）は **Edge Function 経路のみ**。PostgREST・RPC には付かない |
| 冪等キー | **当面持たない**。処理済みキーの保存先が無いため（`../50_詳細設計/07_実装共通設計パターン.md §3`） |
| ページング/ソート/フィルタ | データ小規模のため当面ページングなし。並び順は各機能設計で指定する |
| 期間指定 | RPC 引数で渡す。`p_period`＝`day`/`week`/`month`、範囲は `p_range_start`・`p_range_end`（date） |
| 「当日」の基準 | **日付はアプリが端末のタイムゾーンで決めて渡す。RPC 内で `CURRENT_DATE` を使わない**（2026-08-08 確定・ADR-0014） |
| 日時・数値・enum 表現 | 日時=ISO 8601（`date`/`time`）。栄養値=`float`、回数等=`int`。enum=`body_part`（胸/背中/脚/肩/腕） |
| 命名 | キー・列名は snake_case。RPC 引数は `p_` 接頭辞（`../50_詳細設計/06_DB設計規約.md §5`） |
| 冪等性・リトライ | 参照系は冪等。AI呼び出し（`analyze-meal`／`generate-menu`）は非冪等・**自動リトライしない**（従量課金のため）。429時のみ指数バックオフ |
| レート制限 | AI呼び出しはコスト・悪用防止のため制限（NFR-SEC-05）。閾値は実装時 |

日付を引数で受け取る関数は2つ。**どちらもアプリが決めた暦日をそのまま使う。**

| 関数 | 引数 | 意味 |
|---|---|---|
| `get_dashboard` | `p_today`（date・必須） | 当日。ゲージと今月の集計の基準になる |
| `get_protein_remaining` | `p_target_date`（date・必須） | 集計対象日。残量のリセット境界になる |

- Supabase は UTC で動く。`CURRENT_DATE` を使うと日本時間の深夜に日付がずれる。
- 端末TZで決める対象は3つ。`meal_logs.eaten_date`・残量のリセット・ヒートマップの日付。
- 海外にいるときは現地の日付で区切られる。端末の日付を変えると記録日もずれる。

## 2. 想定API一覧
> 📝 ここに本システムで想定するAPIを機能横断で棚卸しする（契約確定前の見取り図）。契約が固まったものは §3・§4 に落とす。{用途／想定メソッド・パス／対応FEAT-ID／対応EXT-ID／優先度（MUST/NICE）／確定状態（[確定]/[暫定]）}。

**方式（PostgREST／RPC／Edge Function）の割り当ては確定。** 型の細部が `[暫定]` である。

| 用途 | 方式・呼び出し | 対応FEAT | 対応IF | 優先 | 確定状態 |
|---|---|---|---|---|---|
| 器具(マシン)登録・更新・削除 | RPC `create_machine` / `update_machine` / `delete_machine` | FEAT-01 | 内部 | MUST | [暫定] |
| 部位→器具の絞り込み | PostgREST 埋め込み select（3ホップ＋`DISTINCT`＋`gym_id`） | FEAT-02 | 内部 | MUST | [暫定] |
| 種目マスタ管理 | PostgREST `training_menus`（select/insert/update/delete） | FEAT-01/03 | 内部 | MUST | [暫定] |
| ジム／入館 | PostgREST `gyms`・`gym_visits` | FEAT-01/04 | 内部 | MUST | [暫定] |
| AIメニュー提案 | Edge Function `generate-menu` | FEAT-03 | EXT-01 | MUST | [暫定] |
| トレーニング記録 | RPC `create_training_session` ＋ PostgREST `training_session_details` | FEAT-04 | 内部 | MUST | [暫定] |
| ダッシュボード集計 | RPC `get_dashboard` | FEAT-05 | 内部 | MUST | [暫定] |
| プロフィール（体重・目標） | PostgREST `users`（select/update） | FEAT-06 | 内部 | MUST | [暫定] |
| 必要タンパク質量の算出 | **APIなし**。Dart 純関数 `calcTargetProteinG`（`app/lib/domain/nutrition.dart`） | FEAT-07 | 内部 | MUST | [暫定] |
| 食事撮影→栄養価 | Edge Function `analyze-meal` | FEAT-08 | EXT-01 | MUST | [暫定] |
| 食事記録の保存 | PostgREST `meal_logs`（insert） | FEAT-08 | 内部 | MUST | [暫定] |
| タンパク質残量・不足分 | RPC `get_protein_remaining`（素の値を返す。残量算出は Dart） | FEAT-09 | 内部 | MUST | [暫定] |
| 食事マスタCSVインポート | RPC `import_foods` | FEAT-10 | 内部 | MUST | [暫定] |

## 3. エンドポイント一覧
> 📝 ここに全エンドポイント/IFを記載。公開エンドポイントと内部完結のIFを区別する。{メソッド/パス（内部はenqueue/client等）／対応EXT-ID／認証／概要}

外部に公開するエンドポイントは持たない。**すべて自アプリからの呼び出しである。**

| 方式 | 呼び出し | 対応IF | 認証 | 概要 |
|---|---|---|---|---|
| RPC | `rpc('create_machine', {p_gym_id, p_name, p_menu_ids})` | 内部 | 要 | 器具登録。`training_machines`＋`machine_menus` を1トランザクションで書く |
| RPC | `rpc('update_machine', {p_machine_id, p_gym_id, p_name, p_menu_ids})` | 内部 | 要 | 器具の改名・紐づけ差し替え（全置換） |
| RPC | `rpc('delete_machine', {p_machine_id})` | 内部 | 要 | 器具削除。中間行は FK の `ON DELETE CASCADE` で消える |
| PostgREST | `from('training_machines').select(埋め込み).eq('gym_id', …)` | 内部 | 要 | 器具一覧・1件再取得。ジム名・種目名・部位を同梱する。**`gym_id` でジムを絞り込む** |
| PostgREST | `from('training_menus').select(埋め込み).eq('body_part', …)` | 内部 | 要 | 部位で種目→中間→器具を絞り込む（`DISTINCT`・AI不使用・RULE-004） |
| PostgREST | `from('training_menus')` の select/insert/update/delete | 内部 | 要 | 種目マスタ（name・body_part・how_to） |
| PostgREST | `from('gyms')` の select/insert | 内部 | 要 | ジム管理。更新・削除は現行契約に無い |
| PostgREST | `from('gym_visits').insert(...)` | 内部 | 要 | 入館記録。**ヒートマップの集計には使わない**（塗り条件は §4.3） |
| Edge Function | `functions.invoke('generate-menu')` | EXT-01 | 要 | 部位＋器具から AI がメニュー提案（FEAT-03・§4.2） |
| RPC | `rpc('create_training_session', {p_performed_date, p_menu_ids, p_is_done})` | 内部 | 要 | トレーニング記録（セッション＋明細を1トランザクション・T01） |
| PostgREST | `from('training_session_details').update({is_done:true})` | 内部 | 要 | 実行済トグル（T02）。状態ガード `.eq('is_done', false)` 付き `[仮]` |
| RPC | `rpc('get_dashboard', {p_period, p_today, p_range_start, p_range_end, p_month_start, p_month_end})` | 内部 | 要 | ゲージ＋今月の回数＋ヒートマップの集計（FEAT-05・§4.3） |
| PostgREST | `from('users').select(...).single()` ／ `.update(patch)` | 内部 | 要 | 体重・氏名・目標回数（FEAT-06） |
| Edge Function | `functions.invoke('analyze-meal')` | EXT-01 | 要 | 食事画像→Gemini API→栄養4項目（保存はしない・§4.1） |
| PostgREST | `from('meal_logs').insert(...)` | 内部 | 要 | 食事記録の保存（栄養4項目＋日時・画像は非保存）。**摂取数は送らない**（ADR-0013） |
| RPC | `rpc('get_protein_remaining', {p_target_date})` | 内部 | 要 | 体重・当日摂取量・食品候補行を返す。残量と候補の選定は Dart（FEAT-09・§4.4） |
| RPC | `rpc('import_foods', {p_rows})` | 内部 | 要 | 食事マスタCSV取込（FEAT-10）。`ON CONFLICT (name) DO NOTHING` |

- RPC の定義は `supabase/migrations/*.sql` で版管理する（`../50_詳細設計/04_移行設計.md §3`）。
- 関数はいずれも `SECURITY INVOKER`。RLS を迂回しない。
- 引数に `user_id` を取らない。本人の解決は `auth.uid()` が行う（ADR-0005）。

**算出用の SQL 関数は持たない**（2026-08-08 確定・E群D）。

| 事項 | 内容 |
|---|---|
| RPC が返すもの | 素の値だけ。`weight_kg`・`intake_g`・候補行など |
| RPC が返さないもの | `target_g`・`remaining_g`・`rate_pct` などの計算済みの値 |
| 算出の場所 | Dart の純関数（`app/lib/domain/nutrition.dart` ほか）。正本は FEAT-07 §4.5 |
| 作らない関数 | `calc_target_protein_g`。SQL に RULE-001 を複製しないため |
| 理由（1） | 式が1か所になる。丸めの違いで画面ごとに数字がずれない |
| 理由（2） | SCR-05 で体重を変えると**通信せずに**目標値が即座に出る |

器具↔種目は**多対多**（中間テーブル `machine_menus`・正本＝`01_データモデル.md`）。契約への影響は次の2点。

| 対象 | 影響 |
|---|---|
| 器具登録・更新 | 単一の `menu_id` ではなく `p_menu_ids`（bigint配列・1件以上）を受け取る。1台の器具が複数部位に対応する |
| 部位での絞り込み | `training_menus` → `machine_menus` → `training_machines` の**3ホップ**を辿る。1台が同じ部位の種目を複数持つと重複するため **`DISTINCT` が必須** |

絞り込みの実装は次のとおり。詳細の正本は `../50_詳細設計/08_機能別詳細設計/FEAT-02_部位選択と器具絞り込み.md`。

| 事項 | 内容 |
|---|---|
| 起点 | `training_menus`。部位フィルタ `body_part` が起点の条件になる |
| 経路 | `machine_menus`（中間・埋め込み）→ `training_machines`（ネスト）→ `gyms`（さらにネスト） |
| 往復 | 1回のみ。器具ごとに引き直す N+1 を作らない |
| `DISTINCT` の位置 | 器具IDで畳み込む処理を Flutter 側の純関数で行う。畳まないと同じ器具が複数行に現れる |
| 埋め込み側で絞る場合 | 経路上の全段に `!inner` が要る（`machine_menus!inner` ＋ `training_machines!inner`） |
| ジムの絞り込み | **`gym_id` の条件を加える**（2026-08-08 確定）。埋め込みの `training_machines` 側で絞る |
| ジムが1件のとき | 選択UIを出さず、そのジムを自動で使う `[仮]` |

### 旧契約との対比（移行のための対応表）

旧版は Vercel + Next.js Route Handler（`/api/*`）を前提にしていた。**すべて置き換える。**

| 旧（Next.js Route Handler） | 新（Supabase） |
|---|---|
| POST `/api/machines` | RPC `create_machine` |
| GET `/api/machines?body_part=` | PostgREST 埋め込み select（3ホップ＋`DISTINCT`） |
| CRUD `/api/menus` | PostgREST `training_menus` |
| GET/POST `/api/gyms`・POST `/api/gym-visits` | PostgREST `gyms`・`gym_visits` |
| POST `/api/menus/generate` | Edge Function `generate-menu` |
| POST `/api/training-sessions` | RPC `create_training_session` |
| GET `/api/dashboard` | RPC `get_dashboard` |
| GET/PUT `/api/profile` | PostgREST `users` |
| POST `/api/meals/analyze` | Edge Function `analyze-meal` |
| POST `/api/meals` | PostgREST `meal_logs` |
| GET `/api/protein/remaining` | RPC `get_protein_remaining` |
| POST `/api/foods/import` | RPC `import_foods` |

- 旧契約の**平坦な応答形は残らない**。埋め込み select は入れ子で返る。
- 旧契約の HttpOnly Cookie も無くなる。JWT は端末が持つ（§1）。

## 4. IF別 契約
> 📝 各IFごとに、リクエスト／レスポンス／エラーの型を記載。実値は入れず型・必須/任意の枠のみ示す。

### 4.1 EXT-01 食事撮影→栄養価推定 `[暫定]`（FEAT-08）

旧 `POST /api/meals/analyze` は廃止。Edge Function `analyze-meal` に置き換わる。

| 項目 | 内容 |
|---|---|
| 呼び出し | `supabase.functions.invoke('analyze-meal', body: {...})` |
| 実体 | `POST {SUPABASE_URL}/functions/v1/analyze-meal` |
| Content-Type | `application/json`（リクエスト・レスポンスとも） |
| 画像の渡し方 | **base64 にして JSON ボディに載せ、直接POSTする**。Storage は使わない（ADR-0003） |
| ボディサイズ | 実測 最大約300KB。base64 化して約400KB |
| 認証 | 要。JWT は `supabase_flutter` が自動付与 |
| 冪等性 | 非冪等。自動リトライなし（従量課金のため） |
| 目標時間 | ≤20秒（NFR-PERF-04）。打ち切りは `AbortSignal.timeout(18_000)` `[仮]` |

```jsonc
// Request  functions.invoke('analyze-meal', body: …)   （型のみ・実データは書かない）
{
  "image_base64": "string 必須",   // 長辺1024pxへリサイズ済み。データURLの接頭辞は付けない（ADR-0003）
  "mime_type":    "string 必須"    // image/jpeg | image/png | image/webp  [仮]
}

// Edge Function 内部 → Gemini API（EXT-01）
//   POST .../v1beta/models/{model}:generateContent   [仮]（モデルIDは環境変数 GEMINI_MODEL）
//   generationConfig.responseSchema = 栄養4項目＋料理名   [仮]

// Response 200
{
  "food_name": "string",          // 表示専用・保存しない
  "dish_names": ["string"],       // 表示専用・保存しない
  "calories_kcal": "float(>=0)",
  "protein_g": "float(>=0)",
  "sugar_g": "float(>=0)",
  "fat_g": "float(>=0)"
}
// Error（共通契約） 400/401/402/413/415/422/429/500/502/504（§5）
```

- 画像・料理名は**保存しない**（ADR-0003）。画像は関数のメモリ上にのみ存在する。
- 保存は第2段の PostgREST `supabase.from('meal_logs').insert(...)`（栄養4項目＋日時）。
- 送る列は栄養4項目・`eaten_date`・`eaten_time` だけ。**摂取数の列は持たない**（ADR-0013）。
- `eaten_date` は Flutter が端末TZで決めて渡す（ADR-0014）。DB の現在日付を使わない。
- 解析結果は**手修正できない**。手入力の経路も持たない（ADR-0015）。操作は記録と撮り直しの2つ。
- 第1段（AI）と第2段（保存）は別呼び出し。外部I/Oをトランザクションの外に置くため。
- 第1段の結果は画面状態に保持し、**第2段だけを再送できる**UIにする（再課金の回避）。

### 4.2 EXT-01 AIメニュー提案 `[暫定]`（FEAT-03）

旧 `POST /api/menus/generate` は廃止。Edge Function `generate-menu` に置き換わる。

| 項目 | 内容 |
|---|---|
| 呼び出し | `supabase.functions.invoke('generate-menu', body: {...})` |
| 実体 | `POST {SUPABASE_URL}/functions/v1/generate-menu` |
| Content-Type | `application/json`（リクエスト・レスポンスとも） |
| 認証 | 要。JWT は `supabase_flutter` が自動付与 |
| 冪等性 | 非冪等。自動リトライなし（従量課金のため） |
| 目標時間 | ≤15秒（NFR-PERF-03）。打ち切りは `AbortSignal.timeout(13_000)` `[仮]` |

```jsonc
// Request  functions.invoke('generate-menu', body: …)   （型のみ・実データは書かない）
{
  "body_part":   "胸|背中|脚|肩|腕",   // 必須・enum（RULE-003）
  "machine_ids": ["bigint"]            // 必須・1件以上・重複なし
}

// Edge Function 内部
//   ① machine_ids から器具名・種目名をDB照会（決定的処理・AI不使用・RULE-004）
//   ② Gemini API（EXT-01・generateContent・構造化出力）   [仮]

// Response 200
{ "menus": [ { "name": "string", "how_to": "string" } ] }
// Error（共通契約） 400/401/402/429/500/502/504（§5）
```

- 部位→器具の絞り込み（決定的処理・DB照会）は AI 不使用（RULE-004/005）。生成のみ AI。
- 提案は**永続化しない**。採用時の登録は FEAT-01 の `training_menus` insert。
- 器具IDだけでなく**名称も**プロンプトへ渡す。IDはモデルにとって意味を持たないため。

### 4.3 内部 ダッシュボード集計 `[暫定]`（FEAT-05）

旧 `GET /api/dashboard` は廃止。RPC `get_dashboard` に置き換わる。

| 項目 | 内容 |
|---|---|
| 呼び出し | `supabase.rpc('get_dashboard', params: { ... })` |
| 実体 | Postgres 関数 `public.get_dashboard`（`SECURITY INVOKER`） |
| 認証 | 要。RLS が本人行のみに絞る |
| 冪等性 | 冪等（参照系）。リトライ安全 |
| キャッシュ | しない。呼び出しごとに再集計する（当日値が変わるため） |

| 引数 | 型 | 必須 | 内容 |
|---|---|---|---|
| `p_period` | `text` | 任意（既定 `month`） | `day` / `week` / `month` `[仮]`。**ヒートマップの表示範囲だけを変える** |
| `p_today` | `date` | 必須 | 「当日」の暦日。Flutter が端末TZで解決して渡す（ADR-0014） |
| `p_range_start` | `date` | 必須 `[仮]` | ヒートマップの表示範囲の開始日（閉区間） |
| `p_range_end` | `date` | 必須 `[仮]` | ヒートマップの表示範囲の終了日（閉区間） |
| `p_month_start` | `date` | 必須 | **今月の初日**。`training_count` の集計に使う |
| `p_month_end` | `date` | 必須 | **今月の末日**。同上 |

`p_range_*` と `p_month_*` は別物。前者はヒートマップの表示範囲、後者は今月の実施日数の集計範囲で、`p_period` の影響を受けない。

戻り値は3要素。**`p_period` が効くのは `heatmap` だけである。**

| キー | 内容 | `p_period` への依存 |
|---|---|---|
| `protein_gauge` | 当日のタンパク質ゲージ | **依存しない。常に当日**（2026-08-08 確定） |
| `training_count` | 今月の実施日数と目標回数 | 依存しない。常に今月 |
| `heatmap` | 日ごとの実施有無と種目名 | 依存する（`p_range_start`〜`p_range_end`） |

```jsonc
// 戻り値（json 1値・型のみ）
{
  "protein_gauge": {                 // 常に当日。体重が未設定なら protein_gauge ごと null
    "weight_kg": "float(>0)",        // users.weight_kg をそのまま返す
    "intake_g":  "float(>=0)"        // 当日の meal_logs.protein_g 合計。記録なしは 0
  },
  "training_count": {                // 今月の実施状況。p_period に依存しない
    "done_days": "int(>=0)",         // 今月の実施日数。heatmap と同じ条件で数える
    "target":    "int(>=0)"          // users.target_training_count（既定12・RULE-007）
  },
  "heatmap": [                       // p_range_start〜p_range_end の範囲
    { "date": "date", "done": "boolean", "menu_names": ["string"] }
  ]
}
```

画面が使う `target_g`・`rate_pct` は **Dart が算出する**（2026-08-08 確定）。SQL に RULE-001 を複製しないため。

| 項目 | 算出 |
|---|---|
| `target_g` | `weight_kg` を FEAT-07 の Dart 純関数へ渡す（RULE-001＝体重×2g） |
| `rate_pct` | `calcGaugeRatePct`。達成率100%で頭打ち（ADR-0002） |
| `protein_gauge` が null | 両方とも算出しない。ゲージの位置に体重登録の導線を出す |

- **本 RPC の契約は変更なし。** `protein_gauge` は元から素の値（`weight_kg`・`intake_g`）だけを返す。
- 目標値・達成率は戻り値に含まれない。含めない方針を確定として明記する。

ゲージは日単位で完結する。週・月の平均や累積は取らない。

| 事項 | 内容 |
|---|---|
| 期間の影響 | **受けない。`p_period` を変えてもゲージは当日のまま**（2026-08-08 確定） |
| 体重が未設定 | `protein_gauge` を `null` にして **200 を返す** `[仮]`。エラーにしない |
| そのときの他要素 | `training_count`・`heatmap` は通常どおり返す |

ヒートマップの塗り条件を確定した（2026-08-08）。

| 事項 | 内容 |
|---|---|
| 塗る | その日の `training_session_details.is_done` が **1件以上 true** |
| 塗らない | `training_sessions` の行があるだけの日（予定のみ・未実施） |
| 使わない | **`gym_visits`（入館履歴）**。入館は実施の証拠にならない |

`training_count` は目標回数の達成状況を返す（画面表示は「実施日数 / 目標回数」）。

| 項目 | 内容 |
|---|---|
| `done_days` | 今月のうち、上の「塗る」条件を満たす**日数**。ヒートマップと同じ集計元 |
| `target` | `users.target_training_count`。既定は12（RULE-007・FEAT-06） |
| 「今月」の範囲 | `p_today` が属する月。端末TZ基準（ADR-0014） |
| `target` が未設定 | サインアップ時に既定12が入るため通常は発生しない。発生時の表示は `[仮]` |

- ヒートマップは実施有無（2値）＋種目名（session→details→menus）。
- 返すのは**実施記録のある日だけ**。未実施日は Flutter が表示範囲から補完する。
- 失敗は正常応答に混ぜない。`RAISE EXCEPTION` で返す（§5.4）。

### 4.4 内部 タンパク質残量・不足分 `[暫定]`（FEAT-09）

旧 `GET /api/protein/remaining` は廃止。RPC `get_protein_remaining` に置き換わる。

**戻り値を素の値に差し替えた**（2026-08-08 確定・E群D）。残量と候補の選定は Dart が行う。

| 項目 | 内容 |
|---|---|
| 呼び出し | `supabase.rpc('get_protein_remaining', params: { ... })` |
| シグネチャ | `public.get_protein_remaining(p_target_date date)` |
| 実行権限 | `SECURITY INVOKER`・`STABLE`。`GRANT EXECUTE TO authenticated` |
| 認証 | 要。`auth.uid()` が解決できなければ 401 |
| 冪等性 | 冪等（参照系）。リトライ安全 |
| キャッシュ | しない。記録直後は必ず呼び直す（古い残量を出さない） |

| 引数 | 型 | 必須 | 既定 | 内容 |
|---|---|---|---|---|
| `p_target_date` | `date` | 必須 | — | 集計対象日。当日を Flutter が端末TZで決めて渡す（ADR-0014） |

- 旧契約の `p_limit` は**削除した**。提示件数 N（既定3）は Dart 側の定数になった。

```jsonc
// 戻り値（jsonb・型のみ）
{
  "weight_kg": "float(>0) | null",   // users.weight_kg をそのまま返す。未設定は null
  "intake_g":  "float(>=0)",         // 当日の meal_logs.protein_g 合計。記録なしは 0
  "foods_candidates": [              // RULE-005 の母集合。並べ替えず id 昇順で返す
    { "id": "bigint", "food_name": "string", "protein_amount": "float(>=0)" }  // 1食分あたり（ADR-0012）
  ]
}
```

計算済みの値を返さない。Dart が算出する値は次の3つである。

| 値 | 算出 |
|---|---|
| 目標値 `target_g` | `weight_kg` を FEAT-07 の Dart 純関数へ渡す（RULE-001） |
| 残量 `remaining_g` | `max(0, target_g − intake_g)`（RULE-002）。0でクランプ |
| 候補 `suggestions` | `foods_candidates` から差の絶対値昇順で N件（既定3）を選ぶ（RULE-005） |

- `protein_amount` は**1食分あたり**（ADR-0012）。残量とそのまま比較できる。
- `intake_g` は `protein_g` の単純合計。係数は掛けない（ADR-0013）。
- `foods_candidates` に `id` を含める。同値時の順序を `id` 昇順で決めるため。
- `foods` が0件でもエラーにせず `foods_candidates: []` を返す。
- DB列名 `foods.name` は `food_name` に写像する。旧契約の項目名を維持するため。
- 体重が未設定・不正でも **200 を返す**。`weight_kg` を `null` のまま載せ、判定は Dart が行う。
- 本 RPC は `RAISE EXCEPTION` を使わない。ERR-PROFILE-020 / 021 は Dart 側で起こす（FEAT-09 §6）。

## 5. 共通エラー応答契約
> 📝 ここに全API共通のエラー応答契約を記載。{形（error_code/message/retryable）／HTTPステータス方針／ERRの完全列挙の正本の所在}

### 5.1 応答の形は経路で2つに分かれる

| 経路 | サーバが返す形 | Flutter 側の扱い |
|---|---|---|
| Edge Function | `{ "error_code": "ERR-…", "message": "利用者向け日本語", "retryable": true }` | `FunctionException` の本文をそのまま採用 |
| PostgREST・RPC | PostgREST 形式 `{ "code", "message", "details", "hint" }`（いずれも string ／ `hint` は null 可） | `PostgrestException` を共通形へ写像する |

- PostgREST・RPC は Edge Function を通らない。**サーバが共通形を返さない。**
- 写像は `app/lib/data/error_mapper.dart` の1か所に閉じる（`../50_詳細設計/07_実装共通設計パターン.md §1`）。
- `retryable` は「**利用者が手動で再試行する価値があるか**」を表す。
- `retryable: true` はサーバが自動再送したことを意味しない。両者は別概念。
- 利用者向けメッセージに技術詳細を書かない。SQLSTATE・例外文言・モデルIDが該当する。

### 5.2 HTTPステータス方針（共通）

| HTTP | error_code | 意味 | retryable |
|---|---|---|---|
| 401 | `ERR-AUTH-001` | 未認証・JWT 失効・RLS 拒否（Supabase Auth） | false |
| 400 | `ERR-VALIDATION-001` | 入力バリデーション違反 | false |
| 402 | `ERR-AI-CREDIT` | Gemini API の課金無効・請求未設定 | false |
| 429 | `ERR-AI-RATE` | Gemini API のレート制限（分/秒） | true（バックオフ） |
| 429 | `ERR-AI-QUOTA` | Gemini API の日次クォータ超過 | false |
| 502 | `ERR-AI-SCHEMA` | 構造化出力が型不一致 | false |
| 504 | `ERR-AI-TIMEOUT` | AI応答タイムアウト | false |
| 500 | `ERR-AI-FAIL` | 上記以外の AI 失敗 | false |

- AI 失敗時の縮退は共通。**AI機能だけ止め、記録・閲覧は続ける**（NFR-AVAIL-05）。
- ただし食事記録は例外。**AI が失敗したその食事は記録できない**（手入力なし・ADR-0015）。
- 指摘として `01_データモデル.md §8-16` に残した。要件側の文言の見直しが要る。
- 通知は `ScaffoldMessenger.showSnackBar`。`retryable: true` のときだけ再試行アクションを付ける。
- 機能固有 ERR（`ERR-MACHINE-*` 等）は各 `../50_詳細設計/08_機能別詳細設計/FEAT-*.md §6` が割り当てる。

### 5.3 Gemini API（EXT-01）の ERR マッピング

**従来の想定は誤りだった。** 旧版は「残高切れは 429 に混ざって区別できない」としていた。
公式のエラーコード仕様で**区別できる**ことが 2026-08-08 に確認できた。判定材料は 400 `failed_precondition`。

| 事象 | Gemini の応答 | error_code | HTTP | retryable |
|---|---|---|---|---|
| レート制限（分/秒） | 429 `rate_limit_exceeded` | `ERR-AI-RATE` | 429 | **true**（指数バックオフ） |
| 日次クォータ超過 | 429 `quota_exceeded` | **`ERR-AI-QUOTA`** | 429 | **false** |
| 課金無効・請求未設定 | **400 `failed_precondition`** | `ERR-AI-CREDIT` | 402 | false |
| キー無効・権限なし | 401 `authentication` / 403 `permission_denied` | `ERR-AI-FAIL` | 500 | false |
| モデル不明 | 404 `not_found` / `model_not_found` | `ERR-AI-FAIL` | 500 | false |
| サーバ障害 | 500 `api_error` / 503 `service_unavailable` | `ERR-AI-FAIL` | 500 | false |
| タイムアウト | 504 `deadline_exceeded` | `ERR-AI-TIMEOUT` | 504 | false |
| 構造化出力が型不一致 | 200 だが検証失敗 | **`ERR-AI-SCHEMA`** | 502 | false |

本改訂で ERR を2つ新設した。

| 新設ERR | 新設の理由 |
|---|---|
| `ERR-AI-QUOTA`(429) | 日次クォータ超過。429 だが**当日は再送しても通らない**。`ERR-AI-RATE` と retryable が逆になる |
| `ERR-AI-SCHEMA`(502) | 構造化出力の検証失敗。呼び出し自体は成功している。`ERR-AI-FAIL` と原因が違い、切り分けないと調査できない |

- 判定順は (a) HTTP → (b) 通信例外 → (c) 構造化出力の検証。正本は `../50_詳細設計/03_外部連携IF/10_GeminiAPI連携.md`。
- 400 `invalid_request` / `parameter_unknown` は本PJの実装不備。`ERR-AI-FAIL`(500) に倒す。
- `ERR-AI-CREDIT` と `ERR-AI-QUOTA` は運用者への気付きが要る。利用者操作では直らない。
- 自動再試行の対象は `ERR-AI-RATE` だけ。他は再送しても結果が変わらないか、二重課金になる。

Edge Function 側の実行上限（2026-08-08 確認済み）。打ち切りは常に §4 の時間予算で決まる。

| 項目 | 値 |
|---|---|
| メモリ | 256 MB |
| CPU時間 | 2秒（非同期I/Oは含まない） |
| 実行時間 | 無料 150秒 ／ 有料 400秒 |
| リクエストボディ上限 | **未文書化**（下記 ⚠️。実測400KBで運用する） |

### 5.4 PostgREST・RPC 由来のエラー（SQLSTATE → ERR）

`PostgrestException` の `code` で分岐する。共通の扱いは次のとおり。

| `code` | 発生 | 共通の扱い | HTTP 相当 |
|---|---|---|---|
| `42501` | RLS 拒否 | `ERR-AUTH-001` | 401 |
| `PGRST301` ／ `AuthException` | JWT 失効・未ログイン | `ERR-AUTH-001` | 401 |
| `PGRST204` | 更新に未知の列を送った | `ERR-VALIDATION-001` | 400 |
| `PGRST116` | `.single()` が0行 | 機能別 ERR（不在・未作成） | 404 相当 |
| `23505` | UNIQUE 違反 | 機能別 ERR。`ON CONFLICT DO NOTHING` の箇所は成功扱い | 400 |
| `23503` | FK 違反 | **業務エラー**（使用中で削除できない）。500 に落とさない | 400 |
| `23514` | CHECK 違反 | 機能別 ERR | 400 |
| `P0001` | RPC の `RAISE EXCEPTION` | `message` に載せた ERR-ID をそのまま採用 | 400 / 500 |
| 上記以外 | 想定外の失敗 | 機能別の 500 系 | 500 |

- 機能別の接頭辞は FEAT-01=`ERR-MACHINE-*` / FEAT-04=`ERR-TRAINING-*` / FEAT-06=`ERR-PROFILE-*`。
- 同じく FEAT-08=`ERR-MEAL-*` / FEAT-09=`ERR-PROTEIN-*` / FEAT-10=`ERR-FOOD-*`。
- SQLSTATE を利用者へ出さない。`23505` の詳細も画面に出さない。
- SQLSTATE `PTxxx` を HTTP ステータス xxx へ写す PostgREST の挙動は `[仮]`（FEAT-05）。
- PostgREST・RPC 経路には相関IDが付かない（§1）。障害調査の手掛かりが Edge Function 経路より少ない。

- ERRの完全列挙（分岐網羅の母集合）は `60_テスト設計/02_RED母集合_受入基準・状態・エラー.md` を正本とし、各ERRにハンドラ＋テストを1対1で紐づける。

### 5.5 要確認事項

> ⚠️ 要確認（人間判断）: **`generateContent` はレガシー扱い**になっている。2026年6月に Interactions API が GA となり、新規プロジェクトにはそちらが推奨されている。`generateContent` は引き続きサポートされる。本改訂は `generateContent` のままとした。移行するかは人間が判断する。移行する場合は §4.1・§4.2 の内部呼び出しと §5.3 の写像を見直すことになる。

> ⚠️ 要確認（人間判断）: `ERR-AI-QUOTA`(429) は**当日中に回復しない**。`ERR-AI-RATE` と同じ「時間をおいて再試行」の文言だと、利用者が無駄に再操作する。文言と導線を分けるかを確定する。

> ⚠️ 要確認（人間判断）: `ERR-AI-TIMEOUT` の `retryable` が段5と食い違う。`../50_詳細設計/07_実装共通設計パターン.md §4` は `true` としている。本書は **`false`** を正とする。再送が二重課金になり、時間予算も超えるため。段5側の追随が要る。

> ⚠️ 要確認（人間判断）: `ERR-AI-SCHEMA`(502) と機能別 ERR が重複している。FEAT-08 は同じ事象を `ERR-MEAL-004`(422)、FEAT-03 は `ERR-MENU-004` に割り当てている `[仮]`。共通ERRへ寄せるか、機能別ERRを残して共通ERRを内部区分にとどめるかを確定する。

> ⚠️ 要確認（人間判断）: Edge Function の**リクエストボディ上限が未文書化**。`analyze-meal` は base64 後で約400KB のため詰まる公算は低いが、実装時に1回検証する。検索で出る「10MB」は**デプロイサイズ**であり別物。

> ~~⚠️ 要確認（人間判断）: ADR-0001・ADR-0002 が Vercel 前提のまま残っている。前者は Vercel AI Gateway、後者は Next.js + Mantine の採用決定。本書は Flutter + Supabase 構成へ改訂したが、**後継ADRが未起票**。ADR を起こして両者を Superseded にする必要がある。~~（**解決**・2026-08-08）
> **ADR-0010**（Flutter + Supabase）と **ADR-0011**（Gemini API 直接）を起票し Accepted にした。
> ADR-0001 は `Superseded by ADR-0011`、ADR-0002 は `Superseded by ADR-0010` に遷移済み。

> 関連: 外部連携の俯瞰＝`10_システム基本設計/04_外部連携.md` / データ契約＝`01_データモデル.md` / 実装IF仕様＝`50_詳細設計/03_外部連携IF/README.md` / 状態イベント＝`03_ドメインイベント.md`。
