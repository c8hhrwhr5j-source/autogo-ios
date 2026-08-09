//
//  BridgeImplementation.m
//  AutoLua
//
//  ObjC 实现 — IOKit HID 事件 + IOSurface 屏幕捕获 + Lua 引擎
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <mach/kern_return.h>
#import <CoreGraphics/CoreGraphics.h>

// IOSurface 类型通过 UIKit→CoreImage→CoreVideo→IOSurface 间接可用
// 函数仍通过 dlopen/dlsym 动态加载
#define kIOSurfaceLockReadOnly 0x00000001

// ============================================================
// IOKit HID 事件实现
// ============================================================

CFTypeRef AutoLuaCreateDigitizerEvent(
    uint64_t timestamp,
    int32_t transducerType,
    int32_t index,
    int32_t identifier,
    int32_t eventMask,
    int32_t buttonMask,
    float x,
    float y,
    float z,
    float tipPressure,
    int32_t twist,
    int32_t range,
    int32_t quality,
    int32_t density,
    int32_t irregularity,
    int32_t majorRadius
) {
    static void *handle = NULL;
    static CFTypeRef (*fn)(CFAllocatorRef, uint64_t, int32_t, int32_t, int32_t, int32_t, int32_t, float, float, float, float, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t) = NULL;

    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (handle) {
            fn = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
        }
    }

    if (fn) {
        return fn(NULL, timestamp, transducerType, index, identifier, eventMask, buttonMask, x, y, z, tipPressure, twist, range, quality, density, irregularity, majorRadius);
    }
    return NULL;
}

void AutoLuaHIDEventSetFloat(CFTypeRef event, int32_t field, float value) {
    static void (*fn)(CFTypeRef, int32_t, float) = NULL;
    if (!fn) {
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (h) fn = dlsym(h, "IOHIDEventSetFloatValue");
    }
    if (fn) fn(event, field, value);
}

void AutoLuaHIDEventSetInteger(CFTypeRef event, int32_t field, int32_t value) {
    static void (*fn)(CFTypeRef, int32_t, int32_t) = NULL;
    if (!fn) {
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (h) fn = dlsym(h, "IOHIDEventSetIntegerValue");
    }
    if (fn) fn(event, field, value);
}

CFTypeRef AutoLuaHIDEventSystemClientCreate(void) {
    static CFTypeRef (*fn)(CFAllocatorRef) = NULL;
    if (!fn) {
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (h) fn = dlsym(h, "IOHIDEventSystemClientCreate");
    }
    if (fn) return fn(NULL);
    return NULL;
}

int32_t AutoLuaHIDEventSystemClientDispatchEvent(CFTypeRef client, CFTypeRef event) {
    static int32_t (*fn)(CFTypeRef, CFTypeRef) = NULL;
    if (!fn) {
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (h) fn = dlsym(h, "IOHIDEventSystemClientDispatchEvent");
    }
    if (fn) return fn(client, event);
    return -1;
}

// ============================================================
// IOSurface 屏幕捕获实现
// ============================================================

// IOMobileFramebuffer 私有 API
typedef struct __IOMobileFramebuffer *IOMobileFramebufferConnection;

static int (*IOMobileFramebufferGetMainDisplay)(IOMobileFramebufferConnection *connect) = NULL;
static int (*IOMobileFramebufferGetSurface)(IOMobileFramebufferConnection connect, int surfaceID, IOSurfaceRef *surface) = NULL;

// IOSurface 私有框架函数指针（动态加载）
static kern_return_t (*IOSurfaceLockFunc)(IOSurfaceRef, uint32_t, uint32_t *) = NULL;
static kern_return_t (*IOSurfaceUnlockFunc)(IOSurfaceRef, uint32_t, uint32_t *) = NULL;
static size_t (*IOSurfaceGetWidthFunc)(IOSurfaceRef) = NULL;
static size_t (*IOSurfaceGetHeightFunc)(IOSurfaceRef) = NULL;
static size_t (*IOSurfaceGetBytesPerRowFunc)(IOSurfaceRef) = NULL;
static uint32_t (*IOSurfaceGetPixelFormatFunc)(IOSurfaceRef) = NULL;
static void *(*IOSurfaceGetBaseAddressFunc)(IOSurfaceRef) = NULL;

static void loadIOMobileFramebuffer(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 加载 IOSurface 私有框架
        void *iosHandle = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY);
        if (iosHandle) {
            IOSurfaceLockFunc = dlsym(iosHandle, "IOSurfaceLock");
            IOSurfaceUnlockFunc = dlsym(iosHandle, "IOSurfaceUnlock");
            IOSurfaceGetWidthFunc = dlsym(iosHandle, "IOSurfaceGetWidth");
            IOSurfaceGetHeightFunc = dlsym(iosHandle, "IOSurfaceGetHeight");
            IOSurfaceGetBytesPerRowFunc = dlsym(iosHandle, "IOSurfaceGetBytesPerRow");
            IOSurfaceGetPixelFormatFunc = dlsym(iosHandle, "IOSurfaceGetPixelFormat");
            IOSurfaceGetBaseAddressFunc = dlsym(iosHandle, "IOSurfaceGetBaseAddress");
        }

        // 加载 IOMobileFramebuffer 私有框架
        void *handle = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
        if (handle) {
            IOMobileFramebufferGetMainDisplay = dlsym(handle, "IOMobileFramebufferGetMainDisplay");
            IOMobileFramebufferGetSurface = dlsym(handle, "IOMobileFramebufferGetSurface");
        }

        // 备用：CARenderServer
        if (!IOMobileFramebufferGetMainDisplay) {
            (void)dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
            // CARenderServerRenderDisplay 可作为备用
        }
    });
}

