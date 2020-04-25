#! /bin/sh

for f in $(cat <<EOF
.Brewfile
.emacs.d
.git
.gitconfig
.gitignore
.gitmodules
.setup.sh.swp
.vim
.vimperator
.vimperatorrc
.vimperatorrc.js
bin
iterm2-colors
setup.sh
EOF
); do
	test -f $f -o -d $f && (
		echo -- $f
		ln -fs $f ~
	)
done
