# 最大のタイプセット回数
$max_repeat = 5;
# DVI経由でPDFをビルドすることを明示
$pdf_mode = 3;

# pLaTeXを使う
# -halt-on-error:初めのエラーで終わらせる
$latex = 'platex %O %S -halt-on-error';

# pBibTeXを使う(参考文献)
$bibtex = 'pbibtex %O %S';

# Mendexを使う(索引)
$makeindex = 'mendex %O -o %D %S';

# DVIからPDFへの変換
$dvipdf = 'dvipdfmx %O -o %D %S';