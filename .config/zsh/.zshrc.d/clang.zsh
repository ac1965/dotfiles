(( $+commands[clang] )) || return 1
export LDFLAGS="-L$(brew --prefix)/opt/llvm/lib -L$(brew --prefix)/opt/llvm/lib/c++ -Wl,-rpath,$(brew --prefix)/opt/llvm/lib/c++"
export CPPFLAGS="-I$(brew --prefix)/opt/llvm/include"
