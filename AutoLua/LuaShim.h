//
//  LuaShim.h
//  AutoLua
//
//  Lua 5.4 宏包装 — Swift 无法直接调用 C 宏
//

#ifndef LuaShim_h
#define LuaShim_h

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

// ---- 常量 ---- (Xcode 会识别 static const, Swift 可调用)

static const int kLuaOK         = 0;
static const int kLuaTNIL       = 0;
static const int kLuaTNUMBER    = 3;
static const int kLuaTSTRING    = 4;
static const int kLuaTTABLE     = 5;

// ---- Lua API 宏包装 ----

static inline lua_Integer au_tointeger(lua_State *L, int idx) {
    return lua_tointegerx(L, idx, NULL);
}

static inline lua_Number au_tonumber(lua_State *L, int idx) {
    return lua_tonumberx(L, idx, NULL);
}

static inline const char *au_tostring(lua_State *L, int idx) {
    return lua_tolstring(L, idx, NULL);
}

static inline void au_pop(lua_State *L, int n) {
    lua_settop(L, -(n)-1);
}

static inline int au_isnil(lua_State *L, int idx) {
    return lua_type(L, idx) == LUA_TNIL;
}

static inline int au_istable(lua_State *L, int idx) {
    return lua_type(L, idx) == LUA_TTABLE;
}

static inline int au_isnumber(lua_State *L, int idx) {
    return lua_type(L, idx) == LUA_TNUMBER;
}

static inline int au_isstring(lua_State *L, int idx) {
    return lua_type(L, idx) == LUA_TSTRING;
}

static inline int au_pcall(lua_State *L, int nargs, int nresults, int errfunc) {
    return lua_pcallk(L, nargs, nresults, errfunc, 0, NULL);
}

static inline int au_loadstring(lua_State *L, const char *s) {
    return luaL_loadbuffer(L, s, strlen(s), s);
}

#endif /* LuaShim_h */
