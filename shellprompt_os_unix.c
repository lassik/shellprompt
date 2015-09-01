#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/time.h>
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

static struct utsname names;

static int push_string_or_blank(lua_State *L, const char *str)
{
    lua_pushstring(L, str ? str : "");
    return 1;
}

extern int shellprompt_os_is_superuser(lua_State *L)
{
    lua_pushboolean(L, !geteuid());
    return 1;
}

extern int shellprompt_os_get_username(lua_State *L)
{
    struct passwd *pw;

    return push_string_or_blank(
        L,
        (pw = getpwuid(getuid())) ? pw->pw_name : 0);
}

extern int shellprompt_os_get_full_hostname(lua_State *L)
{
    return push_string_or_blank(
        L,
        (uname(&names) != -1) ? names.nodename : 0);
}

extern int shellprompt_os_unamesys(lua_State *L)
{
    return push_string_or_blank(
        L,
        (uname(&names) != -1) ? names.sysname : 0);
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

    /* It's ridiculous that I'm manipulating strings through char
     * pointers in 2015 but I can't think of a simpler way :( */
    if (!(ptr = path = strdup(luaL_checkstring(L, 1)))) {
        return luaL_error(L, "ouf of memory");
    }
    while (*ptr == '/') {
        ptr++;
    }
    do {
        ptr = strchr(ptr, '/');
        if (ptr) {
            *ptr = 0;
        }
        if ((mkdir(path, 0700) == -1) && (errno != EEXIST)) {
            /* I would free(path) here but I'm not confident that
             * free() preserves errno in all cases. Meh. */
            return luaL_error(L, "mkdir %s: %s", path, strerror(errno));
        }
        if (ptr) {
            *ptr++ = '/';
        }
    } while (ptr);
    free(path);
    return 0;
}

/* TODO: Only reads up to LUAL_BUFFERSIZE bytes of input. */
extern int shellprompt_os_get_output(lua_State *L)
{
    luaL_Buffer ans;
    char *buf;
    pid_t child;
    size_t nremain, nfill;
    ssize_t nread;
    int fds[2] = {-1, -1};
    int status;
    int argc, i;
    const char **argv;

    luaL_buffinit(L, &ans);
    argv = 0;
    argc = lua_gettop(L);
    if (argc < 1) {
        goto cleanup;
    }
    if (!(argv = calloc(argc+1, sizeof(*argv)))) {
        goto cleanup;
    }
    for (i = 0; i < argc; i++) {
        if (!(argv[i] = luaL_checkstring(L, i+1))) {
            goto cleanup;
        }
    }
    if (pipe(fds) == -1) {
        goto cleanup;
    }
    if ((child = fork()) == (pid_t)-1) {
        goto cleanup;
    }
    if (!child) {
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
    nremain = LUAL_BUFFERSIZE;
    nfill = 0;
    while (nremain > 0) {
        nread = read(fds[0], buf+nfill, nremain);
        if ((nread == (ssize_t)-1) && (errno == EINTR)) {
            continue;
        }
        if (nread <= 0) {
            break;
        }
        nfill += nread;
        nremain -= nread;
    }
    luaL_addsize(&ans, (size_t)nfill);
    waitpid(child, &status, 0);
cleanup:
    close(fds[0]);
    close(fds[1]);
    free(argv);
    luaL_pushresult(&ans);
    return 1;
}

extern int shellprompt_os_termcolsrows(lua_State *L)
{
    static struct winsize ws;

    if (ioctl(0, TIOCGWINSZ, &ws) == -1) {
        lua_pushnil(L);
        lua_pushnil(L);
    } else {
        lua_pushinteger(L, ws.ws_col);
        lua_pushinteger(L, ws.ws_row);
    }
    return 2;
}

extern int shellprompt_os_milliseconds(lua_State *L)
{
    struct timeval tv;

    gettimeofday(&tv, 0);
    lua_pushinteger(L, 1000*tv.tv_sec + tv.tv_usec/1000);
    return 1;
}
