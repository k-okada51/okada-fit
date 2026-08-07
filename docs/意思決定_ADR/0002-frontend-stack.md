---
status: draft
---

# ADR-0002: フロントエンド構成を Next.js + TypeScript + Mantine に確定する

> **目的**: 1つの設計決定を記録する雛形（1決定＝1ファイル）。本ファイルをコピーし `NNNN-短い決定名.md`（NNNN＝DEC番号のゼロ埋め）で起票する。
> **書き方**:（記入例は example-suido-fax の対応ファイル参照）実データは書かず、`{ }` を自プロジェクトの語に置き換える。**ステータスは `Proposed`（起票）→ `Accepted`（確定）→（必要時）`Superseded by ADR-NNNN`（後継で置換）** で遷移。決定を覆す場合は本ファイルを消さず、新ADRを起こして履歴を残す。確定後は要件・データモデル・アーキ等へ反映し、未決台帳のステータスを更新して初めてクローズ。

- **DEC-ID**: DEC-D01（Webフレームワーク・言語）を確定。**DEC-D05（UIコンポーネントライブラリ）を新規に起票し確定**
- **ステータス**: Superseded by ADR-0010（2026-08-08。旧: Accepted・岡田さん決定・2026-07-23）
- **日付**: 2026-07-23
- **決定者**: 岡田さん
- **前提TODO**: なし

## 背景・課題（Context）
> 📝 ここに何を・なぜ決める必要があるかを記載。関連する要件ID（FEAT/NFR/DM/IF/ST/ERR）を明記する。{決定が必要な理由／制約／前提}

- **対象**: 全FEAT（FEAT-01〜10）の実装基盤。特に FEAT-05（ダッシュボード）・FEAT-08（食事撮影）のUI要件を満たす必要がある。
- **決定が必要な理由**: DEC-D01 が `[仮]` のままで、UIライブラリに至ってはDEC番号すら無く、画面モック規約で「shadcn/ui採用」と暫定的に固定されていた。実装に進む前に、要件（下記）に基づく確定が必要。
- **要求されたUI要件（岡田さん提示）**: ダッシュボード（グラフ・チャート）／器具の登録／AI結果表示・トレーニング内容表示／画像のアップロード&プレビュー／数値入力／設定入力／モーダル・トースト・状態別表示／レスポンシブ／ダークモード
- **判断軸（岡田さん提示）**: ①必要な部品が揃うか ②Developer Experience ③ナレッジの多さ ④無料か
- **制約**: 個人開発1人（NFR-MAINT-01）／サーバ側でAI呼び出し・キー秘匿（NFR-SEC-02）／画面表示≤2秒（NFR-PERF-01）／AI応答≤20秒でローディング表示（NFR-PERF-03/04）／Vercel無料枠／AI基盤はVercel AI Gateway（ADR-0001）

## 選択肢（Options / Alternatives）
> 📝 ここに検討した案を記載（採用案・却下案の両方）。{案／概要／長所／短所}

### UIライブラリ（DEC-D05）
2026-07-23 に各公式ドキュメント＋開発者コミュニティをWeb調査（GitHub star・npm DL は公式APIで検証）。詳細な比較資料は MDV（`okada-fit フロントエンド構成 確定資料`）に保管。

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| **Mantine（採用）** | React UIライブラリ。charts/form/notifications を公式提供 | **円形ゲージ`RingProgress`・カレンダー型ヒートマップ`Heatmap`が公式にあり要件に直結**。オールインワンで継ぎ接ぎ不要。テーマ一括反映。MIT完全無料 | RSC非対応（全て`'use client'`）。star 31.5k と情報量は競合より少ない |
| shadcn/ui | Radix/Base UI + Tailwind のコピペ配布 | AIアシスト開発の親和性が最高、star 120k で情報量最大、軽量、MIT無料 | **カレンダー型ヒートマップがRechartsに無く外部ライブラリ/自作が必要**。所有モデルゆえ保守は自己責任 |
| MUI | npm週1000万DLの最大実績 | 実績・情報量が最大 | 画像アップロード公式なし。Emotion(CSS-in-JS)のSSRが複雑。**一部チャートがPro $299/年** |
| Chakra UI v3 | v3で部品が一通り揃う | 新規開発なら移行負債なし、MIT無料 | **v3でレンダリング速度が約2倍遅い報告**、Next.js Turbopackでハイドレーション不具合報告 |

