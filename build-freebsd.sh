#! /bin/sh
set -e
cd "$(dirname "$0")"
builddir=build-freebsd
LUA_CFLAGS="-I /usr/local/include/lua52"
LUA_LDFLAGS="-L /usr/local/lib -l lua-5.2"
. ./build-helper-unix.sh
cd $builddir
luac52 -o shellprompt.luac ../shellprompt.lua
lua52 ../file2h.lua shellprompt.luac shellprompt_lua > shellprompt_lua.h
clang -Wall -Wextra -Wno-self-assign -g -O -I . $LUA_CFLAGS -o shellprompt -DPROGVERSION="\"$PROGVERSION\"" ../shellprompt.c ../shellprompt_os_unix.c ../shellprompt_os_freebsd.c $LUA_LDFLAGS
