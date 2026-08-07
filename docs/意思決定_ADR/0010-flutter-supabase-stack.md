---
status: draft
---

# ADR-0010: クライアントを Flutter、バックエンドを Supabase にする

> **目的**: 1つの設計決定を記録する雛形（1決定＝1ファイル）。本ファイルをコピーし `NNNN-短い決定名.md`（NNNN＝DEC番号のゼロ埋め）で起票する。
> **書き方**:（記入例は example-suido-fax の対応ファイル参照）実データは書かず、`{ }` を自プロジェクトの語に置き換える。**ステータスは `Proposed`（起票）→ `Accepted`（確定）→（必要時）`Superseded by ADR-NNNN`（後継で置換）** で遷移。決定を覆す場合は本ファイルを消さず、新ADRを起こして履歴を残す。確定後は要件・データモデル・アーキ等へ反映し、未決台帳のステータスを更新して初めてクローズ。

- **DEC-ID**: DEC-D01（フレームワーク・言語）・DEC-D05（UIライブラリ）を改訂。**ADR-0002 を置換する**
- **ステータス**: Accepted（岡田さん決定・2026-08-08）
- **日付**: 2026-08-08
- **決定者**: 岡田さん
- **前提TODO**: なし

## 背景・課題（Context）
> 📝 ここに何を・なぜ決める必要があるかを記載。関連する要件ID（FEAT/NFR/DM/IF/ST/ERR）を明記する。{決定が必要な理由／制約／前提}

- **対象**: 全FEAT（FEAT-01〜10）の実装基盤。
- ADR-0002 は Next.js（App Router）＋ TypeScript ＋ Mantine を確定した。
- その前提は**ブラウザで動く Web アプリ**だった。サーバ処理は Route Handlers に置いた。
- その後、ネイティブアプリ化の方針となった（2026-08-01）。配布は TestFlight。
- **アプリ化により Next.js のホスティングが不要になった。** Vercel を使う理由が消えた。
- ADR-0004 で DB・認証は Supabase に確定済み。サーバ処理の置き場も Supabase 側に寄る。
- **決定が必要な理由**: 上位文書（段1〜5）が Vercel 前提のまま残っている。
- **制約**: 個人開発1人（NFR-MAINT-01）。APIキーを端末に置かない（NFR-SEC-02）。

## 選択肢（Options / Alternatives）
> 📝 ここに検討した案を記載（採用案・却下案の両方）。{案／概要／長所／短所}

クライアントの候補は3つ。Flutter と React Native は 2026-08-01 に13軸で比較した。

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| **Flutter（採用）** | Dart。単一コードで iOS/Android | **ヘルス連携が `health` 1本で両OSに対応**。描画が端末差に左右されにくい | Dart を新たに学ぶ。TypeScript の資産を共有できない |
| React Native | TypeScript。React の資産を活かせる | 既存のTS資産と型を共有できる。学習コストが低い | ヘルス連携が iOS/Android で別ライブラリになる |
| Next.js のまま（ADR-0002） | Web アプリを継続する | 決定済みで手戻りが無い | カメラ・ローカル通知・ヘルス連携がブラウザの制約を受ける。Vercel が必要 |

## 決定（Decision）
> 📝 ここに採用案と、具体値・方式を実装が迷わない粒度で記載。{採用案／確定した具体値・方式}

**Flutter（Dart）＋ Supabase** を採用する。**Vercel は使わない。**

### 構成

```
Flutter アプリ（Dart・iOS先行・TestFlight配布）
  └ supabase_flutter
      ├ Auth              サインイン・JWT保持
      ├ PostgREST         テーブルを直接CRUD（RLSで保護）
      └ Functions.invoke  Edge Function 呼び出し

Supabase
  ├ Auth / PostgreSQL + RLS
  └ Edge Functions（Deno）
      └ Google Gemini API を直接呼ぶ（APIキーは環境変数）
```

- **Vercel・Next.js・Mantine・React・ブラウザは登場しない。**
- 配布は **TestFlight のみ**。ストア公開はしない。
- **iOS 先行**。Android は後回しにする。
- AI 呼び出しの経路は ADR-0011 で確定する。

### 呼び出し方式の割り当て

呼び出しは3方式（PostgREST 直接／RPC／Edge Function）。

| FEAT | 方式 | 名前 |
|---|---|---|
| 01 器具登録 | **RPC** | `create_machine` / `update_machine` / `delete_machine` |
| 02 部位絞り込み | PostgREST（埋め込み select・**`DISTINCT`**） | `training_menus` → `machine_menus` → `training_machines` |
| 03 AIメニュー | **Edge Function** | `generate-menu` |
| 04 トレーニング記録 | **RPC**＋PostgREST | `create_training_session` |
| 05 ダッシュボード | **RPC** | `get_dashboard` |
| 06 初期設定 | PostgREST | `users` |
| 07 必要量算出 | Dart 純関数＋SQL関数 | `calc_target_protein_g` |
| 08 食事撮影 | **Edge Function**＋PostgREST | `analyze-meal` |
| 09 残量・不足分 | **RPC** | `get_protein_remaining` |
| 10 CSV取込 | **RPC** | `import_foods` |

