#! /bin/sh

for f in $(cat <<EOF
.Brewfile
.gitconfig
.gitignore
.gitmodules
.vim
.vimperator
.vimperatorrc
.vimperatorrc.js
bin
EOF
); do
	test -f $f -o -d $f && (
		echo -- $f
		ln -fs $(pwd)/$f ~/.
	)
done
