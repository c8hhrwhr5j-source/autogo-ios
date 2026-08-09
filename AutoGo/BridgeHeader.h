//
//  BridgeHeader.h
//  AutoGo
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
#define kAutoGoTouchPhaseBegan    1
#define kAutoGoTouchPhaseMoved    2
#define kAutoGoTouchPhaseEnded    3
#define kAutoGoTouchPhaseCancel   4

// 事件类型
#define kAutoGoEventTypeDigitizer 11

// 换能器类型
#define kAutoGoTransducerTypeHand 3

// 创建 IOHIDEvent 所需的函数（动态解析）
CFTypeRef AutoGoCreateDigitizerEvent(uint64_t timestamp,
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

void AutoGoHIDEventSetFloat(CFTypeRef event, int32_t field, float value);
void AutoGoHIDEventSetInteger(CFTypeRef event, int32_t field, int32_t value);
CFTypeRef AutoGoHIDEventSystemClientCreate(void);
int32_t AutoGoHIDEventSystemClientDispatchEvent(CFTypeRef client, CFTypeRef event);

// ============================================================
// IOSurface 屏幕捕获
// ============================================================
IOSurfaceRef AutoGoGetMainDisplaySurface(void);
CGImageRef AutoGoCreateImageFromSurface(IOSurfaceRef surface);
NSData* AutoGoGetPixelData(IOSurfaceRef surface, CGRect rect);

// ============================================================
// 前台应用检测
// ============================================================
NSString* AutoGoGetForegroundAppBundleID(void);
NSString* AutoGoGetForegroundAppName(void);
NSDictionary* AutoGoGetRunningApplications(void);

// ============================================================
// Lua 引擎
// ============================================================
void* AutoGoLuaNewState(void);
void  AutoGoLuaCloseState(void* L);
int   AutoGoLuaLoadString(void* L, const char* code);
int   AutoGoLuaPCall(void* L, int nargs, int nresults);
const char* AutoGoLuaToString(void* L, int index);
void  AutoGoLuaPushString(void* L, const char* s);
void  AutoGoLuaPushNumber(void* L, double n);
void  AutoGoLuaPushBoolean(void* L, int b);
void  AutoGoLuaPushCFunction(void* L, void* fn);
void  AutoGoLuaSetGlobal(void* L, const char* name);
void  AutoGoLuaGetGlobal(void* L, const char* name);

#endif /* BridgeHeader_h */
