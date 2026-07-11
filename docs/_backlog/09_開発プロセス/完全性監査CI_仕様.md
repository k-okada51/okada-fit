# 完全性監査 CI 仕様（GitHub Actions）

> **目的**: 設計ドキュメントの**完全性**を GitHub Actions で機械監査する。**正本＝`00_プロジェクト概要/04_適用マトリクス.md` 内の「完全性マニフェスト（YAML）」**。CI は YAML の宣言とリポジトリのファイルを突合し、抜けを検出する。
> **配置**: 本リポでは `_backlog/09_開発プロセス/`（将来フェーズ）。採用時は `.github/workflows/docs-completeness.yml` ＋ `.github/scripts/check_docs_completeness.py` へ昇格。

## 1. 何を正とするか
- 各プロジェクトの `00_プロジェクト概要/04_適用マトリクス.md` に埋め込まれた **唯一の ```yaml ブロック**（`completeness:` ルート）。
- 人間向けの表と YAML は同一ファイル内で一致させる（乖離は運用で防止・必要ならCIで表↔YAML突合も追加可）。

## 2. 判定単位（完全性をどの粒度で見るか）
| 層 | 対象 | 判定単位 |
|---|---|---|
| L1 固定文書 | 標準の約40文書 | **ファイル単位**（`fixed_required` のパスが存在） |
| L2-G1 BC | ドメイン設計のBC群 | **BCフォルダ単位**（`bounded_contexts.list` の各BCが `required_files` を全て持つ・クラスは対象外） |
| L2-G2 機能 | 機能別仕様 | **FR単位**（`features.required` の各FRに `spec_glob` 一致ファイル） |

## 3. CI が検査するルール
1. `fixed_required` の各パスが**存在**する（無ければ FAIL）。
2. `fixed_not_applicable` の各項目に `reason` が**ある**（無ければ FAIL）。該当なしは存在を要求しない。
3. `bounded_contexts.list` の各 `{BC}` について `bounded_contexts.base/{BC}/` に `required_files` が**全て存在**する。
4. `features.required` の各 `{FR}` について `spec_glob`（`{FR}` を展開）に**1つ以上一致**するファイルがある。
5.（WARN）`base` 直下に `list` 未宣言のBCフォルダ＝**孤児**があれば警告。
6. **statusゲート（承認相当の完成強制）**: **`status: draft` / `ai-reviewed` / `wip` 以外**（＝status宣言なし＝**承認相当**）の .md に **未確定マーカー（`📝` / `{…}` / `<!-- TODO:aic -->` / `[仮]` / `🔧DESIGN`）が残っていたら FAIL**。前提: **main＝承認済み**（ブランチ保護＝PR＋メンバー承認）。＝「承認相当なのに未記入」を落とし、次工程AIが未確定値を実装に使う事故を防ぐ（未完成のまま載せるなら `status: draft` を明示して opt-out）。承認履歴（誰/いつ）は PR/git が正。
- 1件でも FAIL があれば PR を落とす（＝リリース承認基準 §A ドキュメントゲートの前段自動化）。

## 4. スターター：ワークフロー
```yaml
# .github/workflows/docs-completeness.yml
name: docs-completeness
on:
  pull_request:
    paths: ["**/*.md", "00_プロジェクト概要/04_適用マトリクス.md"]
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install pyyaml
      - run: python .github/scripts/check_docs_completeness.py
```

## 5. スターター：検査スクリプト
```python
# .github/scripts/check_docs_completeness.py
import re, sys, glob, pathlib, yaml

MATRIX = "00_プロジェクト概要/04_適用マトリクス.md"

def load_manifest(path):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    m = re.search(r"```yaml\s*(.*?)```", text, re.S)   # マトリクス内の唯一のyamlブロック
    if not m:
        sys.exit(f"[FAIL] {path} に完全性マニフェスト(yaml)が無い")
    return yaml.safe_load(m.group(1))["completeness"]

def main():
    c = load_manifest(MATRIX)
    errors, warns = [], []

    # 1. 固定文書（必須=適用）
    for p in (c.get("fixed_required") or []):
        if not pathlib.Path(p).is_file():
            errors.append(f"固定文書が無い: {p}")

    # 2. 該当なしは理由必須
    for item in (c.get("fixed_not_applicable") or []):
        if not item.get("reason"):
            errors.append(f"該当なしに理由が無い: {item.get('path')}")

    # 3. BC展開（フォルダ単位）
    bc = c.get("bounded_contexts") or {}
    base, req = bc.get("base"), (bc.get("required_files") or [])
    declared = bc.get("list") or []
    for name in declared:
        folder = pathlib.Path(base) / name
        if not folder.is_dir():
            errors.append(f"宣言BCのフォルダが無い: {folder}")
            continue
        for rf in req:
            if not (folder / rf).is_file():
                errors.append(f"BC必須構成が無い: {folder}/{rf}")
    # 5. 孤児BC（WARN）
    if base and pathlib.Path(base).is_dir():
        for d in pathlib.Path(base).iterdir():
            if d.is_dir() and d.name not in declared:
                warns.append(f"未宣言のBCフォルダ(孤児?): {d}")

    # 4. 機能展開（FR単位）
    ft = c.get("features") or {}
    gtmpl = ft.get("spec_glob", "")
    for fr in (ft.get("required") or []):
        if not glob.glob(gtmpl.replace("{FR}", fr)):
            errors.append(f"必須FRの仕様が無い: {fr} ({gtmpl})")

    # 6. statusゲート: 承認相当(status:draft/ai-reviewed/wip 以外)に未確定マーカーが無いか
    #    前提: main=承認済み（ブランチ保護）。未完成のまま載せるなら status:draft で opt-out。
    FORBIDDEN = ["📝", "<!-- TODO:aic -->", "[仮]", "🔧DESIGN"]
    WIP = ("draft", "ai-reviewed", "wip")
    for md in glob.glob("**/*.md", recursive=True):
        text = pathlib.Path(md).read_text(encoding="utf-8")
        fm = re.match(r"---\s*\n(.*?)\n---", text, re.S)      # 先頭frontmatter
        status = None
        if fm:
            m2 = re.search(r"(?m)^status:\s*(\S+)", fm.group(1))
            status = m2.group(1) if m2 else None
        if status in WIP:
            continue                                          # 作業中は exempt
        body = text[fm.end():] if fm else text                # 承認相当 → 未記入禁止
        hits = [t for t in FORBIDDEN if t in body]
        if re.search(r"\{[^}\n]*\}", body):                   # {プレースホルダ}
            hits.append("{…}")
        if hits:
            errors.append(f"承認相当なのに未確定マーカー残存: {md} → {hits}")

    for w in warns: print(f"[WARN] {w}")
    if errors:
        for e in errors: print(f"[FAIL] {e}")
        sys.exit(1)
    print("[OK] 完全性マニフェストとファイルは整合")

if __name__ == "__main__":
    main()
```

## 6. 昇格手順（採用時）
1. 上記2ファイルを `.github/` 配下へ配置（`.claude/settings.json` と同様、クローン雛形に含めても可）。
2. `04_適用マトリクス.md` の YAML を本PJ内容で埋める（fixed_required・該当なし・BC・FR）。
3. PRで自動監査。FAIL はマージ前に解消（＝ドキュメント充足ゲートの自動化）。

> 関連: 判定単位・宣言＝`00_プロジェクト概要/04_適用マトリクス.md` ／ 展開規約＝`../../template/ドキュメント構成ツリー.md`「大規模時の展開規約」 ／ 出口ゲート＝`../リリース承認基準_テンプレート.md` §A。
