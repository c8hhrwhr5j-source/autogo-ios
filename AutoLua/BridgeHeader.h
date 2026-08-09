//
//  BridgeHeader.h
//  AutoLua
//
//  ObjC 桥接头文件 — 暴露 C/ObjC API 给 Swift
//

#ifndef BridgeHeader_h
#define BridgeHeader_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ============================================================
// IOKit HID 事件（点击/滑动）
// ============================================================

// 触摸相位常量
#define kAutoLuaTouchPhaseBegan    1
#define kAutoLuaTouchPhaseMoved    2
#define kAutoLuaTouchPhaseEnded    3
#define kAutoLuaTouchPhaseCancel   4

// 事件类型
#define kAutoLuaEventTypeDigitizer 11

// 换能器类型
#define kAutoLuaTransducerTypeHand 3

// 创建 IOHIDEvent 所需的函数（动态解析）
CFTypeRef AutoLuaCreateDigitizerEvent(uint64_t timestamp,
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
                                      int32_t majorRadius);

void AutoLuaHIDEventSetFloat(CFTypeRef event, int32_t field, float value);
void AutoLuaHIDEventSetInteger(CFTypeRef event, int32_t field, int32_t value);
CFTypeRef AutoLuaHIDEventSystemClientCreate(void);
int32_t AutoLuaHIDEventSystemClientDispatchEvent(CFTypeRef client, CFTypeRef event);

// ============================================================
// IOSurface 屏幕捕获
// ============================================================
IOSurfaceRef AutoLuaGetMainDisplaySurface(void);
int AutoLuaSurfaceGetWidth(IOSurfaceRef surface);
int AutoLuaSurfaceGetHeight(IOSurfaceRef surface);
CGImageRef AutoLuaCreateImageFromSurface(IOSurfaceRef surface);
NSData* AutoLuaGetPixelData(IOSurfaceRef surface, CGRect rect);

// ============================================================
// 前台应用检测
// ============================================================
NSString* AutoLuaGetForegroundAppBundleID(void);
NSString* AutoLuaGetForegroundAppName(void);
NSDictionary* AutoLuaGetRunningApplications(void);

// ============================================================
// Lua 引擎
// ============================================================

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "LuaShim.h"

void* AutoLuaLuaNewState(void);
void  AutoLuaLuaCloseState(void* L);
int   AutoLuaLuaLoadString(void* L, const char* code);
int   AutoLuaLuaPCall(void* L, int nargs, int nresults);
const char* AutoLuaLuaToString(void* L, int index);

#endif /* BridgeHeader_h */
