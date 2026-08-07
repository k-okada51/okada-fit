---
status: draft
---

# ADR-0011: AI 呼び出しを Google Gemini API 直接にする

> **目的**: 1つの設計決定を記録する雛形（1決定＝1ファイル）。本ファイルをコピーし `NNNN-短い決定名.md`（NNNN＝DEC番号のゼロ埋め）で起票する。
> **書き方**:（記入例は example-suido-fax の対応ファイル参照）実データは書かず、`{ }` を自プロジェクトの語に置き換える。**ステータスは `Proposed`（起票）→ `Accepted`（確定）→（必要時）`Superseded by ADR-NNNN`（後継で置換）** で遷移。決定を覆す場合は本ファイルを消さず、新ADRを起こして履歴を残す。確定後は要件・データモデル・アーキ等へ反映し、未決台帳のステータスを更新して初めてクローズ。

- **DEC-ID**: DEC-D02（採用モデルの tier）は維持し、AI呼び出しの**経路**を改訂。**ADR-0001 を置換する**
- **ステータス**: Accepted（岡田さん決定・2026-08-08）
- **日付**: 2026-08-08
- **決定者**: 岡田さん
- **前提TODO**: なし

## 背景・課題（Context）
> 📝 ここに何を・なぜ決める必要があるかを記載。関連する要件ID（FEAT/NFR/DM/IF/ST/ERR）を明記する。{決定が必要な理由／制約／前提}

- **対象要件**: FEAT-03（AIメニュー提案）・FEAT-08（食事撮影タンパク質計算）。連携は EXT-01。
- ADR-0001 は全 LLM 呼び出しを **Vercel AI Gateway 経由**に統一すると決めた。
- ADR-0001 は **Proposed のままで Accepted になっていなかった**。経路は未確定だった。
- **ADR-0010 で Vercel を使わないことが決まった。** Gateway も使えない。
- したがって AI 呼び出しの経路を決め直す必要がある。
- **モデルの選定は別の話である。** ADR-0001 の実測ベンチによる選定は生きている。
- **制約**: APIキーを端末に置かない（NFR-SEC-02）。画像入力と構造化出力に対応すること。

## 選択肢（Options / Alternatives）
> 📝 ここに検討した案を記載（採用案・却下案の両方）。{案／概要／長所／短所}

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| **A（採用）** | Edge Function から Gemini API を直接呼ぶ | 経路が1本で単純。APIキーがサーバ側にとどまる | **モデルフォールバックが無い。** 単一プロバイダ依存になる |
| B | 別のゲートウェイを経由する | 複数プロバイダを1キーで扱える。フォールバックが残る | 外部サービスが1つ増える。選定・契約・費用が要る。単一障害点も残る |
| C | 端末から Gemini API を直接呼ぶ | Edge Function が要らない | **APIキーが端末に露出する。NFR-SEC-02 に反する** |

## 決定（Decision）
> 📝 ここに採用案と、具体値・方式を実装が迷わない粒度で記載。{採用案／確定した具体値・方式}

案 **A** を採用する。**Supabase Edge Function から Google Gemini API を直接呼ぶ。**

| 項目 | 値 |
|---|---|
| 呼び出し元 | Supabase Edge Function（Deno）。`generate-menu`（FEAT-03）・`analyze-meal`（FEAT-08） |
| モデル | `gemini-3.5-flash`。環境変数 `GEMINI_MODEL` で設定値化し、コードに埋め込まない |
| 認証 | HTTPヘッダ `x-goog-api-key`。値は **Edge Function の環境変数のみ**（NFR-SEC-02） |
| メソッド | `generateContent` |
| 構造化出力 | `generationConfig.responseMimeType` ＋ `generationConfig.responseSchema` |
| 端末からの経路 | `supabase.functions.invoke(...)`。APIキーは端末に一切置かない |

### Gemini API のエラーコード（公式 api-errors ページで確認）

**従来の想定は誤りだった。** 「残高切れは 429 に混ざって区別できない」としていたが、**区別できる。**

| HTTP | error status | 意味 |
|---|---|---|
| 400 | `invalid_request` | リクエストが不正 |
| 400 | **`failed_precondition`** | **前提条件の未達。課金が無効な場合を含む** |
| 400 | `parameter_unknown` | 未知のパラメータ |
| 401 | `authentication` | APIキーが無い・不正・失効 |
| 403 | `permission_denied` | キーにこのリソースの権限が無い |
| 404 | `not_found` / `model_not_found` | リソース／モデルが見つからない |
| 429 | **`rate_limit_exceeded`** | **分/秒あたりの上限超過** |
| 429 | **`quota_exceeded`** | **日次クォータの超過** |
| 500 | `api_error` | サーバ側の想定外エラー |
| 503 | `service_unavailable` | 一時的な過負荷・停止 |
| 504 | `deadline_exceeded` | 期限内に完了しなかった |

### ERR マッピング（正本は `02_API設計.md §5`・`10_GeminiAPI連携.md`）

