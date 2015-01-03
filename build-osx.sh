#! /bin/sh
set -e
cd "$(dirname "$0")"
builddir=build-osx
. ./build-helper-unix.sh
cd $builddir
luac -o shellprompt.luac ../shellprompt.lua
lua ../file2h.lua shellprompt.luac shellprompt_lua > shellprompt_lua.h
clang -Wall -Wextra -g -O -I . $LUA_CFLAGS -o shellprompt -DPROGVERSION="\"$PROGVERSION\"" ../shellprompt.c ../shellprompt_os_unix.c ../shellprompt_os_osx.c -framework Foundation -framework IOKit $LUA_LDFLAGS
