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
.zshenv
.zstyles
.local
.config
.cache
EOF
); do
	test -f $f -o -d $f && (
        rsync -ah --no-perms ${f} ${HOME}/. && echo -- ${f}
    )
done