| 事象 | Gemini の応答 | 本PJの error_code | HTTP | retryable |
|---|---|---|---|---|
| レート制限（分/秒） | 429 `rate_limit_exceeded` | `ERR-AI-RATE` | 429 | **true**（指数バックオフ） |
| 日次クォータ超過 | 429 `quota_exceeded` | **`ERR-AI-QUOTA`（新設）** | 429 | **false**（当日は再送しても通らない） |
| 課金無効・請求未設定 | **400 `failed_precondition`** | `ERR-AI-CREDIT` | 402 | false |
| キー無効・権限なし | 401 `authentication` / 403 `permission_denied` | `ERR-AI-FAIL` | 500 | false |
| モデル不明 | 404 `model_not_found` | `ERR-AI-FAIL` | 500 | false |
| サーバ障害 | 500 `api_error` / 503 `service_unavailable` | `ERR-AI-FAIL` | 500 | false |
| タイムアウト | 504 `deadline_exceeded` | `ERR-AI-TIMEOUT` | 504 | false |
| 構造化出力が型不一致 | 200 だが検証失敗 | **`ERR-AI-SCHEMA`（新設）** | 502 | false |

**新設する ERR が2つある。**

| ERR | 理由 |
|---|---|
| `ERR-AI-QUOTA` | 日次クォータ超過。429 だが**再送しても当日は通らない**ため `ERR-AI-RATE` と分ける |
| `ERR-AI-SCHEMA` | 構造化出力の検証失敗。呼び出しは成功しており `ERR-AI-FAIL` と原因が違う |

## 根拠（Rationale）
> 📝 ここになぜその案かを記載。トレードオフ・却下理由を明示する。{選定理由／却下した案の理由}

**モデル選定は維持する**

- ADR-0001 は実測ベンチにより既定モデルを Gemini 3.5 Flash とした。この判断は変えない。
- 速度・コスト・精度の比較結果は経路の変更で無効にならない。
- **変わるのは経路だけである。** Gateway 経由から Edge Function 直接呼び出しへ移す。

**却下理由**

| 案 | 却下理由 |
|---|---|
| C | APIキーが端末に露出する。取り出されれば第三者に使われる（NFR-SEC-02） |
| B | 外部サービスを1つ増やす。個人開発の保守負担に見合わない（NFR-MAINT-01） |
| B | ゲートウェイ自体が単一障害点になる点は案Aと変わらない |

**直接呼び出しでも運用できる根拠**

- 課金無効・レート制限・日次クォータを応答から区別できる（上表）。
- Gateway の抽象化が無くても、必要な切り分けは自前で書ける。

## 影響（Consequences）
> 📝 ここに決定がもたらす影響を記載。{反映先ドキュメントの該当箇所／関連テスト観点／前提が崩れた場合の再検討条件}

- **モデルフォールバックが失われる（🔴 高）**:
  - ADR-0001 の `providerOptions.gateway.models` が使えない。
  - **単一プロバイダ依存になる。** Gemini API が落ちれば AI 機能は全面停止する。
  - 対応は**縮退のみ**（NFR-AVAIL-05）。AI機能だけ不可とし、記録・閲覧は継続する。
- ⚠️ 要確認（人間判断）: **`generateContent` はレガシー扱いになっている。**
  - 2026年6月に Interactions API が GA となり、新規プロジェクトにはそちらが推奨されている。
  - `generateContent` は引き続きサポートされる。
  - **本ADRでは `generateContent` を採る。移行するかの判断が別途要る。**
- ⚠️ 要確認（人間判断）: 日次クォータ超過（`ERR-AI-QUOTA`）は当日回復しない。利用者への伝え方を決める必要がある。
- 反映先:
  - `02_設計/10_システム基本設計/04_外部連携.md`（EXT-01 のプロトコル・認証）・`05_技術選定.md`（AI行）
  - `02_設計/30_データ・IF設計/02_API設計.md §5`（ERR マッピング・新設2件）
  - `02_設計/50_詳細設計/03_外部連携IF/10_GeminiAPI連携.md`（全体）
  - `02_設計/50_詳細設計/07_実装共通設計パターン.md`（リトライ・縮退）
  - `02_設計/50_詳細設計/08_機能別詳細設計/`: FEAT-03・FEAT-08
- 関連テスト観点: TC- は次の4点。
  - APIキーが端末側に存在しないこと
  - 400 `failed_precondition` が `ERR-AI-CREDIT` になること
  - 429 の2種が `ERR-AI-RATE` と `ERR-AI-QUOTA` に分かれること
  - 構造化出力の検証失敗が `ERR-AI-SCHEMA` になること
- 前提が崩れた場合の再検討条件: Gemini API の障害が頻発する場合。複数プロバイダのフォールバックを新ADRで再検討する。

## 反映チェック（クローズ条件）
> 📝 ここにクローズに必要なチェック項目を記載（確定後に消化する）。

- [ ] `04_外部連携.md` の EXT-01 を Gemini API 直接呼び出しに更新
- [ ] `05_技術選定.md` の AI 行から Vercel AI Gateway を外す
- [ ] `02_API設計.md §5` に ERR マッピングを反映し `ERR-AI-QUOTA`・`ERR-AI-SCHEMA` を追加
- [ ] `10_GeminiAPI連携.md` を `generateContent` 直接呼び出しで書き直す
- [ ] `07_実装共通設計パターン.md` のフォールバック記述を縮退のみに更新
- [ ] FEAT-03・FEAT-08 の AI 呼び出し記述を更新
- [ ] ADR-0001 のステータスを `Superseded by ADR-0011` に更新
- [ ] 関連テスト観点を確認