### フレームワーク（DEC-D01）
| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| **Next.js App Router（採用）** | Reactフルスタック（フロント＋Route Handlers） | Vercel純正・**AI SDK公式が Next.js 前提**・情報量最大・サーバ側実行が標準内蔵 | Vercelロックイン。RSCの利点はMantineでは一部活きない |
| React Router v7（旧Remix） | Reactフルスタック（Viteベース） | Web標準志向・移植性が高い | AI SDKの作例が少ない。Vercel統合は純正でない |
| Vite + React(SPA) + 別APIサーバー | フロントとバックを分離 | 責務が明確・将来複数クライアントから利用可 | 2プロジェクト管理・CORS・型共有・デプロイ2箇所の手間 |
| Vite + React + Supabase直叩き（BaaS） | サーバコードをほぼ書かない | 最速で作れる | **AIキーをクライアントに置けない（NFR-SEC-02違反）ため成立しない** |

## 決定（Decision）
> 📝 ここに採用案と、具体値・方式を実装が迷わない粒度で記載。{採用案／確定した具体値・方式}

**Next.js（App Router）+ TypeScript + Mantine** を採用する。

- **フレームワーク**: Next.js（App Router）。サーバ処理は Route Handlers に集約し、AI Gateway 呼び出し・DB照会・CSVインポートを担う。
- **言語**: TypeScript（フロント/サーバ共通）。
- **UIライブラリ**: Mantine。導入パッケージは以下。
  ```bash
  npm i @mantine/core @mantine/hooks @mantine/charts recharts @mantine/form @mantine/notifications
  ```
  - `recharts` は `@mantine/charts` の必須依存（Mantine公式指定）
  - **`@mantine/dropzone` は不採用**（食事写真はスマホ撮影主体でドラッグ&ドロップを使わないため）
  - CSS import は **`@mantine/core/styles.css` を先頭**に、charts・notifications の順で読み込む
- **部品の割り当て**:

  | 要件 | 実装 |
  |---|---|
  | タンパク質ゲージ | `RingProgress` |
  | 筋トレ実施日＋種目 | `Heatmap`（ツールチップで種目名） |
  | 期間切替 | `SegmentedControl` |
  | 器具登録・設定 | `TextInput`/`MultiSelect`/`Switch`/`Select` ＋ `useForm` |
  | 数値入力 | `NumberInput` |
  | AI結果表示 | `Card`/`Text`/`Badge`/`Timeline` |
  | AI待機中 | `Loader`/`LoadingOverlay`/`Skeleton` |
  | モーダル | `Modal` |
  | トースト | `notifications.show()` |
  | 状態別表示 | 読込中=`Skeleton` ／ エラー=`Alert` ／ 空=`Text`+`Center` |
  | レスポンシブ | `AppShell`/`SimpleGrid`/breakpoint props |
  | ダークモード | `useMantineColorScheme` + `ColorSchemeScript` |
  | **画像アップロード** | **標準HTML** `<input type="file" accept="image/*" capture="environment">` ＋ `Image` |

- **ダッシュボード仕様（確定）**: ゲージは達成率100%で頭打ち（超過しても100%表示・残量は0が下限）／ヒートマップの色は**実施有無の2値のみ**（種目名はツールチップ）／**表示は常に1ヶ月**。※2026-07-25 更新: データ保持3ヶ月は撤回（全履歴を保持）。遡及範囲のUI仕様は別途。

## 根拠（Rationale）
> 📝 ここになぜその案かを記載。トレードオフ・却下理由を明示する。{選定理由／却下した案の理由}

