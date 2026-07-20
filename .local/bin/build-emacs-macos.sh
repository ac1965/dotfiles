#!/usr/bin/env bash
#
# build-emacs-macos.sh
#
# Deterministic GNU Emacs build for macOS
# - Apple Silicon / Intel 対応
# - Cocoa (Nextstep) 安定ビルド
# - Clang toolchain 使用
# - Homebrew libgccjit による native-comp
# - fingerprint 安定
# - forward-safe (Emacs 30/31)
# - out-of-tree ビルド (ソースツリーは常に git clean な状態を保つ)
# - CLI ラッパー生成 (self-contained NS ビルドの $prefix/bin/emacs 問題への対処)
#

set -Eeuo pipefail

# ============================================================
# Options
# ============================================================

NATIVE_COMP="--with-native-compilation=aot"
DEBUG=false

# デフォルト値（従来の挙動と同じ）
BUILD_DIR="$HOME/.local"
REPO_DIR="$HOME/Projects/github.com/emacs-mirror/emacs"
# OBJ_DIR は未指定なら REPO_DIR 正規化後に "${REPO_DIR}-build" を既定値にする。
# (usage 表示の都合上ここでは空のままにしておく)
OBJ_DIR=""

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -b, --build-dir DIR         インストール先 (--prefix) を指定 (default: $HOME/.local)
  -r, --repository-dir DIR    git clone 先ディレクトリを指定 (default: $HOME/Projects/github.com/emacs-mirror/emacs)
  -o, --obj-dir DIR           configure/make の実行先(out-of-tree ビルドディレクトリ)を指定
                               (default: "<repository-dir>-build")
                               このディレクトリは毎回 rm -rf されるため、
                               他の用途と共有しないこと。
      --no-native, --no-native-compilation
                               native-comp を無効化
      --debug                  デバッグ出力 (set -x) を有効化
  -h, --help                   このヘルプを表示

Note:
  ソースツリー ($REPO_DIR 相当) は git clone / git pull --rebase /
  autogen.sh (configure スクリプト生成) 以外では一切変更しない。
  configure・make・make install はすべて --obj-dir で指定した
  別ディレクトリ内で実行されるため、ソースツリーは常に
  "git status" がクリーンな状態を保つ。

  インストール後、\$BUILD_DIR/bin/emacs は /Applications/Emacs.app 内の
  バイナリを呼ぶシェルラッパーに差し替えられる (理由は該当セクションを参照)。
EOF
}

# 値を取る長短オプションの両対応 ( --opt VALUE / --opt=VALUE / -o VALUE )
while [[ $# -gt 0 ]]; do
	case "$1" in
	-b | --build-dir)
		[[ $# -ge 2 ]] || {
			echo "❌ $1 requires an argument" >&2
			exit 1
		}
		BUILD_DIR="$2"
		shift 2
		;;
	--build-dir=*)
		BUILD_DIR="${1#*=}"
		shift
		;;
	-r | --repository-dir)
		[[ $# -ge 2 ]] || {
			echo "❌ $1 requires an argument" >&2
			exit 1
		}
		REPO_DIR="$2"
		shift 2
		;;
	--repository-dir=*)
		REPO_DIR="${1#*=}"
		shift
		;;
	-o | --obj-dir)
		[[ $# -ge 2 ]] || {
			echo "❌ $1 requires an argument" >&2
			exit 1
		}
		OBJ_DIR="$2"
		shift 2
		;;
	--obj-dir=*)
		OBJ_DIR="${1#*=}"
		shift
		;;
	--debug)
		DEBUG=true
		shift
		;;
	--no-native | --no-native-compilation)
		NATIVE_COMP="--without-native-compilation"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	esac
done

# 相対パス・"~" を含む可能性があるので絶対パスに正規化
BUILD_DIR="$(mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR" && pwd)"

# REPO_DIR も同様に絶対パス化する。
# ただし REPO_DIR 自体はまだ存在しない場合がある(初回 git clone 前)ため、
# 親ディレクトリを絶対パス化してからファイル名部分を連結する。
# これを怠ると、相対パスで -r/--repository-dir を渡した際に
# 後段の `cd "$SRC_DIR"` でカレントディレクトリが変わった後も
# $REPO_DIR が相対パスのままになり、パス組み立てが
# 意図しない場所を指してしまう(過去に実際に踏んだ不具合)。
mkdir -p "$(dirname "$REPO_DIR")"
REPO_PARENT="$(cd "$(dirname "$REPO_DIR")" && pwd)"
REPO_DIR="$REPO_PARENT/$(basename "$REPO_DIR")"

