#include <stdio.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include "shellprompt_lua.h"
#include "shellprompt_os.h"

#define PROGNAME "shellprompt"

#define LUA_REGISTER(L, name) lua_register(L, #name, name)

extern int main(int argc, char **argv)
{
    lua_State *L;
    int i;

    L = luaL_newstate();
    luaL_openlibs(L);

    lua_pushstring(L, PROGNAME);
    lua_setglobal(L, "PROGNAME");
    lua_pushstring(L, PROGVERSION);
    lua_setglobal(L, "PROGVERSION");
    LUA_REGISTER(L, shellprompt_os_is_superuser);
    LUA_REGISTER(L, shellprompt_os_get_username);
    LUA_REGISTER(L, shellprompt_os_get_full_hostname);
    LUA_REGISTER(L, shellprompt_os_get_cur_directory);
    LUA_REGISTER(L, shellprompt_os_ensure_dir_exists);
    LUA_REGISTER(L, shellprompt_os_get_output);
    LUA_REGISTER(L, shellprompt_os_unamesys);
    LUA_REGISTER(L, shellprompt_os_termcolsrows);
    LUA_REGISTER(L, shellprompt_os_milliseconds);
    shellprompt_os_register(L);

    lua_createtable(L, argc - 1, 0);
    for (i = 1; i < argc; i++) {
        lua_pushinteger(L, i);
        lua_pushstring(L, argv[i]);
        lua_settable(L, -3);
    }
    lua_setglobal(L, "arg");

    if (luaL_loadbuffer(L, shellprompt_lua, sizeof(shellprompt_lua), PROGNAME)
        || lua_pcall(L, 0, 0, 0)) {
        fprintf(stderr, "%s: error: %s\n", PROGNAME, lua_tostring(L, -1));
        return 1;
    }

    lua_close(L);
    return 0;
}