- **UIライブラリ＝Mantine の決め手**: 要件の中核である「**円形ゲージ**」と「**カレンダー型ヒートマップ**」に直接対応する公式コンポーネント（`RingProgress`・`Heatmap`）を持つのは Mantine のみ。特に Heatmap は shadcn/ui（Recharts）に存在せず、外部ライブラリ追加か自作が必要になる。加えて `getTooltipLabel` により「実施日にホバーで種目名を表示」という要件も標準機能で満たせる。チャート・フォーム・通知が公式で揃うため継ぎ接ぎが不要で、テーマ変更が全体に一括反映される（ダークモード時にグラフの色も追従）。
- **shadcn/ui を却下した理由**: AIアシスト開発の親和性と情報量では優位だが、その強み（Rechartsの全機能に直接アクセスできる自由度）は**今回の定番的な可視化要件では活きない**。逆にヒートマップの自作コストが発生する。なお Mantine も MCPサーバー・`llms.txt`・Claude Code向けSkillsを公式提供しており、AI開発で大きく劣らない。
- **フレームワーク＝Next.js の決め手**: (1) Mantine採用によりReact系が必須。(2) AIキー秘匿（NFR-SEC-02）のためサーバ側コードが必須で、BaaS単独構成は成立しない。(3) 個人開発・単一Webアプリ・軽量なサーバ処理のため、分離構成の利点（複数クライアント・重いバックエンド）が該当せず、フルスタックが最適。(4) **ADR-0001 で AI Gateway（Vercel）を採用済みのため、「Vercelロックイン回避」という React Router v7 の主要な利点が実質的に価値を失っている**。AI SDK の公式サポートが Next.js 前提である点も加味した。
- **TypeScript の理由**: 採用ライブラリ（Mantine・AI SDK・Next.js）が全てTypeScript製で型定義を同梱しており、TSでなければ補完の恩恵を失う。またAIの構造化出力を `zod` で検証する設計（ADR-0001）はTSと組み合わせて初めて型安全を担保できる。
- **サーバ処理が「軽い」ことの確認**: 実行時間（AI応答6.3秒実測）・リクエスト起点・ステートレス・数百件規模・CPU負荷は中継のみ・キュー不要、の6軸すべてでサーバーレスの制約内に収まることを確認済み。

## 影響（Consequences）
> 📝 ここに決定がもたらす影響を記載。{反映先ドキュメントの該当箇所／関連テスト観点／前提が崩れた場合の再検討条件}

- 反映先:
  - 本worktree（設計層）: `05_技術選定.md`（言語・フレームワーク・UI・DEC台帳）
  - 【別ブランチ・波及】`docs-func-req`: **`00_画面モック規約.md` の「採用ライブラリ: shadcn/ui」を Mantine に更新**（モック正本 `src/mocks/{画面ID}.tsx` は React tsx のまま変更不要）
- **実装上の必須事項**:
  - **Mantine は全コンポーネントが `'use client'`（RSC非対応）**。App Router でのクライアント境界設計に注意する。
  - NFR-PERF-01（画面表示2秒）対策として、チャートは `next/dynamic` による遅延ロードを推奨。
  - ⚠️ Vercelサーバーレス関数の**実行時間上限**と、AI応答（最大20秒想定・NFR-PERF-04）の関係を実装前に確認する。上限に当たる場合は AI SDK の `streamText` によるストリーミング応答で回避する。
- 関連テスト観点: TC-（ダークモード時のチャート表示／レスポンシブ表示／AI待機中のローディング表示／状態別表示の網羅）
- 前提が崩れた場合の再検討条件:
  - Mantine の RSC非対応が性能要件（NFR-PERF-01）の達成を妨げる場合
  - Mantine のメンテナンス停滞・破壊的変更（Chakra v3 のような事例）が発生した場合
  - ダッシュボード要件が高度化し、Mantineの提供範囲を超えるカスタムチャートが必要になった場合 → Recharts を直接利用する構成へ移行を検討

## 反映チェック（クローズ条件）
> 📝 ここにクローズに必要なチェック項目を記載（確定後に消化する）。

- [x] 設計層 `05_技術選定.md` へ反映（DEC-D01確定・DEC-D05新規・UIをMantineに）
- [ ] `docs-func-req` ブランチで `00_画面モック規約.md` の採用ライブラリを Mantine に更新
- [ ] 後続設計PRで `40_機能設計` に SCR-01（ダッシュボード）の Mantine 前提のシーケンス/構成を反映
- [x] MDV 資料（フロントエンド構成 確定資料）を更新
