#! /bin/sh
set -e
cd "$(dirname "$0")"
builddir=build-linux
. ./build-helper-unix.sh
cd $builddir
cat ../shellprompt_os_linux.lua ../shellprompt.lua > shellpromptall.lua
luac -o shellprompt.luac shellpromptall.lua
lua ../file2h.lua shellprompt.luac shellprompt_lua > shellprompt_lua.h
gcc -Wall -Wextra -g -O -I . $LUA_CFLAGS -o shellprompt -DPROGVERSION="\"$PROGVERSION\"" ../shellprompt.c ../shellprompt_os_unix.c ../shellprompt_os_regstub.c $LUA_LDFLAGS