# OBJ_DIR 未指定なら、REPO_DIR の兄弟ディレクトリ "<repo>-build" を既定値にする。
# ソースツリーの外に置くことで、ソース側を "git clean" に保ったまま
# ビルド生成物(Makefile, .o, .elc, .texi, info/, ダンプファイル等)を
# 完全に分離する(out-of-tree build)。
[[ -n "$OBJ_DIR" ]] || OBJ_DIR="${REPO_DIR}-build"
mkdir -p "$(dirname "$OBJ_DIR")"
OBJ_PARENT="$(cd "$(dirname "$OBJ_DIR")" && pwd)"
OBJ_DIR="$OBJ_PARENT/$(basename "$OBJ_DIR")"

# ビルドログは OBJ_DIR とは独立した永続ディレクトリに保存する。
# OBJ_DIR は毎回 rm -rf して作り直すため、OBJ_DIR 配下に置くと
# 失敗時のログが次回実行時に失われてしまうことを避けるため。
LOG_DIR="$HOME/.cache/build-emacs-macos"
mkdir -p "$LOG_DIR"

# インストール先の .app バンドル。
# CLI ラッパー生成でも参照するため、ここで一度だけ定義する。
APP_DST="/Applications/Emacs.app"

$DEBUG && set -x

# ============================================================
# Helpers
# ============================================================

heading() {
	printf "\n\033[38;5;39m==> %s\033[0m\n\n" "$*"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "❌ required command not found: $1" >&2
		exit 1
	}
}

# ============================================================
# Platform Detection
# ============================================================

[[ "$(uname -s)" == "Darwin" ]] || {
	echo "❌ macOS only"
	exit 1
}

ARCH="$(uname -m)"

case "$ARCH" in
arm64) BREW_PREFIX="/opt/homebrew" ;;
x86_64) BREW_PREFIX="/usr/local" ;;
*)
	echo "❌ Unsupported arch: $ARCH"
	exit 1
	;;
esac

echo "Architecture: $ARCH"
echo "Homebrew prefix: $BREW_PREFIX"
echo "Build dir (--prefix): $BUILD_DIR"
echo "Repository dir (source, always kept clean): $REPO_DIR"
echo "Obj dir (configure/make, rebuilt every run): $OBJ_DIR"
echo "Log dir (persistent): $LOG_DIR"
echo "App bundle: $APP_DST"

# ============================================================
# Requirements
# ============================================================

require_cmd brew
require_cmd git
require_cmd pkg-config
require_cmd xcrun
require_cmd clang

BREW_FORMULAS=(
	autoconf texinfo pkg-config
	libgccjit gnutls jansson libxml2
	tree-sitter gmp
)

heading "Installing required Homebrew packages"

for f in "${BREW_FORMULAS[@]}"; do
	brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"
done

# ============================================================
# Apple Clang Toolchain (Stable Cocoa build)
# ============================================================

heading "Configuring Apple Clang toolchain"

# SC2155: `export VAR="$(cmd)"` は set -e 下でも cmd の失敗を握りつぶす
# (export 自体が成功するため)。宣言と代入を分け、xcrun の失敗を検知する。
CC="$(xcrun --find clang)"
CXX="$(xcrun --find clang++)"
AR="$(xcrun --find ar)"
RANLIB="$(xcrun --find ranlib)"
NM="$(xcrun --find nm)"
LD="$CC"
export CC CXX AR RANLIB NM LD

echo "Using Clang: $CC"

# ============================================================
# SDK and Flags
# ============================================================

heading "Configuring SDK and compiler flags"

SDKROOT="$(xcrun --show-sdk-path)"
export SDKROOT

if [[ "$ARCH" == "arm64" ]]; then
	export CFLAGS="-O3 -arch arm64 -isysroot $SDKROOT"
else
	export CFLAGS="-O3 -arch x86_64 -isysroot $SDKROOT"
fi