IOSurfaceRef AutoLuaGetMainDisplaySurface(void) {
    loadIOMobileFramebuffer();

    if (!IOMobileFramebufferGetMainDisplay || !IOMobileFramebufferGetSurface) {
        NSLog(@"[ScreenCapture] IOMobileFramebuffer 不可用");
        return NULL;
    }

    IOMobileFramebufferConnection connect = NULL;
    kern_return_t ret = IOMobileFramebufferGetMainDisplay(&connect);
    if (ret != KERN_SUCCESS || !connect) {
        NSLog(@"[ScreenCapture] 无法获取主显示器连接: %d", ret);
        return NULL;
    }

    IOSurfaceRef surface = NULL;
    ret = IOMobileFramebufferGetSurface(connect, 0, &surface);
    if (ret != KERN_SUCCESS || !surface) {
        NSLog(@"[ScreenCapture] 无法获取 IOSurface: %d", ret);
        return NULL;
    }

    return surface;
}

#pragma mark - Surface 尺寸查询

int AutoLuaSurfaceGetWidth(IOSurfaceRef surface) {
    if (!surface) return 0;
    // 回退：直接读 surface 属性，依赖前一步 dlopen 已加载
    if (IOSurfaceGetWidthFunc) return (int)IOSurfaceGetWidthFunc(surface);
    return 0;
}

int AutoLuaSurfaceGetHeight(IOSurfaceRef surface) {
    if (!surface) return 0;
    if (IOSurfaceGetHeightFunc) return (int)IOSurfaceGetHeightFunc(surface);
    return 0;
}

CGImageRef AutoLuaCreateImageFromSurface(IOSurfaceRef surface) {
    if (!surface) return NULL;

    // 锁定 Surface 以读取
    if (IOSurfaceLockFunc) IOSurfaceLockFunc(surface, kIOSurfaceLockReadOnly, NULL);

    size_t width = IOSurfaceGetWidthFunc ? IOSurfaceGetWidthFunc(surface) : 0;
    size_t height = IOSurfaceGetHeightFunc ? IOSurfaceGetHeightFunc(surface) : 0;
    size_t bytesPerRow = IOSurfaceGetBytesPerRowFunc ? IOSurfaceGetBytesPerRowFunc(surface) : 0;
    uint32_t pixelFormat = IOSurfaceGetPixelFormatFunc ? IOSurfaceGetPixelFormatFunc(surface) : 0;
    void *baseAddress = IOSurfaceGetBaseAddressFunc ? IOSurfaceGetBaseAddressFunc(surface) : NULL;

    if (!baseAddress) {
        if (IOSurfaceUnlockFunc) IOSurfaceUnlockFunc(surface, kIOSurfaceLockReadOnly, NULL);
        return NULL;
    }

    // 创建 CGContext
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;

    // 如果像素格式是 BGRA8888，需要设置
    if (pixelFormat == 'BGRA') {
        bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    }

    CGContextRef context = CGBitmapContextCreate(
        baseAddress, width, height, 8, bytesPerRow,
        colorSpace, bitmapInfo
    );

    CGColorSpaceRelease(colorSpace);

    if (!context) {
        if (IOSurfaceUnlockFunc) IOSurfaceUnlockFunc(surface, kIOSurfaceLockReadOnly, NULL);
        return NULL;
    }

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (IOSurfaceUnlockFunc) IOSurfaceUnlockFunc(surface, kIOSurfaceLockReadOnly, NULL);

    return image;
}

