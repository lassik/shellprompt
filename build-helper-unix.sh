# Do not run this script directly. It's is just a helper for others.
if test -f ./build-config.sh; then
    echo "Using custom build options from build-config.sh"
    . ./build-config.sh
else
    echo "Using default build options (build-config.sh not found)"
fi
if test -z "$LUA_CFLAGS"; then
    LUA_CFLAGS="$(pkg-config --cflags lua5.4)"
fi
if test -z "$LUA_LDFLAGS"; then
    LUA_LDFLAGS="$(pkg-config --libs lua5.4)"
fi
if ! test -z "$LUA_PATH"; then
    export PATH="$LUA_PATH:$PATH"
fi
if test "$1" = release; then
    PROGVERSION="$2"
else
    PROGVERSION="built on $(date "+%Y-%m-%d") by $(whoami)"
fi
test -d "$builddir" || mkdir -m 0700 "$builddir"
find "$builddir" -mindepth 1 -delete