export CPPFLAGS="-isysroot $SDKROOT -I$BREW_PREFIX/include"
export LDFLAGS="-isysroot $SDKROOT -L$BREW_PREFIX/lib -framework AppKit"
export PKG_CONFIG_PATH="$BREW_PREFIX/lib/pkgconfig"

# ============================================================
# libgccjit for native-comp
# ============================================================

heading "Configuring libgccjit"

LIBGCCJIT_PREFIX="$(brew --prefix libgccjit)"
export CPPFLAGS="-I$LIBGCCJIT_PREFIX/include $CPPFLAGS"
export LDFLAGS="-L$LIBGCCJIT_PREFIX/lib $LDFLAGS"

# ============================================================
# Source (ソースツリーは常にクリーンに保つ: clone/pull と
# autogen.sh による configure スクリプト生成のみ行う)
# ============================================================

heading "Preparing source"

SRC_REPO="https://github.com/emacs-mirror/emacs.git"
SRC_DIR="$REPO_DIR"

if [[ -d "$SRC_DIR/.git" ]]; then
	cd "$SRC_DIR"
	git pull --rebase
else
	git clone "$SRC_REPO" "$SRC_DIR"
	cd "$SRC_DIR"
fi

# ============================================================
# Autogen (./configure スクリプトの生成には必須。
# 生成物は通常 .gitignore 対象の autotools 生成ファイルのみで、
# ビルド成果物(.o/.elc/.texi等)はここでは一切生成されない)
# ============================================================

heading "Running autogen"

./autogen.sh

# ============================================================
# Clean (out-of-tree ビルドディレクトリを作り直すだけで良い。
# ソースツリー側の distclean/git clean は不要になった)
# ============================================================

heading "Cleaning previous build (obj dir)"

rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"

# ============================================================
# Configure (obj dir 側で実行し、ソースツリーの configure を参照する)
# ============================================================

heading "Configuring Emacs (out-of-tree)"

cd "$OBJ_DIR"

# --with-ns は既定で self-contained (ns-self-contained) となり、
# lisp/etc/libexec は Emacs.app バンドル内に配置される。
# その代償として $prefix/bin/emacs は「バンドル内から起動される」
# 前提の相対パス解決を行うため単体では動かない。
# ここでは自己完結性を優先し、CLI 側は後段でラッパーを生成して解決する
# (--disable-ns-self-contained を選ぶと逆に .app が $prefix に依存し、
#  $prefix を消すと GUI まで壊れるため、こちらは採用しない)。
# --without-imagemagick: image-dired のサムネイル生成程度にしか使っておらず、
# 画像表示自体は Emacs 組み込みの create-image (libpng/librsvg 等) で足りる。
# --with-imagemagick は Emacs バイナリに ABI バージョン付きの dylib パス
# (libMagickWand-7.Q16HDRI.<N>.dylib) を直接埋め込むため、`brew upgrade` で
# imagemagick の ABI バージョンが上がり旧 Cellar が削除されると、
# 再ビルドするまで dyld レベルで起動不能になる(2026-07 に実際に発生)。
# ImageMagick を使う個別コマンド(convert 等)はこのビルドオプションと無関係に
# 引き続き PATH 経由で呼び出せるため、Emacs 側で --with-imagemagick を
# 要求する必要はない。
"$SRC_DIR/configure" \
	CC="$CC" \
	CXX="$CXX" \
	AR="$AR" \
	RANLIB="$RANLIB" \
	NM="$NM" \
	--with-ns \
	"$NATIVE_COMP" \
	--with-tree-sitter \
	--with-json \
	--with-gnutls \
	--without-imagemagick \
	--with-modules \
	--prefix="$BUILD_DIR"

# ============================================================
# Build
# ============================================================

heading "Building Emacs"

# hw.logicalcpu だとApple Siliconの効率/性能コア混在や
# ハイパースレッディング相当の過剰な並列度により、
# gnulib/lisp生成物の依存順序でごく稀にレース由来の
# ビルド失敗(Error 2)を誘発することがあるため物理コア数を使う。
CORES="$(sysctl -n hw.physicalcpu)"

