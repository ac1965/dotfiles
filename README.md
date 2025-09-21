
# dotfiles

## MacOS のクリーンアップ

- アクティベーションを外す
- MacBook Pro (AppleM4 14-inch, 11.2024)
- MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)

   https://support.apple.com/ja-jp/HT212749

## インストール

```
  $ git clone https://github.com/ac1965/dotfiles.git
  $ dotfiles/setup.sh
```

## Homebrew のインストール

- ターミナルから次のコマンドをコピペ

```
	cd Downloads && git clone https://github.com/ac1965/dotfiles
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    brew bundle --global
```

### iTerm2

`brew bundle --global` を実行すると *Brewfile* に記載されたパッケージのひとつとして iTerm2 もインストールする。

単独でイントールする場合は以下のコマンドを実行する。

```
    brew install --cask iterm2
```

https://iterm2colorschemes.com

https://zenn.dev/aldagram_tech/articles/0fc671a41021f3

- ホットキー

- 任意のデスクトップ上にフルスクリーンで重ねて表示

- ショートカットキー

```
    -- 画面の分割
    command + d 画面を左右に分割
    command + shift + d 画面を上下に分割
    command + n ウィンドウを作成
    command + w ウィンドウを閉じる
	command + t タブを作成
    command + 矢印キー タブの移動
    command + [/] 画面の移動
    command + return 最大化/元のサイズ
```

### pyenv & pipenv

```
    brew install pyenv
```

    https://qiita.com/santa_sukitoku/items/6cbb325a895653c81b36

### MacTex

MacTex(mactex-no-gui) は `Homebrew のインストール` で インストールされる。
パッケージの更新は tlmgr を使い、印刷サイズを A4サイズを設定しておく。

``` bash
sudo tlmgr update --self --all
sudo tlmgr paper a4
```

``` bash
$ cat <<EOF > ~/.latexmkrc
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
EOF
```

### private

個人情報は private.tar.xz.enc

``` bash
decrypt private.tar.xz.enc | tar -xvJ
```

``` bash
tar -cJvf private.tar.xz private
encrypt private.tar.xz
```

decrypt
``` bash
#!/bin/bash

openssl enc -d -aes-256-cbc -pbkdf2 -iter 99999 -in "${1}"
```

encrypt
``` bash
#!/bin/bash

openssl enc -d -aes-256-cbc -pbkdf2 -iter 99999 -in "${1}"
```


### Emacs のインストール

```
  build-emacs.sh --native
```

[Emacs 01](https://github.com/ac1965/dotfiles/blob/master/.docs/Emacs-01.org)

---

# 📑 Markdown チートシート

## 1. 見出し

```markdown
# 見出し1
## 見出し2
### 見出し3
#### 見出し4
##### 見出し5
###### 見出し6
```

---

## 2. 強調

```markdown
*斜体*   または  _斜体_
**太字** または  __太字__
~~取り消し線~~
```

---

## 3. リスト

### 箇条書き（unordered list）

```markdown
- アイテム1
- アイテム2
  - サブアイテム
    - サブサブアイテム
```

### 番号付きリスト（ordered list）

```markdown
1. アイテム1
2. アイテム2
   1. サブアイテム
```

---

## 4. リンクと画像

```markdown
[リンクテキスト](https://example.com)
![代替テキスト](https://example.com/image.png)

[リンク付き画像](https://example.com)
![Alt](https://example.com/img.png)
```

---

## 5. 引用

```markdown
> これは引用です
>> ネストされた引用
```

---

## 6. コード

### インラインコード

```markdown
これは `インラインコード` です
```

### コードブロック

\`\`\`言語名
コード内容
\`\`\`

例:

````markdown
```python
print("Hello, Markdown!")
````

````

---

## 7. 水平線
```markdown
---
````

---

## 8. 表

```markdown
| 見出し1 | 見出し2 | 見出し3 |
|---------|---------|---------|
| セル1   | セル2   | セル3   |
| セル4   | セル5   | セル6   |
```

---

## 9. チェックリスト

```markdown
- [ ] 未完了タスク
- [x] 完了タスク
```

---

## 10. その他便利記法

* **自動リンク**: `<https://example.com>`
* **エスケープ**: 特殊文字は `\*` のようにバックスラッシュで回避
