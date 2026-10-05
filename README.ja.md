# agentic-harness

[Claude Code](https://code.claude.com/docs)、[OpenAI Codex CLI](https://github.com/openai/codex)、[GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) 向けのプロダクト開発ハーネスです。人間の **PO** が舵を取り、エージェントが実行します。流れは設計の対話 → OpenSpec の change（spec、design、計画を兼ねる `tasks.md`）→ サブエージェントによるテスト先行の実装 → 別コンテキストでの敵対的レビュー → PR → PO の受け入れ、です。実際のプロジェクトで作り、測りながら育てたハーネスを一般化しました。エージェント・GitHub・サプライチェーンの現行の指針にも照らしています。既定は Claude Code で、Codex と Copilot CLI はリポジトリごとに選びます（[エージェント](#エージェント)）。

> 英語版の [README.md](README.md) が正本です。

## 含まれるもの

1 つのリポジトリから 2 つの経路で配ります。版は 1 本のタグでそろえます。

| 経路 | 運ぶもの | 更新方法 |
|---|---|---|
| **プラグイン** `harness@agentic-harness`（`plugins/harness/`） | hooks: `guard`（無条件ブロック）、`ask-gate`（PO の確認に回す）、`lint-on-edit`、`test-on-stop`、`subagent-start` / `subagent-stop`。monitor: `watchdog`。サブエージェント: `harness:implementer`（Sonnet、effort medium）、`harness:reviewer`（Opus、effort high）（Claude Code の場合。ほかのエージェントのモデルは `docs/harness/models.md`）。スキル: `harness:workflow`、`harness:design`、`harness:execute`、`harness:mutation-check`、`harness:adopt` | `claude plugin update` |
| **Copier テンプレート**（`copier.yml`、`template/`） | プラグインでは運べないもの: `AGENTS.md`、`CLAUDE.md`（`@AGENTS.md` + Claude 固有の差分）、`.claude/rules/`、`.claude/settings.json`（permissions・sandbox・`HARNESS_*` の env・プラグインの版の固定）、CI の job `check`、Dependabot、PR テンプレート、OpenSpec の設定、状態・台帳・教訓の各ドキュメント、ブランチの ruleset。Copier の質問 `agents`（`claude`・`codex`・`copilot`、既定は `claude`）で選んだエージェントごとに: Codex は `.codex/config.toml`・`.codex/rules/harness.rules`・`.codex/agents/harness-*.toml`、Copilot CLI は `.github/copilot/settings.json`・`.github/copilot-instructions.md`、両者に `.harness/env.json`（hook の設定）。`CLAUDE.md` と `.claude/settings.json` は `claude` を選んだときだけ描画する。`.claude/rules/` はどの選択でも描画する（Codex にはセッションの最初に読むよう指示する） | `copier update`（レビューできる PR になる） |

プラグインは別のプラグインに依存しません。OpenSpec は OpenSpec 自身の CLI から入れます。ハーネスが使うのは `/opsx:propose`、`/opsx:archive`、`/opsx:update`（と、`/opsx:archive` が内から呼ぶ `opsx/sync.md`）だけです。テンプレートの CI の job `check` は、`.claude/skills/openspec-*` やほかの `opsx` のコマンドがあると失敗します。`openspec update` が既定の profile でそれらを戻すためです。生成させないために、各自が OpenSpec のグローバルな profile を設定できます（リポジトリごとには持てません）: `openspec config set profile custom`、`openspec config set workflows '["propose","archive","update"]'`、`openspec config set delivery commands`。

テンプレートの `.claude/settings.json` は `superpowers@claude-plugins-official` を `false` にします。ユーザースコープに入っている Superpowers の指示が、ハーネスの指示と食い違わないようにするためです。リポジトリで Superpowers を使いたいときは `true` に変えてください。

### hooks がすること

| hook | 挙動 |
|---|---|
| `guard`（Bash・Monitor・ファイル操作ツールの PreToolUse） | 次をブロックする: 再帰 + 強制の `rm`、force push（`+refspec` と `-uf` を含む）、`git reset --hard` / `--merge`、`git clean -f`、ツリー全体の checkout / restore、`git branch -D`、`--no-verify` / `commit -n` / `--no-gpg-sign`、`.env` 系ファイル（`.env.example` は除く）、認証情報のディレクトリ、`curl … \| sh` |
| `ask-gate`（Bash・Monitor の PreToolUse） | 次を PO の確認に回す: 保護ブランチへの push（保護ブランチ上での refspec 無しの push を含む）、リモートブランチの削除、`--all` / `--mirror` / `--prune`、`git worktree remove --force`、lockfile を変える install（pnpm・npm・yarn・bun・uv・pip・cargo） |
| `lint-on-edit`（PostToolUse） | 編集したファイルごとに `HARNESS_LINT_CMD <file>` を実行し、失敗をその場で直させる |
| `test-on-stop`（Stop） | ドキュメント以外が変わっていれば、ターンを終える前に `HARNESS_TEST_CMD` を実行する。失敗している間は作業を続けさせる |
| `subagent-start` / `subagent-stop`（SubagentStart / SubagentStop） | watchdog のために、サブエージェントごとの記録（transcript のパス・開始・終了）をプラグインのデータディレクトリに残す。`subagent-stop` は、`harness:implementer` と `harness:reviewer` の返答がエージェントのファイルにある短いブロック（`STATUS`、reviewer の `VERDICT`、実在するレポートを指す `ARTIFACT`、8 行以内）でなければ一度だけ差し戻す。コントローラのコンテキストにはサブエージェント 1 つにつき数行だけが入り、レポートはファイルに残る |
| `watchdog`（プラグインの monitor） | 対話セッションごとに並走し、実行中のサブエージェントが transcript を 15 分書いていない（`STALL`）か、2 時間動き続けている（`TIMEOUT`）ときだけ 1 行出す。それ以外は何も出さないので、サブエージェントを待つ間トークンを使わない |

## エージェント

同じプラグインが 3 つのエージェントの hooks・サブエージェント・スキルを運びます。どのエージェントのファイルを渡すかは、Copier の質問 `agents` で決まります。確認した版: Claude Code 2.1.289、Codex CLI 0.160.0、Copilot CLI 1.0.91。

| | Claude Code | Codex CLI | Copilot CLI |
|---|---|---|---|
| `guard` | exit 2 と stderr の理由 | 同じ。ただしプラグインの hooks を信頼した後だけ。信頼していない hooks は読み飛ばされ、`codex exec` では何も表示されない。`apply_patch` はパスを検査し、パッチ本文はコマンドとして読まない | `COPILOT_CLI=1`（Copilot が hooks に設定する）のとき拒否を stdout の JSON（入れ子の `hookSpecificOutput` の deny だけ）で返し、モデルには `BLOCKED by harness guard (<rule>)` が届く（exit 2 の拒否の stderr はモデルに届かない）。Codex と Claude Code も、この変数を引き継いだときは同じ JSON を受け付ける（`git checkout .` と `rm -rf` はブロックされたまま）。パッチと `create` はパスで検査する |
| `ask-gate` | PO に確認する | 確認できない。`.codex/rules/harness.rules` が `rm`・`curl`・`wget`・`gh` の書き込み（マージ、リリース、Issue の編集と close、リポジトリの作成と削除、workflow の実行）・push・`git worktree remove --force`・lockfile の変更で確認を求め、`codex exec` ではそれらを拒否する。対話で確認が出るかは未確認 | 対話では確認する（未確認）。headless では拒否される |
| `lint-on-edit` | `decision: block` の JSON。エージェントがファイルを直す | 同じ | ブロックできない。lint の出力はコンテキストとして届く（トップレベルの `additionalContext`） |
| `test-on-stop` | テストが失敗している間は作業を続けさせる | 同じ | 同じ |
| サブエージェント | `harness:implementer`、`harness:reviewer` | `.codex/agents/` の `harness-implementer`、`harness-reviewer`、`harness-reviewer-intermediate`（プラグインのエージェントから `scripts/gen-codex-agents.sh` で生成）。子が親のコンテキストを引き継がないよう `fork_turns: "none"` で起動する | `harness:implementer`、`harness:reviewer`。呼び出しのたびに `docs/harness/models.md` の `model` と `reasoning_effort` を渡す |
| サブエージェントの監視 | 完了通知、Claude Code 自身の 10 分の stall timeout、`subagent-start` / `subagent-stop`、monitor `watchdog`（対話セッションのみ） | 返答ブロックとレポートファイルは指示だけ。watchdog なし | 返答ブロックとレポートファイルは指示だけ。watchdog なし |
| スキル | `harness:workflow`、`harness:design`、`harness:execute`、`harness:mutation-check`、`harness:adopt` | 同じ。`$harness:<skill>` で呼ぶ | 同じ。`harness:` の接頭辞なしで表示される（`workflow`、`design` …） |
| OpenSpec | `/opsx:propose`、`/opsx:archive`、`/opsx:update` | `.agents/skills` の `openspec-propose`、`openspec-archive-change`、`openspec-update-change`、`openspec-sync-specs` | `.agents/skills` の同じスキル（`.claude/skills` の `openspec-*` は CI の job `check` が拒否します） |
| 権限 / sandbox | `.claude/settings.json` の permissions と sandbox | `.codex/config.toml`: `approval_policy`、`sandbox_mode = "workspace-write"`、ネットワークは無効。信頼したプロジェクトでだけ読まれる | なし。リポジトリの権限も sandbox も無い |
| 自動導入 | 信頼ダイアログが固定したマーケットプレイスを登録する | なし。`codex plugin marketplace add joe-yama/agentic-harness --ref <tag>`、インストール、信頼（`harness:adopt`） | `.github/copilot/settings.json` が、信頼したときに固定したマーケットプレイスを登録する（未確認。`harness:adopt` が導入を確かめる） |

### 既知の穴

- **Codex の hooks は信頼するまで動きません。** それまで Codex はプラグインの hooks を読み飛ばし（`codex exec` では何も表示されません）、guard は動きません。プロジェクトの設定と rules も、`~/.codex/config.toml` で信頼したプロジェクトでしか読まれません。
- **Codex の hooks は確認できません。** `.codex/rules` は `rm`・`curl`・`wget`・`gh` の書き込み・push・`git worktree remove --force`・lockfile の変更で確認を求めます。対話では確認が出るはずですが未確認で、`codex exec` ではそれらのコマンドを拒否します。一致させるのはコマンドの前方だけです（保護ブランチ以外への push も含めて `git push` はすべて確認になり、`git -C . push` は一致しません）。Codex のネットワークは無効で、ホストの許可リストはありません。
- **Codex はエージェントのファイルの `sandbox_mode` を無視します。** reviewer は親のセッションの sandbox（書き込み可）で動きます。編集の禁止は指示に書いてあるだけで、それが唯一の歯止めです。
- **Copilot CLI にはリポジトリの権限も sandbox もありません。** guard・CI・ブランチの ruleset が歯止めです。
- **Copilot の PostToolUse はブロックできません。** lint のフィードバックはコンテキストとして届くので、モデルがそのまま進むことがあります。
- Copilot は `CLAUDE.md` もあると、AGENTS の規則を二重に表示することがあります。
- `.harness/env.json` は Codex と Copilot 用の `HARNESS_*` の設定です。Claude Code の hooks も、`.claude/settings.json` の `env` が設定していない変数についてはこれを読みます。編集するのは PO だけで（guard の規則 `harness-env` がエージェントのアクセスを拒否します）、guard を緩める `HARNESS_ALLOW_LEASE_PUSH` と `HARNESS_RM_RF_ALLOW` は入れません。パスは `<segment>/../` を畳んでから比べます。コマンドでは最後の要素にある glob だけを数えるので、`ls .harness/*/progress.md` は通ります。`.harness/` の後のブレース展開（`{a,b}`、`{x..y}`）は拒否し、`${name}` のパラメータは拒否しません（`cat .harness/${name}/progress.md` は通ります）。この規則はコマンドの文字列を見るので、`.harness` 自体にある glob（`.h*/env.json`）は見えません。
- `test-on-stop` は、テストが失敗している間、エージェントが PO への質問のために止まっていても、作業を続けさせます（3 つのエージェントすべて）。
- **watchdog は Claude Code の対話セッションでしか動きません。** プラグインの monitor は `claude -p` では動かず、そこで効くのは Claude Code 自身の stall timeout（`CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`）だけです。ハートビートはサブエージェントの transcript で、メッセージ 1 つごとに書かれます。1 回のモデルの応答が `HARNESS_WATCHDOG_IDLE` より長くストリームし続けると stall として報告されます。

## はじめ方

前提: Claude Code 2.1.277 以上（Codex CLI 0.160.0 以上、Copilot CLI 1.0.91 以上は選んだときだけ）、`jq`、`git`、[`uv`](https://docs.astral.sh/uv/)、`gh`、OpenSpec CLI。

```sh
# プロダクトのリポジトリで（既定ブランチが GitHub 上に既にあること）
git switch -c fix/adopt-agentic-harness
uvx copier@9.18.2 copy --vcs-ref v0.3.0 gh:joe-yama/agentic-harness .
git add -A && git commit -m "chore: adopt agentic-harness v0.3.0"
claude            # 対話モードで信頼ダイアログを承認する。v0.3.0 に固定されたマーケットプレイスが登録される
claude plugin install harness@agentic-harness --scope project
```

ほかのエージェントのファイルも描画するには、`--data agents="[claude,codex]"` を付けるか、質問 `agents` に答えます（既定は `[claude]`）。Codex と Copilot CLI のインストール・OpenSpec・検証の手順は `harness:adopt` にあります。`claude plugin marketplace add joe-yama/agentic-harness` は自分で実行しないでください。固定のない既定ブランチが同じ名前で登録されてしまいます。

続けて新しいセッションで、Claude に **`harness:adopt`** の手順 4 以降を実行させてください。このスキルが次を行います。

- OpenSpec を用意する（OpenSpec の余分なスキルとコマンドは入れない）
- ブランチの ruleset を適用する（あなたの確認を取ってから）
- guard が効いていることを確かめる

リポジトリの作成も含めた手順の全体はスキルに書いてあります。

## 設定

テンプレートは次の変数を `.claude/settings.json` の `env` に書きます。Codex と Copilot CLI では、hooks が `.harness/env.json` から読みます。同名の環境変数があればそちらが優先です。コマンドが未設定なら hook は何もしないので、技術スタックを決める前からハーネスを導入できます。

| 変数 | 既定値 | 使うもの |
|---|---|---|
| `HARNESS_LINT_CMD` | 未設定（lint しない） | `lint-on-edit`。編集したファイルは最後の引数として渡す。コマンド文字列には埋め込まない |
| `HARNESS_LINT_PATTERN` | ドキュメント以外の全ファイル | `lint-on-edit`。リポジトリからの相対パスに対する拡張正規表現 |
| `HARNESS_TEST_CMD` | 未設定（テストしない） | `test-on-stop` |
| `HARNESS_DOC_PATTERN` | `\.(md\|txt)$\|^docs/\|^openspec/\|^\.claude/` | lint もテストも起こさないパス |
| `HARNESS_PROTECTED_BRANCHES` | `main` | `ask-gate` と、`HARNESS_ALLOW_LEASE_PUSH` の `guard`。空白区切り |
| `HARNESS_WATCHDOG_IDLE` / `HARNESS_WATCHDOG_MAX` | `900` / `7200` | `watchdog`。`STALL` までの transcript 無更新の秒数と、`TIMEOUT` までのサブエージェント開始からの秒数（Claude Code のみ。`.harness/env.json` ではなくセッションの環境変数から読む） |

### guard の例外（オプトイン）

次の 2 つの変数は `guard` を緩めます。設定しない限り無効で、テンプレートは書きません。未設定なら `guard` の挙動はこれらが無いときとまったく同じです。使うリポジトリは自分で `.claude/settings.json` の `env` に足してください。

- `HARNESS_ALLOW_LEASE_PUSH=1`（ちょうど `1`。ほかの値は無効）は、force 系のオプションが `--force-with-lease=refs/heads/<branch>:<sha>` だけの `git push` を通す。ref は省略せずに書き、期待値は 7〜40 文字の 16 進のオブジェクト名で明示する。`--force-if-includes` は併用してよい。push はリモートを明示し、refspec はすべて `<src>:refs/heads/<branch>` の形で、lease と宛先は 1 対 1 で同じ ref を指さなければならない: `git push --force-with-lease=refs/heads/feature/x:<sha> origin HEAD:refs/heads/feature/x`。完全な ref を求めるのは、git が短い名前を独自に解決するから（`heads/main` は `refs/heads/main`、`v1` や `tag v1` はタグになりうる）。引き続きブロックするもの（`force-push`）: `--force`、`-f`（`-uf` の中も）、`--force-with` などの前方一致、値の無い `--force-with-lease`、期待値の無い `--force-with-lease=<ref>` や 16 進でない期待値（`$(git rev-parse …)` を含む）、`--force-if-includes` だけのもの、`+refspec`、リモートや refspec の無い push（`push.default` 頼み）、短い宛先や lease（`feature/x`、`heads/main`、`v1`、`tag v1`）、`HEAD` / `refs/tags/…` / `:branch` の宛先、lease の無い宛先、`HARNESS_PROTECTED_BRANCHES` に入っているブランチ、refspec の中のシェルの文字（`$B`、`$SRC:…`、`{a,b}`）、`--all`、`--mirror`、`--tags`、`--delete`、`-d`、`--prune`、`--repo`、その push 自身の `git -c` / `--config-env`、そして `GIT_CONFIG*` の変数（`GIT_CONFIG_COUNT`、`GIT_CONFIG_KEY_*`、`GIT_CONFIG_PARAMETERS`、`GIT_CONFIG_GLOBAL` など）に触れるか `git config` を実行するコマンドの中の lease push すべて。リポジトリ自身の git の設定とあなたのグローバルな設定は、そのまま信頼する。
- `HARNESS_RM_RF_ALLOW=<prefix>[:<prefix>...]` は、再帰 + 強制の `rm` を実行してよい絶対パスのディレクトリを並べる。通すのは、オペランドが 1 つ以上あり、すべてのオペランドが素の絶対パスで、シンボリックリンクを解決したうえでプレフィックスと等しいか、パスの区切りの単位でその下にあるときだけ（`/tmp/work/a` は `/tmp/work` の下、`/tmp/workx` は下ではない）。各オペランドの存在するいちばん深いディレクトリを `cd -P` で解決して残りをつなげ、プレフィックスも同じように解決する。プレフィックスの下にあって外を指すシンボリックリンクは拒否する。素のパスとは英数字と `._/@%+=,-` だけのもの: glob（`* ? [`）、`~`、`$`、バッククォート、波括弧、バックスラッシュ、引用符の中の空白、リダイレクト（`2>/dev/null`）を含まず、`..` や空の区切りも無い。BSD の `rm` と同じく、最初のオペランドの後の語はすべてオペランドとして扱う（`rm -rf /tmp/work/a -x` は拒否）。絶対パスでない、`/` である、区切りが 2 つ未満（`/tmp`）、`.`・`..`・空の区切りがある、ほかの文字を含む、解決すると `/` か区切り 1 つになる、のどれかに当たるプレフィックスは無視し、1 つも残らなければ未設定と同じ。引き続きブロックするもの（`rm-rf`）: 相対パス、一致しないオペランドが 1 つでもあるもの、`rm` が単純コマンドの先頭の語でない箇所があるコマンドの再帰 + 強制の `rm` すべて（`xargs rm -rf`、`find -exec rm -rf`、`sudo rm -rf`、`sh -c 'rm -rf …'`）。複合コマンドの `rm` はそれぞれ別に判定する。
- どちらの例外も、guard のほかの部分と同じくコマンドの文字列で判定する。仕掛け線であってサンドボックスではない。同じコマンドで（またはそれより前にシェルで）定義した関数やエイリアスは `rm` や `git` を置き換えられる。`HARNESS_RM_RF_ALLOW` では、どこかで `ln` を実行するコマンド（`/bin/ln`、`sudo ln`、`sh -c 'ln …'`）は拒否する。そのコマンドが作るリンクは、パスを検査する時点ではまだ存在しないから。1024 バイトを超えるオペランドも拒否する。見つけるのは文字どおりの `ln` のコマンドの語だけで、間接に書いた語（`l\n`、`$L`、`$(echo ln)`）や、同じコマンドでのほかのリンクの作り方（`perl -e 'symlink …'`、`cp -P`、`tar -x`）は見えない。検査と実行の間にほかのプロセスが変えたリンクも見えない。どれも既知の限界。

## 更新

```sh
git switch -c fix/harness-v0.3.0
uvx copier@9.18.2 update --vcs-ref v0.3.0      # .claude/settings.json のプラグインの固定も新しいタグに移る
grep -rnE '^(<<<<<<<|>>>>>>>) ' . --exclude-dir=.git   # 衝突は .rej ではなくファイル内に印として書かれる
```

次の順に進めてください。

1. 衝突の印を解消する
2. Claude Code を再起動して新しい固定を読ませる
3. `claude plugin update harness@agentic-harness` を実行する
4. PR を作り、CI とレビューで確かめる

auto mode の Claude は `.claude/settings.json` を書けません。Claude がマージ済みのファイルを用意し、あなたが置きます。

0.3.x から 0.4.0 への移行は後方互換がありません。手順の全体は `harness:adopt` にあります。要点は次のとおりです。

- `.claude/skills/openspec-*`、`.claude/commands/opsx/apply.md`、`opsx/explore.md` を消す
- `enabledPlugins` の Superpowers は `false` のままにし、`ref` を新しい版へ移す
- 設計文書と計画文書を別に書かず、OpenSpec の change（`tasks.md` が計画を兼ねる）にする。台帳は `.harness/<change>/progress.md`
- 別だったレビューのスキルは `harness:execute` に統合された
- `ci.yml` が衝突したら新しいステップを残す
- `docs/harness/models.md` が新しく来る

## セキュリティ上の注意

- **プラグインはあなたのユーザー権限で動きます。** インストールするタグの `plugins/harness/scripts/` を読んでください。hooks が必要とするのは `bash`・`jq`・`git` だけです。
- `HARNESS_*_CMD` の値は、リポジトリにコミットされた設定から読み、`bash -c` で実行します。値の変更はコードの変更と同じように扱ってください。
- Codex と Copilot CLI のプラグインの hooks も、あなたの権限で動きます。Codex が信頼を求めたときに hooks を確認してください。信頼したプロジェクトの設定と rules は、あなたとして実行されます。
- `.harness/env.json` は Claude Code を含むすべてのエージェントの hooks が読みます（`.claude/settings.json` の `env` が設定していない `HARNESS_*` の変数）。その `HARNESS_LINT_CMD` と `HARNESS_TEST_CMD` は `bash -c` で実行されます。変更は `.claude/settings.json` の変更と同じように確認してください。guard がエージェントの編集を防ぎ、編集するのは PO です。
- 信頼していないリポジトリで `--bare` なしに `claude -p` を実行しないでください。headless モードでもコミット済みの hooks が動きます。
- hooks はコマンドの文字列を見ているだけで、仕掛け線であってサンドボックスではありません。OS レベルの境界として、テンプレートは Claude Code の sandbox を有効にします（認証情報のディレクトリは読めず、ネットワークは GitHub とパッケージレジストリに限定）。既知の穴と誤検知は次のとおりです。
  - 引用文字列をコマンドとして検査するのは、`-c`（`sh -c '…'`、`bash -lc "…"`。間にオプションがあってもよい: `bash -c -- '…'`）と `eval` の直後、シェルへの here-string（`bash <<< '…'`）、`watch` と `ssh <host>` の引数だけ。`grep`・`wc`・`head` などの `-c` はフラグとして扱う。それ以外の引用文字列（コミットメッセージ、grep のパターン、Issue 本文）はデータとして扱い、二重引用符の中のコマンド置換もデータになる（`echo "$(rm -rf x)"` は通る）
  - 変数から組み立てたコマンド（`X=rm; $X -rf y`）と、別の言語のコード（`node -e`、`perl -e`、`python -c` の中の `os.system('…')`）は見えない
  - 認証情報のディレクトリ名と `.env` の名前は、データも含めてコマンド文字列のどこにあっても拒否する。`~/.ssh` や `.env` に触れたコミットメッセージ、`grep -rn ".ssh" docs`、`grep -rn .aws README.md`、プロジェクト内の `.aws/…` のパス（`.aws/` で始まる語）も拒否される。例外は `.env.example` と、`jq` / `yq` / `gojq` のフィルタ（`jq '.env' …` は通る）。heredoc の本文は行ごとに検査されるので、長い本文は `--body-file` で渡す
  - 捕まえないもの: `jq -f .env`（フィルタとして読むので、jq のエラーに `.env` の一部が出うる）と、`:` の後の認証情報のディレクトリ（`git show HEAD:.ssh/id_rsa`）
  - 守っている長いオプションの前方一致は、そのオプションとして扱う（git 2.55 と同じく `git reset --h` は `--hard`）。git が曖昧として拒む前方一致（`git push --fo`）も拒否する
  - 64 KiB を超えるコマンドは検査しない。guard は拒否し、ask-gate は確認を求めるので、ファイルに書いてそのファイルを実行する。1 つのコマンドが 16 を超えるディレクトリから push するときも、ask-gate は確認を求める
  - `uv run` は確認なしに `uv.lock` を更新することがある
- 第三者の部品と固定の仕方:
  - OpenSpec（MIT、CLI）
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
bash tests/all.sh   # shellcheck、Codex のエージェントファイル、hook のケース（tests/hooks/cases.tsv）、lifecycle テスト、hook の所要時間、規則の変異テスト、マニフェスト + claude plugin validate、テンプレートの描画
claude --plugin-dir plugins/harness   # 開発中のプラグインを読み込む
```

コミットの前は `tests/lint.sh`・`tests/hooks/run.sh`・`tests/hooks/lifecycle.sh`（テンプレートを変えたときは `tests/template/run.sh`、`plugins/harness/agents/*.md` を編集したときは `bash scripts/gen-codex-agents.sh` の後に `tests/codex-agents.sh` も）で足ります。レビューの依頼前と PR の前に `all.sh` を実行します。`jq`・`git`・`uv`・`claude` CLI が必要です。hook の規則はそれぞれ `# rule:<id>` と `# end:<id>` の間に置きます。`tests/hooks/mutate.sh` が規則を 1 つずつ消し、どのテストも落ちなければ失敗します。

## クレジット

- [obra/superpowers](https://github.com/obra/superpowers) — 設計の対話、タスクごとのサブエージェント実行、テスト先行の考え方の出典。ハーネスは依存しません
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — デルタ仕様とアーカイブによる spec 駆動の変更管理
- implementer のデバッグの規則（先に再現と根本原因、仮説は 1 つずつ、3 回直して駄目なら止める）は、[obra/superpowers](https://github.com/obra/superpowers) の systematic-debugging の考え方を言い換えたものです
- reviewer の過剰設計の観点は [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) の考え方に倣っています
- Anthropic, [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) と [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## ライセンス

[MIT](LICENSE)
