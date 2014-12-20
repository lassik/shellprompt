#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/utsname.h>
#include <sys/wait.h>

#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "shellprompt_os.h"

extern int shellprompt_os_is_superuser(lua_State *L)
{
    lua_pushboolean(L, (geteuid() == 0));
    return 1;
}

extern int shellprompt_os_get_username(lua_State *L)
{
    const char *name;
    struct passwd *pw;

    name = "";
    if ((pw = getpwuid(getuid())) && pw->pw_name) {
        name = pw->pw_name;
    }
    lua_pushstring(L, name);
    return 1;
}

extern int shellprompt_os_get_full_hostname(lua_State *L)
{
    const char *name;
    static struct utsname names;

    name = "";
    if ((uname(&names) != -1) && names.nodename) {
        name = names.nodename;
    }
    lua_pushstring(L, name);
    return 1;
}

extern int shellprompt_os_get_cur_directory(lua_State *L)
{
    char *path;

    if ((path = getcwd(0, 0))) {
        lua_pushstring(L, path);
        free(path);
    } else {
        lua_pushstring(L, "");
    }
    return 1;
}

extern int shellprompt_os_ensure_dir_exists(lua_State *L)
{
    char *ptr;
    char *path;

    ptr = path = strdup(luaL_checkstring(L, 1));
    while (*ptr == '/') {
        ptr++;
    }
    do {
        ptr = strchr(ptr, '/');
        if (ptr) *ptr = 0;
        if ((mkdir(path, 0700) == -1) && (errno != EEXIST)) {
            return luaL_error(L, "mkdir %s: %s", path, strerror(errno));
        }
        if (ptr) *ptr++ = '/';
    } while (ptr);
    free(path);
    return 0;
}

extern int shellprompt_os_get_output(lua_State *L)
{
    luaL_Buffer ans;
    char *buf;
    pid_t child;
    ssize_t nread;
    int fds[2] = {-1, -1};
    int status;
    int argc, i;
    const char **argv;

    luaL_buffinit(L, &ans);
    argv = 0;
    argc = lua_gettop(L);
    if (argc < 1) goto cleanup;
    if (!(argv = calloc(argc+1, sizeof(*argv)))) goto cleanup;
    for (i = 0; i < argc; i++) {
        if (!(argv[i] = luaL_checkstring(L, i+1))) goto cleanup;
    }
    if(pipe(fds) == -1) goto cleanup;
    if((child = fork()) == (pid_t)-1) goto cleanup;
    if(!child) {
        int devnull;

        close(fds[0]);
        devnull = open("/dev/null", O_RDWR);
        dup2(devnull, 0);  /* stdin */
        dup2(fds[1],  1);  /* stdout */
        dup2(devnull, 2);  /* stderr */
        execvp(argv[0], (char **)argv);
        _exit(127);
    }
    close(fds[1]);
    buf = luaL_prepbuffer(&ans);
    if ((nread = read(fds[0], buf, LUAL_BUFFERSIZE)) == (ssize_t)-1) {
        nread = 0;
    }
    while((nread > 0) && (buf[nread-1] == '\n')) {
        nread--;
    }
    luaL_addsize(&ans, (size_t)nread);
    waitpid(child, &status, 0);
cleanup:
    close(fds[0]);
    close(fds[1]);
    free(argv);
    luaL_pushresult(&ans);
    return 1;
}

extern int shellprompt_os_unamesys(lua_State *L)
{
    static struct utsname names;
    const char *sysname;

    sysname = "";
    if ((uname(&names) != -1) && names.sysname) {
        sysname = names.sysname;
    }
    lua_pushstring(L, sysname);
    return 1;
}

extern int shellprompt_os_termcolsrows(lua_State *L)
{
    static struct winsize w;

    if (ioctl(0, TIOCGWINSZ, &w) == -1) {
        lua_pushnil(L);
        lua_pushnil(L);
    } else {
        lua_pushinteger(L, w.ws_col);
        lua_pushinteger(L, w.ws_row);
    }
    return 2;
}