# 失敗時にエラー内容を追跡できるよう、必ずログをファイルに残す。
# OBJ_DIR は次回実行時に rm -rf されるため、ログは独立した
# 永続ディレクトリ(LOG_DIR)に保存する。
# tee を pipefail 下で使うため、make の終了コードは
# PIPESTATUS[0] で明示的に拾い、失敗時はログの場所を案内して即終了する。
LOGFILE="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
echo "Build log: $LOGFILE"

# doc/misc の .org -> .texi -> .info 変換 (org-texinfo-export-to-texinfo-batch)
# は $(abs_top_builddir)/src/emacs (ビルド済みバイナリ) を要求する。
# 一方、トップレベルの "info/dir" 集約ルールは doc/misc/*.texi を
# 「既に存在するファイル」として前提条件チェックするだけで、
# 自身では生成方法を知らない。
# -j 並列ビルドで src のコンパイルと doc/misc の処理タイミングが
# 保証されないため、src/emacs が未完成のまま doc/misc 側の処理が
# 走るとレースで "No rule to make target ...texi" が発生しうる
# (2026-07-11 実機で再現・確認済み)。
# lib -> lib-src -> src -> doc/misc の順に直列で完成させ、
# modus-themes.texi 等の生成物を先に確定させてから
# 残りを並列ビルドすることでレースを回避する。
heading "Building lib / lib-src / src / doc-misc serially (race avoidance)"

{
	make -C lib
	make -C lib-src
	make -C src
	make -C doc/misc info
} 2>&1 | tee "$LOGFILE"
PRELIM_STATUS="${PIPESTATUS[0]}"

if [[ "$PRELIM_STATUS" -ne 0 ]]; then
	echo "❌ preliminary serial build failed (exit $PRELIM_STATUS). See log: $LOGFILE" >&2
	exit "$PRELIM_STATUS"
fi

heading "Building the rest in parallel"

make -j"$CORES" 2>&1 | tee -a "$LOGFILE"
BUILD_STATUS="${PIPESTATUS[0]}"

if [[ "$BUILD_STATUS" -ne 0 ]]; then
	echo "❌ make failed (exit $BUILD_STATUS). See log: $LOGFILE" >&2
	exit "$BUILD_STATUS"
fi

# ============================================================
# Install
# ============================================================

heading "Installing"

# nextstep/Emacs.app への Resources/lisp・MacOS/libexec の配置は
# 「make install」内(install-arch-dep / install-arch-indep)で行われる。
# 「make」(all)だけではバイナリとplist骨格しか作られないため、
# この install ステップは省略できない。
make install 2>&1 | tee -a "$LOGFILE"
INSTALL_STATUS="${PIPESTATUS[0]}"

if [[ "$INSTALL_STATUS" -ne 0 ]]; then
	echo "❌ make install failed (exit $INSTALL_STATUS). See log: $LOGFILE" >&2
	exit "$INSTALL_STATUS"
fi

# 注意: "make install" は既に $BUILD_DIR/bin に
# emacs / emacsclient (バージョン付き実体 + シンボリックリンク) を
# インストール済みだが、self-contained NS ビルドの emacs は
# バンドル外では動作しない(後段の CLI wrapper セクションを参照)。
# emacsclient はバンドル相対パスに依存しないため、そのまま利用できる。

heading "Installing Emacs.app to $APP_DST"

rm -rf "$APP_DST"
# ditto の -L (シンボリックリンク実体化)相当オプションは
# macOSのバージョンによって存在しないことがあるため、
# 同じ目的で標準的に使える `cp -R -L` を使う。
# -L: nextstep/Emacs.app 内にシンボリックリンクが含まれていても
# 実体としてコピーし、リンク切れを防ぐ。
cp -R -L "$OBJ_DIR/nextstep/Emacs.app" "$APP_DST"

# native-comp(--with-native-compilation=aot)有効時、実行ファイルは
# 実行時に Contents/MacOS/../native-lisp (= Contents/native-lisp) を
# 相対パスで探すが、.eln の実体は Contents/Frameworks/native-lisp に
# 配置される。本来は Contents/native-lisp -> Frameworks/native-lisp の
# シンボリックリンクで橋渡しされる想定だが、out-of-tree ビルドの
# nextstep/Emacs.app にはこのリンクが作られないことを実機で確認済み
# (2026-07-11)。無いと `dlopen` が .eln を見つけられず起動時に失敗するため、
# 欠けている場合のみここで明示的に作成する。
if [[ "$NATIVE_COMP" == "--with-native-compilation=aot" ]] \
	&& [[ -d "$APP_DST/Contents/Frameworks/native-lisp" ]] \
	&& [[ ! -e "$APP_DST/Contents/native-lisp" ]]; then
	heading "Linking Contents/native-lisp -> Contents/Frameworks/native-lisp"
	ln -s Frameworks/native-lisp "$APP_DST/Contents/native-lisp"
