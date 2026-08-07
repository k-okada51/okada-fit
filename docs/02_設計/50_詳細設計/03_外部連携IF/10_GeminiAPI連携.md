---
status: draft
---

# Google Gemini API 連携 — EXT-01

> Google Gemini API の連携手順・status写像・識別子ライフサイクル。**外部ワイヤ（既存API契約）は改変しない**。直列化・冪等・再送などの共通非機能は [`README.md`](README.md#共通-連携の直列化冪等再送) を参照。

> ⚠️ **本書はたたき台（2026-08-02 生成／2026-08-07 改訂）**。岡田さんのレビューで最終確定する。前提: EXT-01 は**状態を持たない同期リクエスト応答型**（非同期・識別子採番・ポーリングを伴わない）。本テンプレの §2・§3 は非同期連携を想定した枠のため、該当なしを明記したうえで代替の設計を置く。

## 1. Google Gemini API 連携手順（EXT-01）
> 📝 ここに外部API呼び出しの手順（複数ステップの連携シーケンス）を記載。認証ヘッダ・文字コード・改変禁止の前提を冒頭に明記。%% ここに記載（実データは書かない）

前提（冒頭で固定する）:

| 項目 | 値 |
|---|---|
| 呼び出し元 | Supabase Edge Function（Deno・TypeScript）。アプリから Gemini API を直接呼ばない |
| エンドポイント | `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` `[仮]` |
| 認証ヘッダ | `x-goog-api-key: $GEMINI_API_KEY` `[仮]` |
| キーの置き場所 | **Edge Function の環境変数（Secrets）のみ**🔒。アプリ・リポジトリには置かない（NFR-SEC-02） |
| モデル | `gemini-3.5-flash`。環境変数 `GEMINI_MODEL` で設定値化し、**コードにハードコードしない** |
| 実装 | Deno の `fetch` で直接呼ぶ。SDK は使わない |
| 文字コード・形式 | リクエスト／レスポンスとも UTF-8・`application/json` |
| 構造化出力 | `generationConfig.responseMimeType: "application/json"` ＋ `responseSchema` `[仮]` |
| 画像入力 | `contents[].parts[].inlineData: { mimeType, data(base64) }` `[仮]` |
| 応答検証 | Edge Function 内で zod により検証する |

- **外部ワイヤ（Gemini API の契約）は改変しない**。
- API仕様の細部（パス・フィールド名）は `[仮]`。実装時に公式ドキュメントで確認する。
- **呼び出しは2種類のみ**。いずれも1往復で完結する同期呼び出し。外部にジョブを作らない。

```
analyze-meal（FEAT-08・SCR-04） → Flutter → Storage → Edge Function:
  ① Flutter が長辺1024pxへリサイズし meal-photos バケットへアップロード
  ② Edge Function: JWT検証・入力検証（オブジェクトパス1件）
  ③ Storage から画像を取得し base64 化 → 固定プロンプトと組立（DBには書かない・ADR-0003）
  ④ generateContent → Gemini API（構造化出力）
  ⑤ zod 検証 → 栄養4項目を200で応答 ／ 同時に Storage の画像を削除
  → 監査ログ: 時刻・用途(meal_analyze)・成否・モデルID（NFR-SEC-AUDIT-01）／correlation_id を付与

generate-menu（FEAT-03・SCR-03） → Flutter → Edge Function:
  ⑥ Edge Function: JWT検証・入力検証（body_part, machine_ids）
  ⑦ 器具・種目名をDB照会しプロンプト組立（AI不使用・RULE-004）
  ⑧ generateContent → Gemini API（構造化出力）
  ⑨ zod 検証 → 提案メニューを200で応答（提案自体は永続化しない）
  → 監査ログ: 時刻・用途(menu_generate)・成否・モデルID（NFR-SEC-AUDIT-01）／correlation_id を付与
```

> 📝 ここに各手順のエンドポイント・内容・記録先を表で記載。認証は `{Authorizationヘッダ形式}`（機密はSecrets管理）。{#／手順／エンドポイント／内容／記録先}

| # | 手順 | エンドポイント | 内容 | 記録 |
|---|---|---|---|---|
| ① | FEAT-08 写真アップロード | `supabase.storage.from('meal-photos').upload(...)` | Flutter が長辺1024pxへリサイズして一時アップロード（ADR-0003）。バケット名 `meal-photos` `[仮]`。RLS で本人のみ書き込み可 | アプリログ（`service=okada-fit-app`） |
| ② | FEAT-08 認証・入力検証 | `supabase.functions.invoke('analyze-meal')` | Edge Function が Supabase Auth の JWT を検証（NFR-SEC-01）。オブジェクトパスの所有者一致・MIME・サイズを検証し、相関ID（`correlation_id`）を発番 | Edge Function ログ（`../05_ログ設計.md §6`） |
| ③ | FEAT-08 入力組立 | （内部） | Storage から画像を取得し base64 化。`inlineData` `[仮]` に載せて固定プロンプトと組み立てる。**画像をDBに書かない** | — |
| ④ | FEAT-08 栄養価推定 | `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` `[仮]` | `responseSchema`=`{ food_name, dish_names[], calories_kcal, protein_g, sugar_g, fat_g }` `[仮]` | **監査ログ**（時刻・用途・成否・モデルID／NFR-SEC-AUDIT-01・`../05_ログ設計.md §3`） |
| ⑤ | FEAT-08 応答整形・画像削除 | `supabase.storage.from('meal-photos').remove(...)` | zod 検証済みオブジェクトを 200 応答へ。**成否によらず画像を削除**（ADR-0003）。栄養4項目の保存は別途 `supabase.from('meal_logs').insert(...)` | アプリログ（所要時間・目標 ≤20秒 NFR-PERF-04） |
| ⑥ | FEAT-03 認証・入力検証 | `supabase.functions.invoke('generate-menu')` | JWT を検証。`body_part`（5種・RULE-003）と `machine_ids` を検証し、相関IDを発番 | Edge Function ログ |
| ⑦ | FEAT-03 入力組立 | （内部） | `machine_ids` から器具・種目名を照会（RLS で本人行のみ）しプロンプト化。**絞り込みはAI不使用**（RULE-004） | Edge Function ログ |
| ⑧ | FEAT-03 メニュー提案 | 同 ④ `[仮]` | `responseSchema`=`{ menus: [ { name, how_to } ] }` `[仮]` | **監査ログ**（時刻・用途・成否・モデルID／NFR-SEC-AUDIT-01） |
| ⑨ | FEAT-03 応答整形 | （内部） | zod 検証済みオブジェクトを 200 応答へ。提案は保存しない | アプリログ（所要時間・目標 ≤15秒 NFR-PERF-03） |

**写真の受け渡し（FEAT-08）** — 旧設計から構造ごと変わった箇所。

| 項目 | 内容 |
|---|---|
| 旧 | 画像を multipart で サーバへ直接POST していた |
| 新 | Flutter → Storage `meal-photos` → Edge Function が取得 → Gemini |
| 変更理由 | Edge Function のリクエストボディ上限が未文書化のため `[仮]` |
| Storage の位置づけ | 保管庫ではなく**転送路**。推論完了と同時に削除する（ADR-0003 の「保持しない」を維持） |

- 照会: **本連携では該当なし**（同期リクエスト応答で1往復完結し、外部に照会可能なジョブ／statusを作らないため）。したがって `../02_バッチ設計.md` のポーリングバッチは EXT-01 では使わない。
- エラー詳細の所在: **3階層**に分かれて返る。判定は (a) → (b) → (c) の順で行う。

| 階層 | 何が起きたか | 判定材料 |
|---|---|---|
| (a) HTTP | Gemini API が 401/403/429/5xx を返す | `fetch` の `response.status` と応答本文の `error.status` |
| (b) 通信・打ち切り | ネットワーク断、`AbortController` によるタイムアウト、中断 | 例外種別 |
| (c) スキーマ検証 | 200 は得たが構造化出力が型どおりでない | zod の検証結果 |

**(c) は Gemini API の障害ではなくモデル出力品質の問題**であり、(a)(b) と区別する。

**ERRマッピング**（`../../30_データ・IF設計/02_API設計.md §5` の共通契約へ写像。ERRの完全列挙の正本は段6 `../../60_テスト設計/02_RED母集合_受入基準・状態・エラー.md`）

| 階層 | 検知内容 | 返す error_code | HTTP | retryable | 備考 |
|---|---|---|---|---|---|
| (a) HTTP | 429（レート制限・クォータ超過） | `ERR-AI-RATE` | 429 | true | 指数バックオフのみ許容。自動連打はしない |
| (a) HTTP | 429 のうち課金上限・無料枠切れ `[仮]` | `ERR-AI-CREDIT` | 402 | false | 永続失敗。再送しない（[`README.md`](README.md#共通-連携の直列化冪等再送) の再送方針）。切り分け条件は未確定（下記 ⚠️） |
| (a) HTTP | 401/403（キー無効・失効・API未有効化） | `ERR-AI-FAIL` | 500 | false | **利用者の認証失敗ではない**ため `ERR-AUTH-001` へ写像しない（構成不備＝運用者向け） |
| (a) HTTP | 5xx（Gemini API 側の障害） | `ERR-AI-FAIL` | 500 | false | フォールバック先が無い。縮退のみ（NFR-AVAIL-05） |
| (b) 通信・打ち切り | 応答待ちタイムアウト・接続断・中断 | `ERR-AI-TIMEOUT` | 504 | false | 自動再送はしない。利用者の再操作に委ねる。打ち切り時間は NFR-PERF-04（20秒）／NFR-PERF-03（15秒）を基準とする `[仮]` |
| (c) zod検証 | 構造化出力が型どおりでない（必須欠落・型不一致） | `ERR-AI-FAIL` `[仮]` | 500 `[仮]` | false `[仮]` | **共通契約に定義が無いため本書で提案**（下記 ⚠️） |

> ⚠️ 要確認（人間判断）: **zodスキーマ検証失敗（AIが型どおり返さない）に対応する ERR が共通契約（`../../30_データ・IF設計/02_API設計.md §5`）に無い**。本書は「呼び出しは成功したが結果が使えない＝AI失敗」とみなし `ERR-AI-FAIL`(500)・`retryable: false` へ写像することを `[仮]` で提案する。選択肢は (1) `ERR-AI-FAIL` に含める（本案・ERRを増やさず単純だが原因の切り分けができない）、(2) 専用の `ERR-AI-SCHEMA` を新設し 502 で返す（切り分け容易・ERR母集合が増える）、(3) `retryable: true` として1回だけ再試行を許す（従量課金が二重に発生）。**課金とUXに直結するため人間判断が必要**。決定後、段6のRED母集合へ集約する。

> ⚠️ 要確認（人間判断）: `ERR-AI-CREDIT` の検知条件が未確定 `[仮]`。Gemini API は残高切れに 402 を返さず、クォータ超過と同じ 429（`RESOURCE_EXHAUSTED`）へ混ざる可能性が高い。区別できないと「429＝バックオフ再送」の方針で残高切れを叩き続けることになる。応答本文のどのフィールドで切り分けるかを実装前に確認する。

> ⚠️ 要確認（人間判断）: アプリ→Edge Function の契約が段3と乖離している。`POST /api/meals/analyze` は `analyze-meal`、`POST /api/menus/generate` は `generate-menu` に置き換わる。FEAT-08 は画像 multipart ではなく Storage のオブジェクトパスを渡す形へ変わる。`../../30_データ・IF設計/02_API設計.md §4.1・§4.2` の契約表の改訂が必要。

## 2. Google Gemini API status → 本PJ status 写像 `[仮]`
> 📝 ここに外部システムのstatus値を本PJの状態（ST）へ写像する表を記載。正本は `01_DB物理設計.md` のenum・`30_データ・IF設計/03_ドメインイベント.md`。{外部status／区分／本PJ status／遷移ID}

**本連携では該当なし。** 理由: EXT-01 は状態を持たない**同期リクエスト応答**であり、Gemini API 側に受付番号・ジョブ・status といった**照会可能な外部状態が存在しない**（受付→進行中→完了の遷移が発生しない）。よって外部status を本PJの ST へ写像する対象がない。

また **ST-01（`not_done`）／ST-02（`done`）はトレーニング明細の実行状態**であり、FEAT-04 の記録操作で遷移する（T01: 新規→ST-01、T02: ST-01→ST-02）。**EXT-01 の成否は ST-01/ST-02 を一切変更しない**（AI提案の採否と、実行済の記録は別操作）。

| Google Gemini API status | 区分 | 本PJ status | 遷移 |
|---|---|---|---|
| （存在しない） | 進行中 | 該当なし（同期呼び出しのため進行中状態を持たない。画面のローディングはアプリの一時状態） | 据え置き（遷移なし） |
| （存在しない） | 成功 | 該当なし（STを更新せず、結果を応答として返すのみ） | 遷移なし |
| （存在しない） | 失敗 | 該当なし（STを更新せず、ERRを返して縮退・NFR-AVAIL-05） | 遷移なし |

**モデルフォールバックは持たない `[仮]`** — 旧設計から失われた機能。

| 項目 | 内容 |
|---|---|
| 旧 | Gateway 側にモデル一覧を宣言し、Flash 失敗時に Pro へ自動切替していた |
| 新 | **切替を仲介する層が無い**。Edge Function から Gemini API を直接呼ぶため、宣言だけでのフォールバックはできない |
| 影響 | 既定モデルが失敗した時点で `ERR-AI-FAIL` を返し縮退する（NFR-AVAIL-05）。可用性は旧設計より下がる |
| 代替 | モデル切替が要るなら Edge Function 内に自前で実装する。分岐・再試行・二重課金の設計が別途必要になる |

**代替: AI応答の結果区分 → 本PJの振る舞い（EXT-01）** — status写像の代わりに、本連携ではこの表を実装の判断基準とする。

| 結果区分 | 検知階層 | 本PJの振る舞い（応答） | retryable | 縮退（NFR-AVAIL-05） |
|---|---|---|---|---|
| 成功 | (c) zod検証を通過 | 200（FEAT-08＝栄養4項目 ／ FEAT-03＝`menus[]`） | — | なし |
| レート制限 | (a) HTTP 429 | `ERR-AI-RATE`(429)＋SnackBar（時間をおいて再操作を促す） | true（指数バックオフ） | AI機能のみ一時不可 |
| クレジット不足 | (a) HTTP 429 のうち課金上限 `[仮]` | `ERR-AI-CREDIT`(402)＋SnackBar（運用者＝岡田さんへの気付きが必要） | false | AI機能のみ不可・記録／閲覧は継続 |
| タイムアウト | (b) 通信・打ち切り | `ERR-AI-TIMEOUT`(504)＋SnackBar（「解析に失敗しました」） | false（利用者の再操作） | AI機能のみ不可・記録／閲覧は継続 |
| スキーマ不一致 | (c) zod検証失敗 | `ERR-AI-FAIL`(500) `[仮]`＋SnackBar（撮り直し／再入力を促す） | false `[仮]` | AI機能のみ不可・記録／閲覧は継続 |
| Gemini API 不達・障害 | (a) HTTP 5xx／接続失敗 | `ERR-AI-FAIL`(500)＋SnackBar | false | AI機能のみ不可・記録／閲覧は継続 |

- FEAT-08 で AI が失敗しても、利用者が栄養値を**手入力して `meal_logs` に記録できる**ことを縮退の前提とする `[仮]`（NFR-AVAIL-05 の「記録は継続」）。
- FEAT-03 で AI が失敗しても、部位→器具の絞り込み（RULE-004・決定的処理・NFR-PERF-02）は影響を受けず継続する。
- SnackBar の表示は `ScaffoldMessenger.showSnackBar`（Flutter）。文言の正本は画面設計側に置く。

## 3. 照会用識別子 ライフサイクル
> 📝 ここに外部連携で払い出される識別子（照会キー）の採番→保存→照会→終端までのライフサイクルを記載。突合キーと照会キーが別なら二本立てである旨を明示。

**本連携では該当なし。** EXT-01 は同期リクエスト応答で完結するため、**外部で採番される照会用識別子（受付番号・ジョブID等）は存在しない**。したがって「採番→保存→照会→終端」のライフサイクルも、突合キーと照会キーの二本立ても発生しない。**DBに外部識別子を保持する列は持たない**（`../01_DB物理設計.md`。`meal_logs` は栄養値のみを保持し、画像も外部IDも保存しない・ADR-0003）。

代替として、**相関ID（`correlation_id`）**をリクエスト単位で発番し、EXT-01 呼び出しのログに紐づけて追跡可能にする（方式の正本は `../05_ログ設計.md §6`）。

| 段階 | 内容 |
|---|---|
| 発番 | Edge Function の入口（`analyze-meal` ／ `generate-menu`）で1リクエスト1件を発番。アプリが相関IDヘッダを送った場合はそれを採用する（共通ヘッダ・`../../30_データ・IF設計/02_API設計.md §1`） |
| 伝播 | Edge Function ログ、EXT-01 呼び出しの前後ログ、監査ログ（時刻・用途・成否・モデルID／NFR-SEC-AUDIT-01）に同一値を付与。エラーログにも付与し、利用者からの申告と突合できるようにする |
| 照会 | 障害調査時に **Supabase Edge Function ログ**を `correlation_id` で横断検索する（**外部への照会には使わない**＝Gemini API 側に問い合わせキーは無い） |
| 終端 | 応答の返却をもって終端。**DBに永続化しない**（相関ID用の列を業務テーブルに追加しない） |

**Storage オブジェクトパス（FEAT-08 の一時識別子）** — 外部識別子ではないが、ライフサイクルを固定する。

| 段階 | 内容 |
|---|---|
| 発番 | Flutter が `{user_id}/{uuid}.jpg` `[仮]` の形で採番し `meal-photos` へアップロードする |
| 受渡 | `analyze-meal` のリクエストボディでパスのみを渡す。画像本体は渡さない |
| 検証 | Edge Function がパス先頭の `user_id` と JWT の `sub` の一致を確認する（RLS と二重で防ぐ） |
| 終端 | 推論の成否によらず削除する。削除に失敗した場合の掃除手段は未設計（下記 §4 論点4） |

> ⚠️ 要確認（人間判断）: `correlation_id` の発番方式（UUIDv4 ／ Supabase 側リクエストIDの流用）と、応答ヘッダで利用者へ返すか否かが未確定 `[仮]`。ログの保存先・保持期間は `../05_ログ設計.md §4` の確定待ちであり、本書では方式を決めない。

## 4. 敵対的検証・要確認事項

| # | 論点 | 内容 | 重大度 |
|---|---|---|---|
| 1 | zodスキーマ検証失敗のERRが未定義 | §1 のマッピングで `ERR-AI-FAIL` `[仮]` としたが共通契約に定義が無い。専用ERR新設か既存流用かで段6のRED母集合が変わる | 🔴 高 |
| 2 | Gemini API への単一プロバイダ依存 | 連携先は EXT-01 の1件のみ。**モデルフォールバックの手段が無くなった**（Gateway 消滅）。Gemini API が落ちれば AI 機能は全面停止し、縮退以外の逃げ道が無い | 🔴 高 |
| 3 | `ERR-AI-CREDIT` の検知条件 | Gemini API は 402 を返さない見込み `[仮]`。課金上限が 429 に混ざると、README の再送方針（429=バックオフ再送／402=再送しない）が誤判定で崩れる | 🔴 高 |
| 4 | Storage の削除漏れ | 推論後の削除に失敗すると写真が `meal-photos` に残る。ADR-0003「保持しない」に反する。バケットのTTL・定期削除といった掃除手段が未設計 | 🔴 高 |
| 5 | タイムアウト値の根拠 | NFR-PERF-03/04（15秒／20秒）は**画面側の性能目標**。Storage 往復（アップロード＋取得＋削除）が加わり、Gemini API に割ける持ち時間は旧設計より短い。打ち切り値は未検証 | 🟡 中 |
| 6 | Edge Function の実行時間・ボディ上限 | 上限値が未確認 `[仮]`。写真を Storage 経由にした前提そのものが上限次第で変わる。実行時間上限が推論時間を下回ると FEAT-08 が成立しない | 🟡 中 |
| 7 | 縮退時の手入力フォールバック | FEAT-08 の AI 失敗時に栄養値を手入力できるかは画面設計（SCR-04）側の未確定事項。できない場合、NFR-AVAIL-05 の「記録は継続」が実質成立しない | 🟡 中 |
| 8 | プロバイダ側のデータ保持 | ADR-0003 は**自システムで保存しない**決定であり、Google 側の ZDR／学習利用の設定は未確認。無料枠は学習利用の対象になり得る `[仮]` | 🟡 中 |
| 9 | 監査ログの記録項目 | NFR-SEC-AUDIT-01 の「外部送信の記録」として時刻・用途・成否・モデルIDを記録する前提だが、`../05_ログ設計.md` 側の項目定義が未確定。プロンプト本文・画像を記録**しない**ことは ADR-0003 から必須 | 🟢 低 |

> ⚠️ 要確認（人間判断）: 論点2（単一プロバイダ依存）について、本書は「代替経路を持たず縮退のみ」を前提に記述している。別プロバイダへの二重化を行う場合は EXT-ID の追加を伴う設計変更となるため、岡田さんの判断が必要。

> ⚠️ 要確認（人間判断）: 本書は Flutter + Supabase 構成（Vercel 不使用）で記述している。一方 ADR-0001（Vercel AI Gateway 採用）・ADR-0002（Next.js + Mantine 採用）・`30_データ・IF設計/02_API設計.md`（`/api/*` の Route Handler 契約）は Vercel 前提のまま。後継ADRの起票と段3の改訂が必要。

> 関連: 共通・他の連携先＝[`README.md`](README.md) / 契約スキーマ＝`30_データ・IF設計/02_API設計.md` / ポーリングバッチ＝`../02_バッチ設計.md`。
