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
	imagemagick tree-sitter gmp
)

heading "Installing required Homebrew packages"

for f in "${BREW_FORMULAS[@]}"; do
	brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"
done

# ============================================================
# Apple Clang Toolchain (Stable Cocoa build)
# ============================================================

heading "Configuring Apple Clang toolchain"

export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export LD="$CC"
export AR="$(xcrun --find ar)"
export RANLIB="$(xcrun --find ranlib)"
export NM="$(xcrun --find nm)"

echo "Using Clang: $CC"

# ============================================================
# SDK and Flags
# ============================================================

heading "Configuring SDK and compiler flags"

export SDKROOT="$(xcrun --show-sdk-path)"

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
	--with-imagemagick \
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
# インストール済みのため、ここで未strip・バージョン管理外の
# 生バイナリで上書きするとインストールの整合性が崩れる。
# 意図的に上書きしたい場合のみ以下のコメントを外すこと。
#
# mkdir -p "$BUILD_DIR/bin"
# install -m 755 "$OBJ_DIR/src/emacs" "$BUILD_DIR/bin/emacs"
# install -m 755 "$OBJ_DIR/lib-src/emacsclient" "$BUILD_DIR/bin/emacsclient"

APP_DST="/Applications/Emacs.app"
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
# Summary
# ============================================================

echo
echo "======================================="
echo "Build complete"
echo "Arch:       $ARCH"
echo "CC:         $CC"
echo "Repository: $REPO_DIR   (source, unmodified by build)"
echo "Obj dir:    $OBJ_DIR   (rebuilt from scratch every run)"
echo "Prefix:     $BUILD_DIR"
echo "Build log:  $LOGFILE"
echo "======================================="
