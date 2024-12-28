#! /bin/zsh

# .gitconfig
for f in $(cat <<EOF
Brewfile
.Brewfile
.docker-alias
.gitconfig_global
.gitignore_global
.latexmkrc
.macos
.vimperator
.vimperatorrc
.vimperatorrc.js
.vimrc
.vim
.viminfo
.bin
.zshrc
EOF
); do
	test -f $f -o -d $f && (
        rsync -avh --no-perms ${f} ${HOME}/.
    )
done
