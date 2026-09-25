# agentic-harness

[Claude Code](https://code.claude.com/docs) 向けのプロダクト開発ハーネスです。人間の **PO** が舵を取り、エージェントが実行します。流れは brainstorming → spec（OpenSpec）→ 実装計画 → サブエージェントによるテスト先行の実装 → 別コンテキストでの敵対的レビュー → PR → PO の受け入れ、です。実際のプロジェクトで作り、測りながら育てたハーネスを一般化しました。Claude Code・GitHub・サプライチェーンの現行の指針にも照らしています。

> 英語版の [README.md](README.md) が正本です。

## 含まれるもの

1 つのリポジトリから 2 つの経路で配ります。版は 1 本のタグでそろえます。

| 経路 | 運ぶもの | 更新方法 |
|---|---|---|
| **プラグイン** `harness@agentic-harness`（`plugins/harness/`） | hooks: `guard`（無条件ブロック）、`ask-gate`（PO の確認に回す）、`lint-on-edit`、`test-on-stop`。サブエージェント: `harness:implementer`、`harness:reviewer`。スキル: `harness:workflow`、`harness:review-loop`、`harness:mutation-check`、`harness:adopt` | `claude plugin update` |
| **Copier テンプレート**（`copier.yml`、`template/`） | プラグインでは運べないもの: `AGENTS.md`、`CLAUDE.md`（`@AGENTS.md` + Claude 固有の差分）、`.claude/rules/`、`.claude/settings.json`（permissions・sandbox・`HARNESS_*` の env・プラグインの版の固定）、CI の job `check`、Dependabot、PR テンプレート、OpenSpec の設定、状態・台帳・教訓の各ドキュメント、ブランチの ruleset | `copier update`（レビューできる PR になる） |

プラグインは公式マーケットプレイスの [Superpowers](https://github.com/obra/superpowers) に依存します。OpenSpec は OpenSpec 自身の CLI から入れます。

### hooks がすること

| hook | 挙動 |
|---|---|
| `guard`（Bash・Monitor・ファイル操作ツールの PreToolUse） | 次をブロックする: 再帰 + 強制の `rm`、force push（`+refspec` と `-uf` を含む）、`git reset --hard` / `--merge`、`git clean -f`、ツリー全体の checkout / restore、`git branch -D`、`--no-verify` / `commit -n` / `--no-gpg-sign`、`.env` 系ファイル（`.env.example` は除く）、認証情報のディレクトリ、`curl … \| sh` |
| `ask-gate`（Bash・Monitor の PreToolUse） | 次を PO の確認に回す: 保護ブランチへの push（保護ブランチ上での refspec 無しの push を含む）、リモートブランチの削除、`--all` / `--mirror` / `--prune`、`git worktree remove --force`、lockfile を変える install（pnpm・npm・yarn・bun・uv・pip・cargo） |
| `lint-on-edit`（PostToolUse） | 編集したファイルごとに `HARNESS_LINT_CMD <file>` を実行し、失敗をその場で直させる |
| `test-on-stop`（Stop） | ドキュメント以外が変わっていれば、ターンを終える前に `HARNESS_TEST_CMD` を実行する。失敗している間は作業を続けさせる |

## はじめ方

前提: Claude Code 2.1.277 以上、`jq`、`git`、[`uv`](https://docs.astral.sh/uv/)、`gh`、OpenSpec CLI。

```sh
# プロダクトのリポジトリで（既定ブランチが GitHub 上に既にあること）
git switch -c fix/adopt-agentic-harness
uvx copier@9.18.2 copy --vcs-ref v0.1.0 gh:joe-yama/agentic-harness .
claude            # 対話モードで信頼ダイアログを承認する。v0.1.0 に固定されたマーケットプレイスが登録される
claude plugin install harness@agentic-harness --scope project
```

`claude plugin marketplace add joe-yama/agentic-harness` は自分で実行しないでください。固定のない既定ブランチが同じ名前で登録されてしまいます。

続けて新しいセッションで、Claude に **`harness:adopt`** の手順 5 以降を実行させてください。このスキルが次を行います。

- OpenSpec を固定したスキルで用意する
- ブランチの ruleset を適用する（あなたの確認を取ってから）
- guard が効いていることを確かめる

リポジトリの作成も含めた手順の全体はスキルに書いてあります。

## 設定

テンプレートは次の変数を `.claude/settings.json` の `env` に書きます。コマンドが未設定なら hook は何もしないので、技術スタックを決める前からハーネスを導入できます。

| 変数 | 既定値 | 使うもの |
|---|---|---|
| `HARNESS_LINT_CMD` | 未設定（lint しない） | `lint-on-edit`。編集したファイルは最後の引数として渡す。コマンド文字列には埋め込まない |
| `HARNESS_LINT_PATTERN` | ドキュメント以外の全ファイル | `lint-on-edit`。リポジトリからの相対パスに対する拡張正規表現 |
| `HARNESS_TEST_CMD` | 未設定（テストしない） | `test-on-stop` |
| `HARNESS_DOC_PATTERN` | `\.(md\|txt)$\|^docs/\|^openspec/\|^\.claude/` | lint もテストも起こさないパス |
| `HARNESS_PROTECTED_BRANCHES` | `main` | `ask-gate`。空白区切り |

## 更新

```sh
git switch -c fix/harness-v0.2.0
uvx copier@9.18.2 update --vcs-ref v0.2.0      # .claude/settings.json のプラグインの固定も新しいタグに移る
grep -rnE '^(<<<<<<<|>>>>>>>) ' . --exclude-dir=.git   # 衝突は .rej ではなくファイル内に印として書かれる
```

次の順に進めてください。

1. 衝突の印を解消する
2. Claude Code を再起動して新しい固定を読ませる
3. `claude plugin update harness@agentic-harness` を実行する
4. PR を作り、CI とレビューで確かめる

auto mode の Claude は `.claude/settings.json` を書けません。Claude がマージ済みのファイルを用意し、あなたが置きます。

## セキュリティ上の注意

- **プラグインはあなたのユーザー権限で動きます。** インストールするタグの `plugins/harness/scripts/` を読んでください。hooks が必要とするのは `bash`・`jq`・`git` だけです。
- `HARNESS_*_CMD` の値は、リポジトリにコミットされた設定から読み、`bash -c` で実行します。値の変更はコードの変更と同じように扱ってください。
- 信頼していないリポジトリで `--bare` なしに `claude -p` を実行しないでください。headless モードでもコミット済みの hooks が動きます。
- hooks はコマンドの文字列を見ているだけで、仕掛け線であってサンドボックスではありません。OS レベルの境界として、テンプレートは Claude Code の sandbox を有効にします（認証情報のディレクトリは読めず、ネットワークは GitHub とパッケージレジストリに限定）。既知の穴と誤検知は次のとおりです。
  - 引用文字列もコマンドとして検査する（そのため `sh -c '…'` も捕まる）。守っているコマンドに言及しただけの引用文字列でも反応する（例: `git push origin main` を含む Issue 本文）。長い本文は `--body-file` で渡す
  - 変数から組み立てたコマンド、別のインタプリタ経由のコマンド（`python -c`、`node -e`）、省略形の長いオプション（`--har`）は見えない
  - `uv run` は確認なしに `uv.lock` を更新することがある
- 第三者の部品と固定の仕方:
  - Superpowers（MIT、公式マーケットプレイスが固定）
  - OpenSpec（MIT、`gh skill` でタグを固定）
  - Playwright MCP（Apache-2.0、版を完全固定。`ui_review` のときだけ入る）
  - GitHub Actions はすべてコミット SHA で固定し、Dependabot が更新する

## ユーザー設定に残すもの

マシンや個人に固有の方針は、共有するテンプレートに入れません。`~/.claude/settings.json` とユーザーレベルの hooks に置いてください。例:

- origin や `gh` の login が個人アカウントでないときに、`git push` や `gh` の書き込みの前に確認を求めるゲート
- コミット署名の設定
- モデルの既定値

## 版の付け方

タグ `vX.Y.Z`（テンプレート）と `harness--vX.Y.Z`（プラグイン。`claude plugin tag` で作る）は同じコミットを指します。プラグインの版は `plugins/harness/.claude-plugin/plugin.json` だけに書きます。変更履歴は [CHANGELOG.md](CHANGELOG.md) です。

## 開発

```sh
bash tests/all.sh   # shellcheck、hook の 177 ケース、lifecycle テスト、規則の変異テスト、マニフェスト + claude plugin validate、テンプレートの描画
claude --plugin-dir plugins/harness   # 開発中のプラグインを読み込む
```

`jq`・`git`・`uv`・`claude` CLI が必要です。hook の規則はそれぞれ `# rule:<id>` と `# end:<id>` の間に置きます。`tests/hooks/mutate.sh` が規則を 1 つずつ消し、どのテストも落ちなければ失敗します。

## クレジット

- [obra/superpowers](https://github.com/obra/superpowers) — brainstorming、計画、サブエージェント駆動開発、TDD
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — デルタ仕様とアーカイブによる spec 駆動の変更管理
- reviewer の過剰設計の観点は [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) の考え方に倣っています
- Anthropic, [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) と [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## ライセンス

[MIT](LICENSE)
