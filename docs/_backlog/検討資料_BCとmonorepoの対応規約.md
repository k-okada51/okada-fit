# 検討資料：Bounded Context を軸にした「ドキュメント↔コード」対応規約（案）

> **位置づけ**: 本書は**検討資料（案）であり確定仕様ではない**。会議で §6 の論点を決めてから **共通プラグイン（規約）** へ正式規約化する。
> **狙い**: 設計ドキュメント（`ドキュメント構成ツリー.md`）とコード（monorepo）を **同じ Bounded Context 軸で1:1対応**させ、①人間の俯瞰・②AI駆動開発（設計↔実装の追跡）を両立する。

## 1. 中心原則（案）

> **1 Bounded Context = 1 ドキュメントフォルダ = 1 パッケージ**

- **Bounded Context（BC）** を、ドキュメント・コードに共通する**唯一の分割軸**にする。
- 「外部APIごとに分ける」という案は、この特殊ケース（外部連携＝独立Ber or ACLパッケージ）として本原則に包含される。

## 2. doc ↔ code 対応表（案）

| ドキュメント（設計） | コード（monorepo） | 中身 |
|---|---|---|
| `02_設計/30_データ・IF設計/{BC}/`（Domain） | `packages/{BC}/domain` | 集約・エンティティ・値オブジェクト・ドメインイベント |
| `02_設計/30_データ・IF設計/{BC}/`（Application） | `packages/{BC}/application` | アプリ層ユースケース（Orchestration） |
| `02_設計/30_データ・IF設計/02_API設計`（or BC別） | `packages/{BC}/api`（or `apps/gateway`） | エンドポイント・IF契約 |
| `02_設計/50_詳細設計/01_DB物理設計`（BC別展開可） | `packages/{BC}/db` | 物理テーブル・DDL・マイグレーション |
| `02_設計/50_詳細設計/03_外部連携IF`（連携先別） | `packages/{連携先}-adapter` | 外部API連携＝ACL（Portの実装） |
| `01_要件定義/00_用語定義`・共通プラグイン（コード規約） | `packages/shared`（最小） | 共有型・共通エラー契約 |

→ **同じ `{BC}` 名でフォルダとパッケージが縦串**になり、AIが「概念→実装」を迷わず対応付けられる。

## 3. monorepo レイアウト例（案）

```
<repo>/
├── apps/
│   └── gateway/                 # API公開面・複数BCのorchestration（合成層）
├── packages/
│   ├── {BC-A}/                  # 業務BC（domain / application / db）
│   ├── {BC-B}/
│   ├── {外部連携先}-adapter/     # 外部BC＝ACL（例: kintone-adapter, nexlink-adapter）
│   └── shared/                  # 共有カーネル（最小限）
├── ports/                       # BC間の公開contract（interface）
└── （tooling: pnpm workspaces / Nx / Turborepo のいずれか）
```

## 4. 依存ルール（案・BC軸の最大の効き所）

- **BC間の直接importを禁止**し、**公開contract（Port/interface）経由のみ**許可する。
- 外部システムは **adapterパッケージ（ACL）** に隔離し、中核ドメインは**Portだけに依存**（外部の都合が中核へ漏れない＝腐敗防止層）。
- これを **monorepoツールの module boundary lint で機械的に強制**する（例: Nx の `enforce-module-boundaries`、eslint import制約）。
  - → **ACL/Portが"設計図"だけでなく"コード"でも守られる**。BC軸でしか得られない利点。

## 5. スケール調整（過剰分割の回避）

- **小規模案件はBCを増やさない**。1〜3パッケージ＋`apps` で十分。
- **BCは将来サービスへ昇格可能**（monorepoでパッケージ開始 → 必要ならmicroservice抽出。strangler-friendly）。
- 例（`aic-suido-fax`・小規模）:
  ```
  apps/gateway/            # 窓口API（resolve・テナント分離・状態管理）
  packages/fax-sender/     # BC: PDF生成＋送達確認
  packages/nexlink-adapter/# 外部ACL: NEXLINK 6手順
  packages/kintone-adapter/# 外部ACL: パターンA
  packages/shared/         # 型・エラー契約
  ```

## 6. 会議で決める論点（★本資料の主眼）

| # | 論点 | 選択肢/論点 |
|---|---|---|
| Q1 | **BCの分割粒度・命名**を誰がいつ確定するか | `02_設計/30_データ・IF設計/01_データモデル` でBC一覧を先に正本化 → doc/code共通名にする |
| Q2 | **monorepoツール** | pnpm workspaces（軽量）／Nx（boundary lint・生成器が強力）／Turborepo（ビルドキャッシュ中心） |
| Q3 | **リポジトリ分離の方針**（請負の顧客分離との緊張） | 案件ごとに別monorepo／社内共通adapterだけ別monorepoで参照／全社1つ |
| Q4 | **共通コネクタ（adapter）の再利用** | 案件内packages／社内公開パッケージ（private registry）として横展開 |
| Q5 | **`apps` と `packages` の責務境界** | apps=合成/公開面のみ薄く、ロジックはpackagesに寄せる、で良いか |
| Q6 | **doc↔code命名の強制度** | 「同名必須」を規約化するか（lint/CIでチェックするか） |
| Q7 | **ports/contract の管理** | 独立`ports/`か各BCが公開する`index`か |

## 7. メリット / トレードオフ（判断材料）

**メリット**
- doc↔codeの1:1で、AIが設計から実装を生成・追跡しやすい（②に直結）。
- ACL/Portをlintで強制でき、外部依存の腐敗を構造的に防ぐ。
- 「外部APIごと」「共通コネクタ再利用」の要望を1つの軸で吸収。
- BC→サービス昇格が容易（段階的なマイクロサービス化）。

**トレードオフ / 前提**
- **BC境界を先に正しく切る必要**（誤るとパッケージ分割ごと崩れる）。
- **shared/kernel の肥大化リスク**（規律が要る）。
- monorepoツールの学習・CIオーケストレーション（Nx等）のコスト。
- 顧客案件の**アクセス制御・納品範囲**とmonorepo集約の緊張（Q3で方針決定）。

---

> 次アクション: 会議で §6（特に Q1 BC粒度・Q2 ツール・Q3 リポジトリ分離）を決定 → 本書を **共通プラグイン（規約 `doc-code-mapping`）** として正式規約化し、`ドキュメント構成ツリー.md` から参照する。