### 表記

| 種別 | 書き方 | 実体 |
|---|---|---|
| Edge Function | `supabase.functions.invoke('analyze-meal')` | `POST {SUPABASE_URL}/functions/v1/analyze-meal` |
| PostgREST | `supabase.from('meal_logs').insert(...)` | — |
| RPC | `supabase.rpc('get_dashboard', {...})` | — |

- **旧 `/api/*` の Route Handler パスはすべて置き換える。**

### UI（Flutter ウィジェット）

ADR-0002 の Mantine 部品は前提ごと無効になる。次の対応で置き換える。

| 旧（Mantine） | 新（Flutter） |
|---|---|
| `RingProgress` | `CircularProgressIndicator` ／ `fl_chart` |
| `SegmentedControl` | `SegmentedButton` |
| トースト | `ScaffoldMessenger.showSnackBar` |
| `Skeleton` | `shimmer` |
| `Modal` | `showDialog` / `showModalBottomSheet` |
| `NumberInput` | `TextFormField` ＋ `TextInputFormatter` |
| `FileInput` | `file_picker` |
| 撮影 | `image_picker`（`ImageSource.camera`） |
| チャート | `fl_chart` |

## 根拠（Rationale）
> 📝 ここになぜその案かを記載。トレードオフ・却下理由を明示する。{選定理由／却下した案の理由}

**Flutter を選んだ理由**

- Flutter と React Native を13軸で比較した（2026-08-01）。
- 差が付いたのは2軸だけだった。ヘルス連携（Flutter有利）と TS資産共有（RN有利）。
- **決め手はヘルス連携。** `health` パッケージ1本で iOS/Android の両方に対応できる。
- RN はヘルス連携が OS ごとに別ライブラリになる。保守が2本に増える（NFR-MAINT-01）。

**ADR-0002 を置き換える理由**

- ADR-0002 の前提「ブラウザで動く Web アプリ」が成り立たなくなった。
- アプリ化で Next.js のホスティングが不要になり、Vercel 依存が消えた。
- サーバ処理は Supabase Edge Functions に移す。ADR-0004 の Supabase 採用と一体になる。
- UIライブラリ（DEC-D05・Mantine）は React 前提のため、前提ごと無効になる。

## 影響（Consequences）
> 📝 ここに決定がもたらす影響を記載。{反映先ドキュメントの該当箇所／関連テスト観点／前提が崩れた場合の再検討条件}

- 反映先: **段1〜5 の全文書**。
  - 段1 `02_設計/10_システム基本設計/`（01_構成要素・02_境界・03_データフロー・04_外部連携・05_技術選定）
  - 段2 `02_設計/20_インフラ設計/`（01_システム構成・環境・02_IaC・デプロイ・可用性配置）
  - 段3 `02_設計/30_データ・IF設計/02_API設計.md`（呼び出し方式）
  - 段4 `02_設計/40_機能設計/01_シーケンス設計.md`
  - 段5 `02_設計/50_詳細設計/`（06_DB設計規約 §5・07_実装共通設計パターン・08_機能別詳細設計）
- **内部サービス名の改称**: `okada-fit-web` を3つに分ける。

| 名前 | 実体 |
|---|---|
| `okada-fit-app` | Flutter アプリ |
| `okada-fit-fn` | Supabase Edge Functions |
| `okada-fit-db` | Supabase（PostgreSQL・Auth） |

- **NFR-MAINT-02 が成立しなくなる（🔴 高）**:
  - 同要件は「以前のデプロイに即時ロールバックできる」前提で書かれている。
  - Vercel の即時ロールバックが使えなくなる。
  - アプリの切戻しには TestFlight の再配布と端末での再インストールが要る。
  - **即時性を満たせない。非機能要件（NFR-MAINT-02）の改訂が必要。**
  - 切戻しの所要時間を実測して記録する（`50_詳細設計/04_移行設計.md §5`）。
- 関連テスト観点: TC- は次の3点。
  - PostgREST の直接CRUD が RLS で本人行に限られること
  - `functions.invoke` が本人のJWTを引き継ぐこと
  - TestFlight ビルドが iOS 実機で起動すること
- 前提が崩れた場合の再検討条件: Android を先行させる必要が出た場合。Web 版を併設する要求が出た場合。

## 反映チェック（クローズ条件）
> 📝 ここにクローズに必要なチェック項目を記載（確定後に消化する）。

- [ ] 段1 の Vercel・Next.js・Mantine 表記を Flutter＋Supabase に更新
- [ ] 段2 のホスティング・デプロイを TestFlight 配布に更新
- [ ] 段3 `02_API設計.md` の `/api/*` を PostgREST・RPC・Edge Function に置換
- [ ] 段4・段5 の呼び出し方式とUI部品を Flutter 表記に統一
- [ ] 内部サービス名を `okada-fit-app` / `okada-fit-fn` / `okada-fit-db` に統一
- [ ] ADR-0002 のステータスを `Superseded by ADR-0010` に更新
- [ ] 【別ブランチ】NFR-MAINT-02 を TestFlight 配布の実態に合わせて改訂
- [ ] 関連テスト観点を確認
