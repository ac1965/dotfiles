#! /bin/sh

# .gitconfig 
for f in $(cat <<EOF
.Brewfile
.docker-alias
.gitconfig_global
.gitignore_global
.vimperator
.vimperatorrc
.vimperatorrc.js
.vimrc
.vim
.viminfo
.bin
EOF
); do
	test -f $f -o -d $f && (
		echo -- $f
		ln -fs $(pwd)/$f ~/.
	)
done