NSData* AutoLuaGetPixelData(IOSurfaceRef surface, CGRect rect) {
    if (!surface) return nil;

    if (IOSurfaceLockFunc) IOSurfaceLockFunc(surface, kIOSurfaceLockReadOnly, NULL);

    size_t width = IOSurfaceGetWidthFunc ? IOSurfaceGetWidthFunc(surface) : 0;
    size_t bytesPerRow = IOSurfaceGetBytesPerRowFunc ? IOSurfaceGetBytesPerRowFunc(surface) : 0;
    void *base = IOSurfaceGetBaseAddressFunc ? IOSurfaceGetBaseAddressFunc(surface) : NULL;

    if (!base) {
        if (IOSurfaceUnlockFunc) IOSurfaceUnlockFunc(surface, kIOSurfaceLockReadOnly, NULL);
        return nil;
    }

    int x = MAX(0, (int)rect.origin.x);
    int y = MAX(0, (int)rect.origin.y);
    int w = MIN((int)width - x, (int)rect.size.width);
    int h = MIN((int)(IOSurfaceGetHeightFunc ? IOSurfaceGetHeightFunc(surface) : 0) - y, (int)rect.size.height);

    if (w <= 0 || h <= 0) {
        if (IOSurfaceUnlockFunc) IOSurfaceUnlockFunc(surface, kIOSurfaceLockReadOnly, NULL);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
    uint8_t *dst = (uint8_t *)data.mutableBytes;
    uint8_t *src = (uint8_t *)base;

    for (int row = 0; row < h; row++) {
        memcpy(dst + row * w * 4, src + (y + row) * bytesPerRow + x * 4, w * 4);
    }

    if (IOSurfaceUnlockFunc) IOSurfaceUnlockFunc(surface, kIOSurfaceLockReadOnly, NULL);
    return data;
}

// ============================================================
// 前台应用检测
// ============================================================

NSString* AutoLuaGetForegroundAppBundleID(void) {
    // 通过 SBApplicationController
    Class SBAppCtrl = NSClassFromString(@"SBApplicationController");
    if (SBAppCtrl) {
        id controller = [SBAppCtrl performSelector:NSSelectorFromString(@"sharedInstance")];
        if (controller) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id frontmost = [controller performSelector:NSSelectorFromString(@"frontmostApplication")];
            #pragma clang diagnostic pop
            if (frontmost) {
                return [frontmost valueForKey:@"bundleIdentifier"];
            }
        }
    }

    // 备用：FBSystemService
    Class FBService = NSClassFromString(@"FBSystemService");
    if (FBService) {
        id service = [FBService performSelector:NSSelectorFromString(@"sharedInstance")];
        if (service) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id app = [service performSelector:NSSelectorFromString(@"frontmostApplication")];
            #pragma clang diagnostic pop
            if (app) {
                return [app valueForKey:@"bundleIdentifier"];
            }
        }
    }

    return nil;
}

NSString* AutoLuaGetForegroundAppName(void) {
    NSString *bundleID = AutoLuaGetForegroundAppBundleID();
    if (!bundleID) return @"Unknown";

    // 尝试通过 LSApplicationProxy 获取本地化名称
    Class LSProxy = NSClassFromString(@"LSApplicationProxy");
    if (LSProxy) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id proxy = [LSProxy performSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")
                                 withObject:bundleID];
        #pragma clang diagnostic pop
        if (proxy) {
            NSString *name = [proxy valueForKey:@"localizedName"];
            if (name) return name;
        }
    }

    return bundleID;
}

NSDictionary* AutoLuaGetRunningApplications(void) {
    NSMutableDictionary *apps = [NSMutableDictionary dictionary];

    // 通过 LSApplicationWorkspace
    Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
    if (LSAppWorkspace) {
        id workspace = [LSAppWorkspace performSelector:NSSelectorFromString(@"defaultWorkspace")];
        if (workspace) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSArray *allApps = [workspace performSelector:NSSelectorFromString(@"allApplications")];
            #pragma clang diagnostic pop
            for (id app in allApps) {
                NSString *bundleID = [app valueForKey:@"applicationIdentifier"];
                NSString *name = [app valueForKey:@"localizedName"] ?: bundleID;
                if (bundleID) {
                    apps[bundleID] = name;
                }
            }
        }
    }

    return apps;
}

// ============================================================
// Lua 引擎实现（轻量封装）
// ============================================================

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

void* AutoLuaLuaNewState(void) {
    lua_State *L = luaL_newstate();
    if (L) {
        luaL_openlibs(L);
    }
    return L;
}

void AutoLuaLuaCloseState(void *L) {
    if (L) lua_close((lua_State*)L);
}

int AutoLuaLuaLoadString(void *L, const char *code) {
    return luaL_loadstring((lua_State*)L, code);
}

int AutoLuaLuaPCall(void *L, int nargs, int nresults) {
    return lua_pcall((lua_State*)L, nargs, nresults, 0);
}

const char* AutoLuaLuaToString(void *L, int index) {
    return lua_tostring((lua_State*)L, index);
}

void AutoLuaLuaPushString(void *L, const char *s) {
    lua_pushstring((lua_State*)L, s);
}

void AutoLuaLuaPushNumber(void *L, double n) {
    lua_pushnumber((lua_State*)L, n);
}

void AutoLuaLuaPushBoolean(void *L, int b) {
    lua_pushboolean((lua_State*)L, b);
}

void AutoLuaLuaPushCFunction(void *L, void *fn) {
    lua_pushcfunction((lua_State*)L, (lua_CFunction)fn);
}

void AutoLuaLuaSetGlobal(void *L, const char *name) {
    lua_setglobal((lua_State*)L, name);
}

void AutoLuaLuaGetGlobal(void *L, const char *name) {
    lua_getglobal((lua_State*)L, name);
}

// Lua engine implementation ends
