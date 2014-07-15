#include <stdio.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "shellprompt_os.h"
#include "shellprompt_lua.h"

#define PROGNAME "shellprompt"

static lua_State *L;

static void addfunc(const char *name, int (*func)(lua_State *))
{
    lua_pushcfunction(L, func);
    lua_setfield(L, -2, name);
}

extern int main(int argc, char **argv)
{
    int i;

    L = luaL_newstate();
    luaL_openlibs(L);

    lua_newtable(L);
    addfunc("is_superuser", shellprompt_os_is_superuser);
    addfunc("get_username", shellprompt_os_get_username);
    addfunc("get_full_hostname", shellprompt_os_get_full_hostname);
    addfunc("get_cur_directory", shellprompt_os_get_cur_directory);
    addfunc("get_output", shellprompt_os_get_output);
    lua_setglobal(L, "shellprompt_os");

    lua_createtable(L, argc-1, 0);
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
