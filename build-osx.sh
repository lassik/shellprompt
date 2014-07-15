#! /bin/sh
set -e
cd "$(dirname "$0")"
test -e build-osx && rm -rf build-osx
mkdir -m 0700 build-osx
cd build-osx
luac -o shellprompt.luac ../shellprompt.lua
clang -Wall -Wextra -g -O -o file2h ../file2h.c
./file2h shellprompt_lua shellprompt.luac > shellprompt_lua.h
clang -Wall -Wextra -g -O -o shellprompt -llua -I. ../shellprompt.c ../shellprompt_os_unix.c
