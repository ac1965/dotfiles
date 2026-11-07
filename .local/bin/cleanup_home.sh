#!/usr/bin/env bash
# cleanup_home.sh — ホームディレクトリ整理スクリプト
#
#   A: 再生成できるキャッシュ類 ........ 確認なしで削除
#   B: 内容確認が必要なもの ............ 1件ずつ y/N で確認して削除
#   C: 用途次第のもの(Docker/Ollama等) . 1件ずつ y/N で確認して削除
#   D: 触らないもの .................... 削除対象外(ガードで削除を拒否)
#
# 使い方:
#   ./cleanup_home.sh --dry-run   # 何も消さず、実行内容と容量だけ表示(最初に推奨)
#   ./cleanup_home.sh             # 実行
#   ./cleanup_home.sh --skip-a    # A を飛ばす (--skip-b / --skip-c も同様)
#
# B/C の確認は y か n のみ受け付け、回答は ~/.cleanup_home.answers に保存され、
# 次回実行時の既定値になります(Enter だけで前回の回答を採用)。
# 既定値をリセットするには上記ファイルを削除してください。dry-run では保存しません。

set -u
HOME_DIR="$HOME"
DRY_RUN=0; SKIP_A=0; SKIP_B=0; SKIP_C=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-a)  SKIP_A=1 ;;
    --skip-b)  SKIP_B=1 ;;
    --skip-c)  SKIP_C=1 ;;
    -h|--help) sed -n "2,20p" "$0"; exit 0 ;;
    *) echo "不明なオプション: $arg"; exit 1 ;;
  esac
done

# ------------------------------------------------------------------
# D. 触らないもの(コメント兼ガード)
#   .ssh / .gnupg ........ 秘密鍵・GPG鍵。消すと復元不能
#   .authinfo.gpg ........ 現行の認証情報(.bak のほうは B で確認)
#   Secret ............... 機密データ置き場
#   .gitconfig* .zshrc .zshenv .zprofile .profile .bashrc .vimrc
#   .p10k.zsh Brewfile ... 設定ファイル類
#   Documents Pictures Movies Desktop Maildir org
#   .emacs.d-stable .emacs.d .emacs.d-develop .elisp
#                      ... 書類・メール・ノート・Emacs設定
#   Google Drive / OneDrive* / novel / capture_session
#                      ... クラウド/外部ボリュームへのリンク。消すと同期先に影響
#   Library/Keychains .... キーチェーン
#   .Trash ............... 権限制約あり。Finder で中身を確認してから空にする
# ------------------------------------------------------------------
PROTECTED=(
  ".ssh" ".gnupg" ".authinfo.gpg" "Secret"
  ".gitconfig" ".gitconfig_global" ".gitignore" ".zshrc" ".zshenv" ".zprofile"
  ".profile" ".bashrc" ".vimrc" ".p10k.zsh" "Brewfile" ".Brewfile"
  "Documents" "Pictures" "Movies" "Desktop" "Maildir" "org"
  ".emacs.d" ".emacs.d-stable" ".emacs.d-develop" ".elisp"
  "Google Drive" "novel" "capture_session"
  "Library/Keychains" ".Trash"
)

