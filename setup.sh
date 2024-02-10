#! /bin/zsh

# .gitconfig
for f in $(cat <<EOF
.Brewfile
.docker-alias
.gitconfig_global
.gitignore_global
.macos
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
        test -e "$HOME/$f" && rm -f "$HOME/$f"
        ln -fs "$(pwd)/$f" "$HOME/${f:t}"
	)
done
