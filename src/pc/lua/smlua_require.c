// Backported from upstream sm64coopdx. Newer character packs split their code across
// subfolders and load it with require(), which this version of the engine didn't have

#include <stdbool.h>
#include "smlua.h"
#include "smlua_require.h"
#include "pc/mods/mods.h"
#include "pc/mods/mods_utils.h"

#define LOADING_SENTINEL ((void*)-1)

// table to track loaded modules per mod
void smlua_get_or_create_mod_loaded_table(lua_State* L, struct Mod* mod) {
    char registryKey[SYS_MAX_PATH + 16] = "";
    snprintf(registryKey, sizeof(registryKey), "mod_loaded_%s", mod->relativePath);

    lua_getfield(L, LUA_REGISTRYINDEX, registryKey);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setfield(L, LUA_REGISTRYINDEX, registryKey);
    }
}

bool smlua_get_cached_module_result(lua_State* L, struct Mod* mod, struct ModFile* file) {
    smlua_get_or_create_mod_loaded_table(L, mod);
    lua_getfield(L, -1, file->relativePath);

    if (lua_touserdata(L, -1) == LOADING_SENTINEL) {
        LOG_LUA_LINE("loop or previous error loading module '%s'", file->relativePath);
        lua_pop(L, 1); // pop sentinel
        lua_pushnil(L);
        lua_remove(L, -2); // remove loaded table
        return true;
    }

    if (lua_isnil(L, -1)) {
        // not cached
        lua_pop(L, 2); // pop nil and loaded table
        return false;
    }

    // cached, remove loaded table and leave value on top
    lua_remove(L, -2);
    return true;
}

void smlua_mark_module_as_loading(lua_State* L, struct Mod* mod, struct ModFile* file) {
    smlua_get_or_create_mod_loaded_table(L, mod);
    lua_pushlightuserdata(L, LOADING_SENTINEL);
    lua_setfield(L, -2, file->relativePath);
    lua_pop(L, 1); // pop loaded table
}

void smlua_cache_module_result(lua_State* L, struct Mod* mod, struct ModFile* file, s32 prevTop) {
    if (lua_gettop(L) == prevTop) {
        lua_pushboolean(L, 1);
    } else if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_pushboolean(L, 1);
    }

    smlua_get_or_create_mod_loaded_table(L, mod);

    lua_pushvalue(L, -2); // duplicate result
    lua_setfield(L, -2, file->relativePath); // loaded[file->relativePath] = result
    lua_pop(L, 1); // pop loaded table
}

static void smlua_copy_with_forward_slashes(char* destination, const char* source) {
    snprintf(destination, SYS_MAX_PATH, "%s", source);
    for (char* c = destination; *c != '\0'; c++) {
        if (*c == '\\') { *c = '/'; }
    }
}

// Joins a module name onto the running file's folder, resolving ./ and ../
static void smlua_resolve_module_path(const char* baseFolder, const char* moduleName, char* out) {
    char base[SYS_MAX_PATH] = "";
    char name[SYS_MAX_PATH] = "";
    smlua_copy_with_forward_slashes(base, baseFolder);
    smlua_copy_with_forward_slashes(name, moduleName);

    char* rest = name;
    while (true) {
        if (strncmp(rest, "./", 2) == 0) {
            rest += 2;
        } else if (strncmp(rest, "../", 3) == 0) {
            rest += 3;
            // drop the last folder from base, which ends in a slash
            size_t len = strlen(base);
            if (len > 0) { base[--len] = '\0'; }
            while (len > 0 && base[len - 1] != '/') { base[--len] = '\0'; }
        } else {
            break;
        }
    }

    snprintf(out, SYS_MAX_PATH, "%s%s", base, rest);
}

static struct ModFile* smlua_find_mod_file(const char* moduleName) {
    char basePath[SYS_MAX_PATH] = "";
    char absolutePath[SYS_MAX_PATH] = "";
    char relative[SYS_MAX_PATH] = "";

    if (!gLuaActiveMod) {
        return NULL;
    }

    // get the directory of the current file
    if (gLuaActiveModFile) {
        path_get_folder(gLuaActiveModFile->relativePath, basePath);
    }

    // resolve moduleName to a path relative to mod root
    smlua_resolve_module_path(basePath, moduleName, absolutePath);

    char luaName[SYS_MAX_PATH + 8] = "";
    char luacName[SYS_MAX_PATH + 8] = "";
    snprintf(luaName, sizeof(luaName), "%s.lua", absolutePath);
    snprintf(luacName, sizeof(luacName), "%s.luac", absolutePath);

    // since mods' relativePaths are relative to the mod's root, we can do a direct comparison
    for (int i = 0; i < gLuaActiveMod->fileCount; i++) {
        struct ModFile* file = &gLuaActiveMod->files[i];

        // don't consider the currently running file
        if (file == gLuaActiveModFile) {
            continue;
        }

        // only consider lua files
        if (!str_ends_with(file->relativePath, ".lua") && !str_ends_with(file->relativePath, ".luac")) {
            continue;
        }

        smlua_copy_with_forward_slashes(relative, file->relativePath);
        if (!strcmp(relative, luaName) || !strcmp(relative, luacName)) {
            return file;
        }
    }

    return NULL;
}

static int smlua_custom_require(lua_State* L) {
    const char* moduleName = luaL_checkstring(L, 1);

    struct Mod* activeMod = gLuaActiveMod;
    if (!activeMod) {
        LOG_LUA_LINE("require() called outside of mod context");
        return 0;
    }

    if (str_ends_with(moduleName, "/") || str_ends_with(moduleName, "\\")) {
        LOG_LUA_LINE("cannot require a directory");
        return 0;
    }

    // find the file in mod files
    struct ModFile* file = smlua_find_mod_file(moduleName);
    if (!file) {
        LOG_LUA_LINE("module '%s' not found in mod files", moduleName);
        return 0;
    }

    // check cache first
    if (smlua_get_cached_module_result(L, activeMod, file)) {
        return 1;
    }

    // mark module as "loading" to prevent recursion
    smlua_mark_module_as_loading(L, activeMod, file);

    // cache the previous mod file
    struct ModFile* prevModFile = gLuaActiveModFile;

    // load and execute
    gLuaActiveModFile = file;
    s32 prevTop = lua_gettop(L);

    int rc = smlua_load_script(activeMod, file, 0, false);

    if (rc == LUA_OK) {
        smlua_cache_module_result(L, activeMod, file, prevTop);
    }

    gLuaActiveModFile = prevModFile;

    return 1; // return the module value
}

void smlua_init_require_system(void) {
    lua_State* L = gLuaState;
    if (!L) { return; }

    lua_pushcfunction(L, smlua_custom_require);
    lua_setglobal(L, "require");
}
