# ~/.latexmkrc
# デフォルトエンジン: LuaLaTeX-ja(和文組版)
# 従来の pLaTeX + dvipdfmx 運用から全面切り替え。

# 最大タイプセット回数
$max_repeat = 5;

# PDF を LuaLaTeX で直接生成(DVI 経由を廃止)
$pdf_mode = 4;

# LuaLaTeX 本体(SyncTeX 有効、初回エラーで停止)
$lualatex = 'lualatex %O -synctex=1 -halt-on-error %S';

# 索引(和文対応: upmendex)
$makeindex = 'upmendex %O -o %D %S';

# 参考文献
#   - 和文スタイル(jplain/junsrt 等)を使う場合: upbibtex
#   - biblatex + biber を使う場合はそちらが優先される
$bibtex = 'upbibtex %O %S';
$biber  = 'biber %O %S';

# 生成物のクリーンアップ対象に LuaLaTeX/latexmk 特有の拡張子を追加
$clean_ext = 'synctex.gz synctex.gz(busy) run.xml bbl bcf fdb_latexmk';

# ---------------------------------------------------------------
# 旧 pLaTeX(dvipdfmx)構成を文書単位で使いたい場合は、
# 対象 .tex ファイルの先頭に以下の magic comment を入れると
# latexmk がこちらを優先する。
#
#   % !TEX program = platex
#
# その場合の変換チェーンは以下(このファイルには含めていない、
# 必要な文書側の .latexmkrc または個別呼び出しで指定すること):
#
#   $latex   = 'platex %O %S -halt-on-error';
#   $dvipdf  = 'dvipdfmx %O -o %D %S';
#   $pdf_mode = 3;
# ---------------------------------------------------------------
