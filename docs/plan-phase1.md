# mrdebug フェーズ1: mruby/mruby 上で動くコアの再構築

## Context

現行 `picoruby-debug` は PicoRuby 前提の一体設計で、`Debugger` クラスが UI ループ
（`Editor::Line` プロンプト）まで内包し、`picoruby-sandbox` / `picoruby-editor` /
`picoruby-io-console` / `picoruby-json` に依存している。そのため mruby 単体では導入できない。
またデバッガの状態管理・BP マッチング・モード管理まで C（`src/mruby/debugger.c` 448行）に
置かれており、変更コストが高い。

[設計メモ](https://gist.github.com/yuuu/8f187aa1035104aac297958c2be783c7) の方針に沿って、
**依存極小のコア `mrdebug` ＋ 差し替え可能なフロントエンド** に作り直す。

**このフェーズのゴール**: `/Users/yuuu/ghq/github.com/mruby/mruby`（mruby 4.0.0）のビルドに
gem を1行追加するだけで、`bin/mruby script.rb` の `binding.debugger` が対話デバッグできる。
対応コマンドは `continue` / `step` / `next` / `break` / `delete` / `print` の6つに絞る。

**実装方針の制約**: C は VM フック部分のみ。それ以外は全て Ruby で書く。
C は `src/hook.c` 1ファイルに閉じ込め、Ruby に対して6メソッドだけ公開する。

**スコープ外（後続フェーズ）**: PicoRuby / R2P2 での動作（今回は一切考慮しない）、
`quit` / `list` / `bt` / `frame` / `up` / `down` / `watch` / `display` / `finish` などの追加コマンド、
ワイヤプロトコル / トランスポート抽象 / RemoteUI / ホスト CLI バイナリ / ホスト側 DAP ブリッジ /
`mrdebug-console`（オンデバイス UI gem）。

## 調査で確定した前提（mruby 4.0.0 / master `4e2bc5c2b`）

- `spec.build.defines << "MRB_USE_DEBUG_HOOK"` は `mrbgems/mruby-bin-debugger/mrbgem.rake:5`
  が実際に使っている手法。`setup` が `instance_eval(&@initializer)` の前に既定値を入れる
  （`lib/mruby/gem.rb:54-108`）ので `spec.rbfiles +=` も安全。
- `mruby-binding` / `mruby-eval` は `metaprog.gembox`、`mruby-io` は `stdlib-io.gembox` にあり、
  いずれも `default.gembox` 経由で既定ビルドに入る。`mrb_binding_new` は
  `mrbgems/mruby-binding/src/binding.c:446` に外部リンケージがあり、現行同様に前方宣言で使える。
- irep の debug info は `filename` があれば常に生成される
  （`mrbgems/mruby-compiler/src/codegen.c:608-613`）。`bin/mruby foo.rb` は追加フラグ不要。
- **`mrb->c->prev` は root context では NULL。** 現行の「`prev` に退避してから funcall」が成立
  しない。`src/vm.c:2422` の `#define regs (ci->stack)` は安全だが、`mrb_vm_exec` のローカル
  `mrb_callinfo *ci` は `cibase` 配列への生ポインタで、同一コンテキスト上の funcall が
  `cibase` を realloc すると dangling する。→ 専用コンテキストが必要（下記 1）。
- gem 内部ヘッダは `include/` に置かない（`include/` は gem 間共有用）。C が1ファイルなら
  `src/hook.c` だけで済み、`src/*.c` の非再帰 glob にそのまま乗る。

## 設計の要点

### 1. 専用デバッガコンテキスト（C・最重要リスク）

`src/hook.c` が遅延生成する `struct mrb_context` を1本持ち、Ruby へのコールバック前後で
`mrb->c` をそれに差し替える。`mrbgems/mruby-fiber/src/fiber.c` の `init_fiber`
（stbase/stend, cibase/ciend, `ci = cibase`, `cibase[0]` ゼロ化, `ci->stack = stbase`,
`svars = NULL`, `fib = NULL`, `vmexec = FALSE`）を手本にする。

- コールバック中は `dbg_ctx->prev = task_c` / `mrb->c = dbg_ctx`（GC は `mrb->c` から prev 鎖を
  辿るので両方マークされる）。停止中の `ci` 走査用に `paused_ctx = task_c` を保持。
- 復帰時に `mrb->c = task_c`、`dbg_ctx->ci = dbg_ctx->cibase`、`stbase[0] = nil` まで戻して
  スタックを空にする（非アクティブ時は GC 到達不能なので残留参照を作らない）。
- これで root context でも Task 上でも同一コードパスになる。現行実装は `prev` がある前提なので、
  これは plain mruby 対応に必須の変更。

### 2. C から Ruby への公開面は6メソッドだけ

```
MRDebug::Hook.install(session)      # code_fetch_hook を張り、コールバック先 session を記憶
MRDebug::Hook.uninstall
MRDebug::Hook.armed = bool          # false なら hook は即 return（唯一の C 側ゲート）
MRDebug::Hook.frame_count           # 停止中コンテキストの Ruby フレーム数（next の深度判定用）
MRDebug::Hook.frame_position(depth) # -> [file, line] / nil（C フレーム等）
MRDebug::Hook.frame_binding(depth)  # -> Binding / nil（print の評価用）
```

`code_fetch_hook` の中身（C にしか書けないものだけ）:

1. `armed` が false なら即 return。
2. `mrb_debug_get_filename` / `mrb_debug_get_line` で file/line を取得。`line < 0` は return。
3. `(irep, line)` が前回と同じなら return（1行 = 複数命令の重複排除）。
4. `mrb->code_fetch_hook = NULL` にして再入を防ぎ、専用コンテキストへ swap。
5. `mrb_protect_error` 経由で `session.on_line(file, line)` を funcall
   （`on_line` から例外が漏れると hook 停止 + `mrb->c` 差し替え状態のまま伝播するため）。
6. コンテキストを戻し、hook を張り直して return。

`file` 文字列は irep ごとに `const char*` の同一性でキャッシュして GC 負荷を抑える
（デバッガ意味論を含まない、純粋な最適化）。

### 3. C から Ruby へ移すもの

| 現行の C 実装 | 新実装 |
|---|---|
| `LineBreakpoint`（CDATA + 先頭メンバ埋め込み idiom） | 素の Ruby クラス。suffix マッチは `file.end_with?` |
| `picoruby_debugger` 構造体（breakpoints / mode / next_ci） | `MRDebug::Session` の ivar |
| `mrb_debugger_should_break_p` などのホットパスクエリ群 | `Session#on_line` 内の Ruby 判定 |
| `next` の `next_ci` ポインタ比較 | `Hook.frame_count` による深度比較（記録深度以下で停止） |
| `mrb_binding_debugger`（`binding.debugger` 入口） | Ruby。`Binding#debugger` → `MRDebug.brk(self)` が `Hook.frame_position` で呼び出し位置を取り、その場で停止ループを回す（hook を経由しない） |

`Binding#debugger` から `MRDebug.brk` までは固定の呼び出し鎖なので、ユーザーフレームまでの
オフセットは名前付き定数にし、E2E テストで固定する。

### 4. Session / UI の分離と「コアは I/O を持たない」

- `MRDebug::Session` がデバッガ状態を所有（breakpoints / mode / 現在の停止位置と binding）。
- **コマンド層は文字列を返し、印字しない。** `MRDebug::Command` が
  `line -> [出力行の配列, :stay | :resume]` を返し、UI が `puts` する。
  現行の `Debugger#dispatch_command` が直接 `puts` していた設計をやめる。これで層1のユニット
  テストが stdio なしで書ける（C を減らした分、テストできる範囲が大きく広がる）。
- UI 契約は `MRDebug::UI::Base`（`on_stop(session, notices)` / `on_output(str)`）。
  フェーズ1の実装は `MRDebug::UI::LocalConsole` のみ。
- `LocalConsole` は `STDIN.gets` の行単位入力（raw モード・端末エコー処理なし）。
  `picoruby-editor` を使わないので、**現行の既知ギャップ（パイプ入力で複数コマンドを取りこぼす）は
  この時点で解消する**。行編集・履歴が要る環境は後続フェーズの `mrdebug-console` の担当。

### 5. 引き継ぐ規約

suffix ベースのファイルマッチと、安定番号付け（`delete` は in-place deactivate、既存番号がずれない）
は現行から踏襲する。

## ファイル構成

削除: `include/`, `src/*.c`（シム）, `src/mruby/`, `src/mrubyc/`, `mrblib/*.rb`（全置換）,
`editors/vscode/`（設計メモ 1.3 の決定により独自 Extension は廃止。VS Code 連携はホスト側
DAP ブリッジができるまで使えなくなる）。

新規:

```
mrbgem.rake                        # gem 'mrdebug'
src/hook.c                         # ★C はこの1ファイルのみ
mrblib/mrdebug.rb                  # module MRDebug, .session, .brk, .attach(ui) / Binding#debugger
mrblib/mrdebug/session.rb          # 状態所有 + on_line（停止判定・停止ループ）
mrblib/mrdebug/line_breakpoint.rb  # file/line + suffix マッチ + active フラグ
mrblib/mrdebug/command.rb          # コマンドテーブル + パース + dispatch（文字列を返す）
mrblib/mrdebug/ui.rb               # UI::Base 契約
tools/mrdebug/ui/local_console.rb  # build.host? 限定
test/*.rb                          # 層1: mruby assert（このディレクトリは assert 専用）
e2e/build_config.rb                # 検証用 MRUBY_CONFIG（ビルド名 'mrdebug-host'）
e2e/scenarios/*.rb, e2e/expected/*.txt, e2e/run.rb   # 層2: トランスクリプト E2E
Rakefile                           # rake build / test:unit / test:e2e
```

`mrbgem.rake`:

```ruby
MRuby::Gem::Specification.new('mrdebug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger core for mruby'

  spec.build.defines << 'MRB_USE_DEBUG_HOOK'

  spec.add_dependency 'mruby-binding', core: 'mruby-binding'
  spec.add_dependency 'mruby-eval',    core: 'mruby-eval'

  if spec.build.host?
    spec.add_dependency 'mruby-io', core: 'mruby-io'
    spec.rbfiles += Dir.glob("#{spec.dir}/tools/mrdebug/**/*.rb").sort
  end
end
```

## コマンド（フェーズ1はこの6つのみ）

| コマンド | 別名 | 動作 |
|---|---|---|
| `continue` | `c`, 空入力 | 次の breakpoint まで再開 |
| `step` | `s` | 次の行で停止（呼び出しに入る） |
| `next` | `n` | 同じかそれより浅いフレームの次の行で停止 |
| `break <file>:<line>` | `b` | breakpoint 追加。引数が行番号のみなら現在のファイル。引数なしで一覧 |
| `delete [<番号>]` | `d` | 指定番号の breakpoint を削除。番号なしで全削除 |
| `print <式>` | `p` | 停止フレームの binding で評価して表示 |

未知のコマンドは `unknown command: ...` を返す。`quit` は無いので、終了は
`continue` でスクリプトを走り切らせる（`quit` は後続フェーズ）。

## 性能上のトレードオフ（意図的に受け入れる）

BP マッチングを Ruby に移した結果、**RUN モードで BP が1件以上あると、実行される Ruby の
ソース行ごとに Ruby への funcall が1回発生する**（現行は「BP のあるファイルの irep 以外は
C 側でスキップ」する fast path を持っていた）。C 側に残すゲートは `armed` 1個だけなので、
BP が0件のときは現行と同じくほぼゼロコスト。

フェーズ1はホスト前提なのでこれを受け入れ、Verification 6 で実測値を README に残す。
対策（Ruby から C へ「関心のあるファイル/行」を素の配列で降ろす、opcode パッチ）は
設計メモ 1.4B / 7.7 の後続課題として据え置く。

## ドキュメント

- `README.md` 全面書き換え: mruby 単体での導入手順、上記コマンド表、`MRB_USE_DEBUG_HOOK` が
  ビルド全体の `mrb_state` レイアウトを変える点（設計メモ 7.6、回避不可）、上記の性能特性。
- `CLAUDE.md` 全面書き換え（現行は旧 C アーキテクチャの詳細記述なので実態と乖離する）。
- gem 名は `mrdebug`。リポジトリ名（`yuuu/picoruby-debug`）のリネームは別途ご対応が必要なので、
  README のインストール例はローカル `conf.gem` パス指定を基本に書き、`github:` 行はリネーム後の
  名前として注記する。

作業は `main` から切ったブランチ（`rewrite/mrdebug-core`）で行う。

## 作業ステップ（10分割・各ステップ終了時に確認いただく）

この作業計画はリポジトリの `docs/plan-phase1.md` にも出力し、以降の作業の基準にする。

1. **土台づくり** — `rewrite/mrdebug-core` ブランチを切り、`docs/plan-phase1.md` を出力。
   旧実装（`include/`, `src/`, `mrblib/`, `editors/vscode/`）を削除し、`mrbgem.rake` を
   `mrdebug` に差し替え。`e2e/build_config.rb` と `Rakefile` を用意して、
   **中身が空の gem が mruby にリンクされてビルドが通る**ところまで（`rake build`）。
2. **hook の骨格（C）** — `src/hook.c` に `MRDebug::Hook` を定義。`install` / `uninstall` /
   `armed=`、専用コンテキストの生成と swap、`session.on_line(file, line)` の funcall
   （`mrb_protect_error` 付き）。Ruby 側は「呼ばれた行を print するだけ」のスタブにして、
   **フックが1行ごとに発火する**ことをスモーク確認。
3. **フレーム API（C）** — `Hook.frame_count` / `frame_position(depth)` / `frame_binding(depth)`
   を追加し、スタブから正しい値が取れることを確認。**ここで C は完成**（以降 C は触らない）。
4. **入口** — `mrblib/mrdebug.rb`（`module MRDebug`, `.session`, `.brk`, `Binding#debugger`）。
   `binding.debugger` を置いたスクリプトで、**最初の停止位置（file:line）が正しく出る**ところまで。
5. **Session と LineBreakpoint** — 状態所有、モード（run / step / next）、`on_line` の停止判定、
   suffix マッチ、安定番号付け。
6. **コマンド層** — `MRDebug::Command`。6コマンドのテーブル・パース・戻り文字列。I/O を持たない。
7. **UI と結線** — `MRDebug::UI::Base` と `tools/mrdebug/ui/local_console.rb`。
   `Session` に結線して、**6コマンドで対話デバッグが一通り動く**ことを手動スモーク確認。
8. **層1ユニットテスト** — `test/*.rb`（Verification 3 の項目）。`rake test:unit` が緑。
9. **層2 E2E** — `e2e/run.rb` ハーネスとシナリオ（Verification 4 の項目）。`rake test:e2e` が緑。
10. **仕上げ** — 専用コンテキストのストレス確認とオーバーヘッド実測（Verification 5・6）、
    `README.md` / `CLAUDE.md` の全面書き換え。

## Verification

`MRDEBUG_MRUBY_DIR=/Users/yuuu/ghq/github.com/mruby/mruby` を前提に `Rakefile` 経由で実行する。
`e2e/build_config.rb` はビルド名を `mrdebug-host` にして既存の `build/host` を壊さない。

1. **ビルド** — `rake build`
   （= `MRUBY_CONFIG=$PWD/e2e/build_config.rb rake -f $MRDEBUG_MRUBY_DIR/Rakefile`）
2. **手動スモーク** —
   `printf 'b 8\nc\np a\nn\ns\nc\n' | .../build/mrdebug-host/bin/mruby e2e/scenarios/basic.rb`
   が期待どおり進むこと。特に**複数コマンドを一度にパイプしても取りこぼさない**こと
   （現行の既知ギャップの解消確認）。
3. **層1ユニットテスト** — `rake test:unit`（mruby の `rake test`）。C を削った分ここが主力になる:
   コマンドパーサ/テーブル、`LineBreakpoint#break?` の suffix マッチ、`Session` の停止判定
   （run / step / next の深度比較を `frame_count` をスタブして検証）、`delete` 後も既存番号が
   ずれないこと、`Command` の戻り文字列。
4. **層2 E2E** — `rake test:e2e`。`e2e/scenarios/*.rb` にコマンド列と期待トランスクリプトを置き、
   `e2e/run.rb` が差分判定。シナリオ: `binding.debugger` での初回停止位置が正しいこと
   （フレームオフセット固定）、BP ヒット、`step` / `next` の深度差、`print` の評価と評価失敗時の
   メッセージ、`delete` 後に停止しないこと、スクリプトが最後まで走り切ること。
5. **専用コンテキストのストレス確認**（最重要リスク）— 深い再帰の中で停止し、`print` で重い式
   （`Binding#eval` がコンパイラを回す）を繰り返し評価しても壊れないこと。`Binding#eval` が
   停止中コンテキストのスタック上の env を参照する点も同時に確認する。`MRB_GC_STRESS` を
   足したビルドでも同じシナリオを通す。
6. **フックのオーバーヘッド実測** — gem 未導入 / BP 0件 / BP 1件設定の3点でベンチを取り、
   README に数値を残す。

## 後続フェーズに送る項目（今回の調査で分かったことを含む）

- **`quit` の実装方式**: `mrb->c->status = MRB_TASK_STOPPED` は効かない
  （`RETURN_IF_TASK_STOPPED` は `MRB_USE_TASK_SCHEDULER` = `mruby-task` gem でしか有効化されず
  既定ビルドに入らない。`src/vm.c:2335-2349`）。代わりに `MRB_EXC_EXIT` フラグ付き例外を
  `mrb_exc_raise` すれば、`bin/mruby` が `MRB_EXC_CHECK_EXIT` で拾ってエラー表示なしに
  `exit(status)` する（`include/mruby/error.h:27-31`,
  `mrbgems/mruby-bin-mruby/tools/mruby/mruby.c:369,404`）。`mruby-exit` 依存は不要。
- 追加コマンド: `quit` / `list` / `bt` / `frame` / `up` / `down` / `finish` / `watch` / `display` /
  条件付き BP / メソッド BP / `catch` / `info` / `step N` / `next N`。
- PicoRuby / R2P2 での動作（`mrbgem.rake` の依存宣言分岐を含む）。
- オンデバイス UI gem `mrdebug-console`（`picoruby-editor` / `io-console` 依存）。
- ワイヤプロトコル / トランスポート抽象（mruby 4.0 の `ports/` 機構がシリアル HAL に使える）。
- ホスト CLI バイナリ（`spec.bins`）とホスト側 DAP ブリッジ、`vscode-rdbg` 互換。
- ホットパスの C 側 fast path 復活（上記「性能上のトレードオフ」参照）。
