#! /bin/sh
set -e
cd "$(dirname "$0")"
test -d build-osx || mkdir -m 0700 build-osx
find build-osx -mindepth 1 -delete
cd build-osx
luac -o shellprompt.luac ../shellprompt.lua
lua ../file2h.lua shellprompt.luac shellprompt_lua > shellprompt_lua.h
clang -Wall -Wextra -g -O -o shellprompt -llua -I. ../shellprompt.c ../shellprompt_os_unix.c
