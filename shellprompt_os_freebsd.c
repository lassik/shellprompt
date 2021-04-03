#include <sys/sysctl.h>
#include <sys/types.h>

#include <errno.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include "shellprompt_os.h"

static int shellprompt_os_getpowerinfo(lua_State *L)
{
    int isbattery, ischarging, isdischarging, charge;

    isbattery = ischarging = isdischarging = 0;
    charge = 100;
    lua_createtable(L, 0, 0);
    lua_pushboolean(L, ischarging);
    lua_setfield(L, -2, "charging");
    lua_pushinteger(L, charge);
    lua_setfield(L, -2, "percent");
    return 1;
}

#define LUA_REGISTER(L, name) lua_register(L, #name, name)

extern void shellprompt_os_register(lua_State *L)
{
    LUA_REGISTER(L, shellprompt_os_getpowerinfo);
}