is_protected() {
  local p="$1" rel x
  rel="${p#"$HOME_DIR"/}"
  case "$rel" in OneDrive*) return 0 ;; esac
  for x in "${PROTECTED[@]}"; do
    # 保護対象そのもの、またはその配下
    if [[ "$rel" == "$x" || "$rel" == "$x"/* ]]; then return 0; fi
  done
  return 1
}

# ------------------------------------------------------------------
# ヘルパー
# ------------------------------------------------------------------
TOTAL_FREED=0

human() { du -sh "$1" 2>/dev/null | cut -f1; }
kb()    { du -sk "$1" 2>/dev/null | cut -f1; }

# 安全削除: ホーム配下のみ、保護対象は拒否
safe_rm() {
  local p="$1"
  [[ -e "$p" || -L "$p" ]] || { echo "  (なし) $p"; return 0; }
  case "$p" in
    "$HOME_DIR"/*) ;;
    *) echo "  [拒否] ホーム外のパス: $p"; return 1 ;;
  esac
  if is_protected "$p"; then
    echo "  [拒否] 保護対象のため削除しません: $p"; return 1
  fi
  local size k
  size=$(human "$p"); k=$(kb "$p"); k=${k:-0}
  if (( DRY_RUN )); then
    echo "  [dry-run] 削除予定: $p ($size)"
  else
    if rm -rf -- "$p"; then
      echo "  削除: $p ($size)"
      TOTAL_FREED=$(( TOTAL_FREED + k ))
    else
      echo "  [失敗] $p"
    fi
  fi
}

# ディレクトリの中身だけ消す(ディレクトリ自体は残す)
safe_rm_contents() {
  local d="$1" f
  [[ -d "$d" ]] || { echo "  (なし) $d"; return 0; }
  for f in "$d"/* "$d"/.[!.]*; do
    [[ -e "$f" || -L "$f" ]] && safe_rm "$f"
  done
}

# B/C の回答(y/n)を保存し、次回実行時の既定値(Enterで採用)にする。
ANSWERS_FILE="$HOME_DIR/.cleanup_home.answers"   # 形式: <キー><TAB><y|n>

get_default() {  # get_default <key> → y または n(未保存は n)
  local v=""
  [[ -f "$ANSWERS_FILE" ]] && v=$(awk -F'\t' -v k="$1" '$1==k{v=$2} END{print v}' "$ANSWERS_FILE")
  [[ "$v" == "y" ]] && echo y || echo n
}

save_answer() {  # save_answer <key> <y|n>
  local tmp
  tmp=$(mktemp) || return
  [[ -f "$ANSWERS_FILE" ]] && awk -F'\t' -v k="$1" '$1!=k' "$ANSWERS_FILE" >"$tmp"
  printf '%s\t%s\n' "$1" "$2" >>"$tmp"
  mv "$tmp" "$ANSWERS_FILE"
}

confirm() {  # confirm <key>: y/n のみ受け付け、Enter で前回の回答を採用
  local key="$1" def ans prompt
  def=$(get_default "$key")
  if [[ "$def" == "y" ]]; then prompt="[Y/n] (前回: y)"; else prompt="[y/N] (前回: n)"; fi
  while true; do
    read -r -p "  → 削除しますか? $prompt " ans </dev/tty
    ans=$(echo "${ans:-$def}" | tr 'A-Z' 'a-z')
    case "$ans" in
      y|n) save_answer "$key" "$ans"; [[ "$ans" == "y" ]]; return ;;
      *)   echo "  y か n で答えてください" ;;
    esac
  done
}

ask_rm() {  # ask_rm <path> <説明>
  local p="$1" note="${2:-}"
  [[ -e "$p" || -L "$p" ]] || { echo "  (なし) $p"; return 0; }
  echo
  echo "■ $p  [$(human "$p")]"
  [[ -n "$note" ]] && echo "  $note"
  if (( DRY_RUN )); then safe_rm "$p"; return; fi
  if confirm "path:$p"; then safe_rm "$p"; else echo "  スキップ"; fi
}

run_cmd() {  # run_cmd <コマンド...>
  if (( DRY_RUN )); then echo "  [dry-run] $*"; else echo "  \$ $*"; "$@"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

before_kb=$(df -k "$HOME_DIR" | awk 'NR==2{print $4}')

# ==================================================================
# A. 再生成できるキャッシュ(確認なし)
# ==================================================================
if (( ! SKIP_A )); then
  echo "=================== A. キャッシュ削除 ==================="

  echo "[Homebrew]"
  if have brew; then run_cmd brew cleanup -s; fi
  safe_rm_contents "$HOME_DIR/Library/Caches/Homebrew"

  echo "[trivy / grype]"
  safe_rm_contents "$HOME_DIR/Library/Caches/trivy"
  safe_rm_contents "$HOME_DIR/.cache/grype"

  echo "[pip]"
  if have pip3; then run_cmd pip3 cache purge; fi
  safe_rm_contents "$HOME_DIR/Library/Caches/pip"
  safe_rm_contents "$HOME_DIR/.cache/pip"

  echo "[uv]"
  if have uv; then run_cmd uv cache clean; fi
  safe_rm_contents "$HOME_DIR/.cache/uv"

  echo "[Chrome / playwright / puppeteer / node-gyp / atlas / lima]"
  safe_rm_contents "$HOME_DIR/Library/Caches/Google"
  safe_rm_contents "$HOME_DIR/Library/Caches/ms-playwright"
  safe_rm_contents "$HOME_DIR/.cache/puppeteer"
  safe_rm_contents "$HOME_DIR/Library/Caches/node-gyp"
  safe_rm_contents "$HOME_DIR/Library/Caches/com.openai.atlas"
  safe_rm_contents "$HOME_DIR/Library/Caches/lima"

  echo "[Xcode ビルド成果物]"
  safe_rm_contents "$HOME_DIR/Library/Developer/Xcode/DerivedData"
  safe_rm_contents "$HOME_DIR/Library/Developer/Xcode/Archives"

  echo "[mypy / dein / emacs キャッシュ]"
  safe_rm "$HOME_DIR/.mypy_cache"
  safe_rm_contents "$HOME_DIR/.cache/dein"
  safe_rm_contents "$HOME_DIR/.cache/emacs"
fi

# ==================================================================
# B. 内容確認が必要なもの(1件ずつ確認)
# ==================================================================
if (( ! SKIP_B )); then
  echo
  echo "=================== B. 確認して削除 ==================="
  ask_rm "$HOME_DIR/Library/Application Support/Claude.bak_20260705_115405" \
         "7月5日のClaudeバックアップ。現行の Claude が正常に動いていれば不要。"
  ask_rm "$HOME_DIR/Diagnostics" \
         "sysdiagnose(7/11)。tar.gz と展開フォルダが重複。"
  ask_rm "$HOME_DIR/Projects/narou_dl/dist"  "PyInstaller成果物。再ビルド可。"
  ask_rm "$HOME_DIR/Projects/narou_dl/build" "PyInstaller中間ファイル。再ビルド可。"

  DL="$HOME_DIR/Downloads"
  ask_rm "$DL/conversations.json"  "199MBの会話エクスポート。索引ファイル作成済みなら不要。"
  ask_rm "$DL/archive.zip"         "内容を確認してから。"
  ask_rm "$DL/チャット索引-Emacs・Lisp-全文.md"  "同内容の .org と重複。"
  ask_rm "$DL/チャット索引-Emacs・Lisp-全文.org" "同内容の .md と重複。どちらか一方を残す。"
  ask_rm "$DL/【防衛省】デジタル統括アドバイザー業務2027_提案書（社名あり）_20261030.pptx" \
         "古い版の可能性。最新版は別ファイル。内容を確認。"

  echo
  echo "--- 使っていないツールの残骸(小容量) ---"
  for f in .aider .aider.chat.history.md .aider.input.history .ropeproject \
           .vimperator .vimperatorrc .vimperatorrc.js .hyper.js \
           .mew.el .mew-theme.el .weechat; do
    ask_rm "$HOME_DIR/$f" "使っていなければ削除可。"
  done
  ask_rm "$HOME_DIR/.authinfo.gpg.bak" \
         "認証情報のバックアップ。現行の .authinfo.gpg と内容が同等か確認してから!"
fi

# ==================================================================
# C. 用途次第(1件ずつ確認)
# ==================================================================
if (( ! SKIP_C )); then
  echo
  echo "=================== C. 用途次第のもの ==================="

  echo
  echo "■ Docker (Library/Containers/com.docker.docker 約51GB)"
  if have docker && docker info >/dev/null 2>&1; then
    docker system df
    echo "  警告: -a --volumes は未使用イメージと未使用ボリューム(DBデータ等)を消します。"
    if (( DRY_RUN )); then
      echo "  [dry-run] docker system prune -a --volumes"
    elif confirm "docker:prune"; then
      docker system prune -a --volumes -f
    else
      echo "  スキップ"
    fi
  else
    echo "  Docker が起動していないためスキップ(Docker Desktop を起動して再実行)。"
  fi

  echo
  echo "■ Ollama モデル"
  if have ollama && ollama list >/dev/null 2>&1; then
    # qwen2.5vl:7b と :latest は同一実体のため、
    # 片方だけ消してもディスクは減らない(両方消すと減る)。
    ollama list | tail -n +2 | while IFS= read -r line; do
      name=$(echo "$line" | awk '{print $1}')
      size=$(echo "$line" | awk '{print $3, $4}')
      echo
      echo "  モデル: $name ($size)"
      if (( DRY_RUN )); then
        echo "  [dry-run] ollama rm $name"
      else
        if confirm "ollama:$name"; then ollama rm "$name"; else echo "  スキップ"; fi
      fi
    done
  else
    echo "  ollama が使えない(未起動)ためスキップ。"
  fi

  ask_rm "$HOME_DIR/.venv_tf213" "TensorFlow 2.13用の古い仮想環境。使っていなければ削除。"
  ask_rm "$HOME_DIR/.venv310"    "Python3.10用の仮想環境。使っていなければ削除。"
  ask_rm "$HOME_DIR/.pyenv/versions/lora-oss20b-312" "LoRA用の仮想環境。使っていなければ削除。"
  ask_rm "$HOME_DIR/.lima/x64-lab" \
         "Lima VM。起動中なら先に 'limactl stop x64-lab'。VM内データも消える。"
  ask_rm "$HOME_DIR/nuclei-templates" "nuclei を使わなければ削除可(再取得可)。"
  ask_rm "$HOME_DIR/AozoraEpub3"      "使わなければ削除可。"
  ask_rm "$HOME_DIR/node_modules"     "ホーム直下の node_modules。通常は不要(誤って作られたもの)。"
fi

# ==================================================================
# 結果
# ==================================================================
echo
echo "=================== 完了 ==================="
if (( DRY_RUN )); then
  echo "dry-run のため何も削除していません。"
else
  after_kb=$(df -k "$HOME_DIR" | awk 'NR==2{print $4}')
  echo "safe_rm で消した合計: 約 $(( TOTAL_FREED / 1024 )) MB"
  echo "空き容量の増加(df 差分): 約 $(( (after_kb - before_kb) / 1024 )) MB"
  echo "※ Docker/Ollama/brew 等のコマンド経由の削減分は df 差分に反映されます。"
fi
echo "※ .Trash は権限の制約があるため触っていません。Finder から確認して空にしてください。"
