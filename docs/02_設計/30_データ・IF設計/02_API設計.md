---
status: draft
---

# API設計（IF契約） — okada-fit

> **目的**: 各IF（EXT-01〜）の**契約（リクエスト／レスポンス／エラー）**を定義し、契約テストの基準とする。
> **書き方**:（記入例は example-suido-fax の対応ファイル参照）実データは書かず、型（スキーマ）の枠だけ示す。契約はスキーマ（zod等）を単一ソースとし、エラーは共通契約で統一する。EXT-ID は不変（`../../01_要件定義/00_用語定義.md §3` ID付番規則）。実装ワイヤ・詳細は `50_詳細設計/03_外部連携IF/README.md` を正本とする。

> ⚠️ **本書はたたき台（2026-07-25 生成）**。岡田さんのレビューで最終確定する。前提: Next.js Route Handlers（`/api/*`）／Supabase Auth（全API認証必須）／AI呼び出しは EXT-01（Vercel AI Gateway）。

## 目次
1. [API共通規約](#1-api共通規約)
2. [想定API一覧](#2-想定api一覧)
3. [エンドポイント一覧](#3-エンドポイント一覧)
4. [IF別 契約](#4-if別-契約)
5. [共通エラー応答契約](#5-共通エラー応答契約)

## 1. API共通規約
> 📝 ここに全APIに共通する規約を記載。個別IFではなく横断ルールを固定する。{ベースURL・バージョニング（/v1等）／認証・認可（方式・トークン所在・スコープ）／共通リクエスト/レスポンスヘッダ（相関ID・冪等キー等）／ページング・ソート・フィルタの様式／日時・数値・enumの表現規約／冪等性・リトライの扱い／レート制限}。詳細な型は `../50_詳細設計/06_DB設計規約.md` の物理命名規約・`01_データモデル.md` のデータ契約に従う。

| 規約 | 方針 |
|---|---|
| バージョニング | ベース `/api`。単一クライアント（自アプリ）のため当面バージョンパスは持たない |
| 認証・認可 | **Supabase Auth**（ADR-0004）。全エンドポイント認証必須。トークンは HttpOnly Cookie（Supabase SSR）。DB側は **RLS で本人行のみ**（`user_id = auth.uid()`） |
| 共通ヘッダ | 相関ID（任意・ログ用）。書き込み系は冪等キー（任意） |
| ページング/ソート/フィルタ | データ小規模のため当面ページングなし。期間は `?period=day\|week\|month` / `?from=&to=`（date） |
| 日時・数値・enum 表現 | 日時=ISO 8601（`date`/`time`）。栄養値=`float`、回数等=`int`。enum=`body_part`（胸/背中/脚/肩/腕） |
| 冪等性・リトライ | 参照系は冪等。AI呼び出し（analyze/generate）は非冪等・**自動リトライしない**（従量課金のため）。429時のみ指数バックオフ |
| レート制限 | AI呼び出しはコスト・悪用防止のため制限（NFR-SEC-05）。閾値は実装時 |

## 2. 想定API一覧
> 📝 ここに本システムで想定するAPIを機能横断で棚卸しする（契約確定前の見取り図）。契約が固まったものは §3・§4 に落とす。{用途／想定メソッド・パス／対応FEAT-ID／対応EXT-ID／優先度（MUST/NICE）／確定状態（[確定]/[暫定]）}。

| 用途 | 想定メソッド/パス | 対応FEAT | 対応IF | 優先 | 確定状態 |
|---|---|---|---|---|---|
| 器具(マシン)登録 | POST/GET/PUT/DELETE `/api/machines` | FEAT-01 | 内部 | MUST | [暫定] |
| 部位→器具の絞り込み | GET `/api/machines?body_part=` | FEAT-02 | 内部 | MUST | [暫定] |
| 種目マスタ管理 | CRUD `/api/menus` | FEAT-01/03 | 内部 | MUST | [暫定] |
| ジム/入館 | POST `/api/gyms`・POST `/api/gym-visits` | FEAT-04 | 内部 | MUST | [暫定] |
| AIメニュー提案 | POST `/api/menus/generate` | FEAT-03 | EXT-01 | MUST | [暫定] |
| トレーニング記録 | POST `/api/training-sessions` | FEAT-04 | 内部 | MUST | [暫定] |
| ダッシュボード集計 | GET `/api/dashboard` | FEAT-05 | 内部 | MUST | [暫定] |
| プロフィール（体重・目標） | GET/PUT `/api/profile` | FEAT-06/07 | 内部 | MUST | [暫定] |
| 食事撮影→栄養価 | POST `/api/meals/analyze` | FEAT-08 | EXT-01 | MUST | [暫定] |
| 食事記録の保存 | POST `/api/meals` | FEAT-08 | 内部 | MUST | [暫定] |
| タンパク質残量・不足分 | GET `/api/protein/remaining` | FEAT-09 | 内部 | MUST | [暫定] |
| 食事マスタCSVインポート | POST `/api/foods/import` | FEAT-10 | 内部 | MUST | [暫定] |

## 3. エンドポイント一覧
> 📝 ここに全エンドポイント/IFを記載。公開エンドポイントと内部完結のIFを区別する。{メソッド/パス（内部はenqueue/client等）／対応EXT-ID／認証／概要}

| メソッド/パス | 対応IF | 認証 | 概要 |
|---|---|---|---|
| POST `/api/machines` | 内部 | 要 | 器具(マシン)登録（gym_id・name・`menu_ids[]`＝対応種目を1件以上） |
| GET `/api/machines?body_part=胸` | 内部 | 要 | 部位で種目→中間(`machine_menus`)→器具を絞り込み（`DISTINCT`・AI不使用・RULE-004） |
| GET/POST/PUT/DELETE `/api/menus` | 内部 | 要 | 種目マスタ（name・body_part・how_to） |
| GET/POST `/api/gyms` | 内部 | 要 | ジム管理 |
| POST `/api/gym-visits` | 内部 | 要 | 入館記録（ヒートマップの実施有無元） |
| POST `/api/menus/generate` | EXT-01 | 要 | 部位＋器具から AI がメニュー提案（FEAT-03） |
| POST `/api/training-sessions` | 内部 | 要 | トレーニング記録（実施日＋明細=種目×実行済） |
| GET `/api/dashboard?period=month` | 内部 | 要 | ゲージ＋ヒートマップの集計（FEAT-05） |
| GET/PUT `/api/profile` | 内部 | 要 | 体重・目標（必要タンパク質は体重×2gで算出） |
| POST `/api/meals/analyze` | EXT-01 | 要 | 食事画像→AI Gateway→栄養4項目（保存はしない） |
| POST `/api/meals` | 内部 | 要 | 食事記録の保存（栄養4項目・画像は非保存） |
| GET `/api/protein/remaining` | 内部 | 要 | 当日残量＝目標−摂取、不足を補う食品候補（FEAT-09） |
| POST `/api/foods/import` | 内部 | 要 | 食事マスタCSV取込（FEAT-10） |

器具↔種目は**多対多**（中間テーブル `machine_menus`・正本＝`01_データモデル.md`）。契約への影響は次の2点。

| 対象 | 影響 |
|---|---|
| 器具登録・更新 | 単一の `menu_id` ではなく `menu_ids[]`（bigint配列・1件以上）を受け取る。1台の器具が複数部位に対応する |
| 部位での絞り込み | `training_menus` → `machine_menus` → `training_machines` を辿る。1台が同じ部位の種目を複数持つと重複するため **`DISTINCT` が必須** |

## 4. IF別 契約
> 📝 各IFごとに、リクエスト／レスポンス／エラーの型を記載。実値は入れず型・必須/任意の枠のみ示す。

### 4.1 EXT-01 食事撮影→栄養価推定 `[暫定]`（FEAT-08）
```jsonc
// Request  POST /api/meals/analyze   （ブラウザ → サーバ, multipart/form-data）
{ "image": "File（クライアントで長辺1024pxにリサイズ済み・ADR-0003）" }

// サーバ内部 → AI Gateway（EXT-01, generateObject・model=google/gemini-3.5-flash）
//   schema: { food_name, dish_names[], calories_kcal, protein_g, sugar_g, fat_g }

// Response 200
{
  "food_name": "string",
  "dish_names": ["string"],
  "calories_kcal": "float",
  "protein_g": "float",
  "sugar_g": "float",
  "fat_g": "float"
}
// Error（共通契約） 402/429/500 等（§5）
```
- 画像・料理名は**保存しない**（ADR-0003）。保存は別途 `POST /api/meals`（栄養4項目のみ）。
- 非冪等・自動リトライなし。処理は ≤20秒想定（NFR-PERF-04）。上限に当たる場合は `streamText` 検討。

### 4.2 EXT-01 AIメニュー提案 `[暫定]`（FEAT-03）
```jsonc
// Request  POST /api/menus/generate   （ブラウザ → サーバ）
{ "body_part": "胸|背中|脚|肩|腕", "machine_ids": ["bigint"] }

// サーバ内部 → AI Gateway（EXT-01, generateObject）
// Response 200
{ "menus": [ { "name": "string", "how_to": "string" } ] }
```
- 部位→器具の絞り込み（決定的処理・DB照会）は AI 不使用（RULE-004/005）。生成のみ AI。

### 4.3 内部 ダッシュボード集計 `[暫定]`（FEAT-05）
```jsonc
// Request  GET /api/dashboard?period=month
// Response 200
{
  "protein_gauge": { "target_g": "float", "intake_g": "float", "rate_pct": "float(0-100)" },
  "heatmap": [ { "date": "date", "done": "boolean", "menu_names": ["string"] } ]
}
```
- ゲージは達成率100%で頭打ち（ADR-0002）。`target_g`＝体重×2g。ヒートマップは実施有無（2値）＋種目名（session→details→menus）。

### 4.4 内部 タンパク質残量・不足分 `[暫定]`（FEAT-09）
```jsonc
// Request  GET /api/protein/remaining
// Response 200
{
  "target_g": "float", "intake_g": "float", "remaining_g": "float(>=0)",
  "suggestions": [ { "food_name": "string", "protein_amount": "float" } ]  // foodsから不足を補う候補（DB照会・AI不使用）
}
```

## 5. 共通エラー応答契約
> 📝 ここに全API共通のエラー応答契約を記載。{形（error_code/message/retryable）／HTTPステータス方針／ERRの完全列挙の正本の所在}

- 全APIのエラーは `{ "error_code": "ERR-...", "message": "{利用者向け日本語}", "retryable": {boolean} }`。
- HTTPステータス方針（主なもの）:

| HTTP | error_code（例） | 意味 | retryable |
|---|---|---|---|
| 401 | ERR-AUTH-001 | 未認証（Supabase Auth） | false |
| 400 | ERR-VALIDATION-001 | 入力バリデーション違反 | false |
| 402 | ERR-AI-CREDIT | AI Gateway クレジット不足 | false |
| 429 | ERR-AI-RATE | AI/APIレート制限 | true（バックオフ） |
| 504/500 | ERR-AI-TIMEOUT / ERR-AI-FAIL | AI応答タイムアウト・失敗（縮退：記録/閲覧は継続・NFR-AVAIL-05） | 一部true |

- ERRの完全列挙（分岐網羅の母集合）は `60_テスト設計/02_RED母集合_受入基準・状態・エラー.md` を正本とし、各ERRにハンドラ＋テストを1対1で紐づける。

> 関連: 外部連携の俯瞰＝`10_システム基本設計/04_外部連携.md` / データ契約＝`01_データモデル.md` / 実装IF仕様＝`50_詳細設計/03_外部連携IF/README.md` / 状態イベント＝`03_ドメインイベント.md`。
