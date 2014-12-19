#! /bin/sh
set -e
cd "$(dirname "$0")"
test -d build-linux || mkdir -m 0700 build-linux
find build-linux -mindepth 1 -delete
cd build-linux
luac -o shellprompt.luac ../shellprompt.lua
lua ../file2h.lua shellprompt.luac shellprompt_lua > shellprompt_lua.h
LUA="${LUA:-$(pkg-config --cflags --libs lua5.2)}"
gcc -Wall -Wextra -g -O -I . -o shellprompt ../shellprompt.c ../shellprompt_os_unix.c $LUA
