#! /bin/sh

for f in $(cat <<EOF
.Brewfile
.gitconfig
bin
.vimperator
.vimperatorrc
.vimperatorrc.js
.vimrc
.vim
EOF
); do
	test -f $f -o -d $f && (
		echo -- $f
		ln -fs $(pwd)/$f ~/.
	)
done