fi

# ============================================================
# CLI wrapper
# ============================================================
#
# --with-ns は既定で self-contained ビルドになる。この構成では
# lisp / etc / libexec は Emacs.app バンドル内にのみ配置され、
# 実行ファイルは自分が
#
#   <bundle>/Contents/MacOS/Emacs
#
# として起動される前提で、Contents/Resources/lisp や
# Contents/MacOS/libexec を「実行ファイルからの相対パス」で解決する。
#
# ところが "make install" は $prefix/bin/emacs にも同じ実体を置く。
# これはバンドルの外にあるため相対解決に失敗し、カレントディレクトリを
# 起点に Contents/... を探しにいく。結果として、例えば ~/.emacs.d で
# 実行すると次のように壊れる (2026-07-12 実機で確認):
#
#   Warning: Lisp directory 'Contents/Resources/lisp': No such file or directory
#   Error: /Users/<user>/.emacs.d/Contents/Resources/etc/charsets: No such file or directory
#
# Homebrew の emacs-plus 等が持つ Contents/MacOS/bin/emacs ラッパーは
# ソースビルドでは生成されない。したがってここで自前のラッパーを置き、
# CLI からの `emacs` が常に .app 内のバイナリを叩くようにする。
#
# make install は毎回この壊れたバイナリを書き戻すため、
# ラッパー生成は「インストール後に必ず実行する」必要がある。
# 手作業で置き換えても次回ビルドで失われる。
#
# emacsclient はバンドル相対パスに依存しないので差し替えない。

heading "Installing CLI wrapper: $BUILD_DIR/bin/emacs -> $APP_DST"

APP_BIN="$APP_DST/Contents/MacOS/Emacs"

[[ -x "$APP_BIN" ]] || {
	echo "❌ app binary not found: $APP_BIN" >&2
	exit 1
}

mkdir -p "$BUILD_DIR/bin"

# ヒアドキュメントは非クォートで展開する ($APP_BIN を埋め込むため)。
# "$@" だけは実行時に評価させたいのでエスケープする。
cat >"$BUILD_DIR/bin/emacs" <<WRAPPER
#!/bin/sh
# Generated by build-emacs-macos.sh -- DO NOT EDIT.
# self-contained NS ビルドの実体はバンドル外では動作しないため、
# CLI からは常に .app 内のバイナリを起動する。
exec "$APP_BIN" "\$@"
WRAPPER

chmod 755 "$BUILD_DIR/bin/emacs"

# 生成したラッパーが実際に起動できることを確認する。
# ここで失敗するなら .app 側の配置(lisp/etc/native-lisp)が壊れている。
heading "Verifying CLI wrapper"

if ! "$BUILD_DIR/bin/emacs" -Q --batch \
	--eval '(message "emacs=%s native-comp=%s" emacs-version (if (and (fboundp (quote native-comp-available-p)) (native-comp-available-p)) "yes" "no"))'; then
	echo "❌ wrapper verification failed: $BUILD_DIR/bin/emacs" >&2
	exit 1
fi

# ============================================================
# Summary
# ============================================================

echo
echo "======================================="
echo "Build complete"
echo "Arch:        $ARCH"
echo "CC:          $CC"
echo "Repository:  $REPO_DIR   (source, unmodified by build)"
echo "Obj dir:     $OBJ_DIR   (rebuilt from scratch every run)"
echo "Prefix:      $BUILD_DIR"
echo "App bundle:  $APP_DST"
echo "CLI wrapper: $BUILD_DIR/bin/emacs -> $APP_DST/Contents/MacOS/Emacs"
echo "Build log:   $LOGFILE"
echo "======================================="
echo
echo "Note: \$BUILD_DIR/bin/emacs はラッパーです。"
echo "      PATH に $BUILD_DIR/bin が含まれていることを確認してください:"
echo "        type -a emacs"
