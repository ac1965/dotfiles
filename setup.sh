#! /bin/zsh

# .gitconfig
for f in $(cat <<EOF
.Brewfile
.bin
.config
.docs
.docker-alias
.gitconfig_global
.gitignore_global
.latexmkrc
.local
.macos
.vim
.viminfo
.vimperator
.vimperatorrc
.vimperatorrc.js
.vimrc
.zshenv
.zshrc
.zstyles
Brewfile
EOF
); do
	test -f $f -o -d $f && (
        rsync -ah --no-perms ${f} ${HOME}/. && echo -- ${f}
    )
done
