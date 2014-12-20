#! /bin/sh
set -e
cd "$(dirname "$0")"
if test -f ./build-config.sh ; then
    echo "Using custom build options from build-config.sh"
    . ./build-config.sh
else
    echo "Using default build options (build-config.sh not found)"
fi
if test -z "$LUA_CFLAGS" ; then
    LUA_CFLAGS="$(pkg-config --cflags lua5.2)"
fi
if test -z "$LUA_LDFLAGS" ; then
    LUA_LDFLAGS="$(pkg-config --libs lua5.2)"
fi
if ! test -z "$LUA_PATH" ; then
    export PATH="$LUA_PATH:$PATH"
fi
if test "$1" = release ; then
    PROGVERSION="$2"
else
    PROGVERSION="built on $(date "+%Y-%m-%d") by $(whoami)"
fi
test -d build-linux || mkdir -m 0700 build-linux
find build-linux -mindepth 1 -delete
cd build-linux
cat ../shellprompt_os_linux.lua ../shellprompt.lua > shellpromptall.lua
luac -o shellprompt.luac shellpromptall.lua
lua ../file2h.lua shellprompt.luac shellprompt_lua > shellprompt_lua.h
gcc -Wall -Wextra -g -O -I . $LUA_CFLAGS -o shellprompt -DPROGVERSION="\"$PROGVERSION\"" ../shellprompt.c ../shellprompt_os_unix.c $LUA_LDFLAGS
