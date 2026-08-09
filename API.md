# AutoGo iOS API 文档

> 脚本语言：JavaScript（JavaScriptCore 引擎，iOS 内置）
> 所有 API 通过全局对象 `autogo` 调用，例如 `autogo.tap(100, 200)`

---

## 目录
- [截图类](#截图类)
- [取色类](#取色类)
- [找色类](#找色类)
- [多点找色类](#多点找色类)
- [触摸类（单指）](#触摸类单指)
- [触摸类（多点）](#触摸类多点)
- [触摸类（手势）](#触摸类手势)
- [HUD 浮窗类](#hud-浮窗类)
- [OCR 文字识别](#ocr-文字识别)
- [工具类](#工具类)
- [TCP 远程控制协议](#tcp-远程控制协议)
- [文件存放路径](#文件存放路径)

---

## 截图类

### capture
获取最新缓存的屏幕截图帧（零延迟，直接返回流式捕获的缓存）。

```
autogo.capture()
```

**返回值** {boolean} 是否成功获取帧。

**说明** 必须先调用 `startStreaming()` 启动流式捕获（App 启动时自动开启 20fps）。

```js
if (autogo.capture()) {
    // 帧已就绪，可以进行取色/找色操作
}
```

---

### captureFresh
强制立即捕获一帧新画面（不读缓存），适合需要最新画面的场景。

```
autogo.captureFresh()
```

**返回值** {boolean} 是否成功。

```js
autogo.captureFresh() // 强制刷新一帧
var color = autogo.getPixelColor(100, 200)
```

---

### captureWait
等待并获取一帧画面，超时返回 false。

```
autogo.captureWait(timeout)
```

| 参数 | 类型 | 说明 |
|---|---|---|
| timeout | number | 超时秒数，默认 1.0 |

**返回值** {boolean}

```js
if (autogo.captureWait(2.0)) {
    // 2秒内等到了一帧
}
```

---

### getScreenSize
获取屏幕分辨率。

```
autogo.getScreenSize()
```

**返回值** {object} `{width: number, height: number}`

```js
var size = autogo.getScreenSize()
console.log("屏幕: " + size.width + "x" + size.height)
// 输出: 屏幕: 1179x2556
```

---

## 取色类

### getPixelColor
获取指定坐标点的 RGB 颜色值。

```
autogo.getPixelColor(x, y)
```

| 参数 | 类型 | 说明 |
|---|---|---|
| x | number | 坐标点 X 位置 |
| y | number | 坐标点 Y 位置 |

**返回值** {object | null} `{r: number, g: number, b: number}`，坐标超出屏幕返回 null

```js
var color = autogo.getPixelColor(100, 200)
if (color) {
    console.log("R=" + color.r + " G=" + color.g + " B=" + color.b)
}
```

---

## 找色类

### findColor
在整个屏幕中查找指定颜色，返回所有匹配点。

```
autogo.findColor(r, g, b, tolerance, maxResults)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| r | number | — | 目标红色分量 0~255 |
| g | number | — | 目标绿色分量 0~255 |
| b | number | — | 目标蓝色分量 0~255 |
| tolerance | number | 5 | 容差 0~255，越大越宽松 |
| maxResults | number | 500 | 最多返回多少个结果 |

**返回值** {array} 匹配点数组 `[{x, y}, ...]`

```js
// 找红色像素
var points = autogo.findColor(255, 0, 0, 10, 100)
if (points.length > 0) {
    autogo.tap(points[0].x, points[0].y)
}
```

---

### findColorInRegion
在指定区域内查找颜色。

```
autogo.findColorInRegion(r, g, b, tolerance, rx, ry, rw, rh, maxResults)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| r, g, b | number | — | 目标 RGB |
| tolerance | number | — | 容差 |
| rx | number | — | 区域左上角 X |
| ry | number | — | 区域左上角 Y |
| rw | number | — | 区域宽度 |
| rh | number | — | 区域高度 |
| maxResults | number | 500 | 最大结果数 |

**返回值** {array} `[{x, y}, ...]`

```js
// 在左上角 400x400 区域找蓝色
var pts = autogo.findColorInRegion(0, 0, 255, 5, 0, 0, 400, 400, 50)
```

---

## 多点找色类

### findMultiColors
多点相对坐标找色——先找首色，再验证相对位置的其他颜色点是否匹配。

> 与 AutoGo 的 `FindMultiColors` 协议兼容

```
autogo.findMultiColors(firstColorHex, pointsStr, tolerance, maxResults)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| firstColorHex | string | — | 首色 "RRGGBB"，如 "FF0000" |
| pointsStr | string | — | 相对坐标串 `"dx\|dy\|RRGGBB,..."` |
| tolerance | number | 5 | 容差 0~255 |
| maxResults | number | 100 | 最大结果数 |

**返回值** {array} 匹配的首色坐标 `[{x, y}, ...]`

```js
// 找红色按钮上的白色文字
// 首色: 红色 FF0000，相对点: (10,5)处白色FFFFFF, (-5,8)处白色FFFFFF
var results = autogo.findMultiColors(
    "FF0000",
    "10|5|FFFFFF,-5|8|FFFFFF",
    5,
    100
)
if (results.length > 0) {
    autogo.tap(results[0].x, results[0].y)
}
```

---

### findMultiColorsEx
多点找色（数组格式），传入结构化数据。

```
autogo.findMultiColorsEx(r, g, b, tolerance, relativePoints, maxResults)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| r, g, b | number | — | 首色 RGB |
| tolerance | number | — | 容差 |
| relativePoints | array | — | 相对坐标点数组 `[{dx, dy, r, g, b}, ...]` |
| maxResults | number | 100 | 最大结果数 |

**返回值** {array} `[{x, y}, ...]`

```js
var results = autogo.findMultiColorsEx(
    255, 0, 0,        // 首色红色
    5,                 // 容差
    [                  // 相对坐标点
        {dx: 10, dy: 5,  r: 255, g: 255, b: 255},  // 相对(10,5)处白色
        {dx: -5, dy: 8, r: 255, g: 255, b: 255}    // 相对(-5,8)处白色
    ],
    100
)
```

---

## 触摸类（单指）

### tap
基础点击（按下 → 等待 → 抬起）。

```
autogo.tap(x, y, delayMs)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| x | number | — | 点击 X 坐标 |
| y | number | — | 点击 Y 坐标 |
| delayMs | number | 30 | 按下持续时间（毫秒） |

```js
autogo.tap(500, 300)           // 快速点击
autogo.tap(500, 300, 100)      // 按下100ms后抬起
```

---

### longPress
长按（按下 → 保持 → 抬起）。

```
autogo.longPress(x, y, durationMs)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| x | number | — | 长按 X 坐标 |
| y | number | — | 长按 Y 坐标 |
| durationMs | number | 800 | 保持时间（毫秒） |

```js
autogo.longPress(500, 300)       // 长按 800ms
autogo.longPress(500, 300, 1500) // 长按 1.5 秒
```

---

### swipe
滑动（从起点匀速移动至终点）。

```
autogo.swipe(fromX, fromY, toX, toY, durationMs, steps)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| fromX | number | — | 起点 X |
| fromY | number | — | 起点 Y |
| toX | number | — | 终点 X |
| toY | number | — | 终点 Y |
| durationMs | number | 300 | 滑动耗时（毫秒） |
| steps | number | 30 | 中间移动步数 |

```js
autogo.swipe(100, 800, 100, 200)        // 向上滑 300ms
autogo.swipe(300, 500, 700, 500, 500)   // 向右滑 500ms
autogo.swipe(100, 500, 100, 100, 200, 20) // 快速上滑 200ms/20步
```

---

## 触摸类（多点）

### touchDown
手指按下（不自动抬起，需配合 touchUp 使用）。

```
autogo.touchDown(x, y, fingerIndex)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| x | number | — | 按下 X 坐标 |
| y | number | — | 按下 Y 坐标 |
| fingerIndex | number | 0 | 手指编号 0~9 |

```js
// 两指同时按下
autogo.touchDown(200, 300, 0)  // 食指
autogo.touchDown(400, 300, 1)  // 中指
```

---

### touchMove
手指移动（在 touchDown 后调用）。

```
autogo.touchMove(x, y, fingerIndex)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| x | number | — | 移动目标 X |
| y | number | — | 移动目标 Y |
| fingerIndex | number | 0 | 手指编号 0~9 |

---

### touchUp
手指抬起。

```
autogo.touchUp(x, y, fingerIndex)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| x | number | — | 抬起位置 X |
| y | number | — | 抬起位置 Y |
| fingerIndex | number | 0 | 手指编号 0~9 |

```js
// 完整多点触控流程
autogo.touchDown(200, 300, 0)    // 食指按下
autogo.touchDown(400, 300, 1)    // 中指按下
autogo.sleep(500)                 // 保持 500ms
autogo.touchMove(250, 300, 0)    // 食指右移
autogo.touchMove(450, 300, 1)    // 中指右移
autogo.touchUp(250, 300, 0)      // 食指抬起
autogo.touchUp(450, 300, 1)      // 中指抬起
```

---

### multiTap
多点同时点击（简化的多点 touchDown → touchUp）。

```
autogo.multiTap(points, delayMs)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| points | array | — | 坐标数组 `[{x, y}, {x, y}, ...]` |
| delayMs | number | 30 | 按下持续时间（毫秒） |

```js
// 双指同时点击
autogo.multiTap([
    {x: 200, y: 300},
    {x: 400, y: 300}
], 30)
```

---

## 触摸类（手势）

### pinch
双指缩放手势。

```
autogo.pinch(centerX, centerY, fromDistance, toDistance, durationMs, steps)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| centerX | number | — | 缩放中心 X 坐标 |
| centerY | number | — | 缩放中心 Y 坐标 |
| fromDistance | number | — | 起始两指间距（像素） |
| toDistance | number | — | 目标两指间距（像素） |
| durationMs | number | 300 | 手势耗时（毫秒） |
| steps | number | 20 | 中间步数 |

```js
// 放大：两指从 100 像素间距扩张到 200 像素
autogo.pinch(500, 400, 100, 200, 300, 20)

// 缩小：两指从 200 像素间距收缩到 50 像素
autogo.pinch(500, 400, 200, 50, 500, 30)
```

---

## HUD 浮窗类

### showHud
显示悬浮调试文本窗口。

```
autogo.showHud(text, x, y)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| text | string | — | 显示的文本 |
| x | number | 屏幕中间 | 窗口位置 X（可选） |
| y | number | 60 | 窗口位置 Y（可选） |

```js
autogo.showHud("执行中...")              // 屏幕顶部居中
autogo.showHud("状态: OK", 100, 300)     // 指定位置
```

---

### hideHud
隐藏悬浮窗口。

```
autogo.hideHud()
```

---

### updateHud
更新悬浮窗口文本（不改变位置）。

```
autogo.updateHud(text)
```

```js
autogo.showHud("正在处理...")
// ... 处理中 ...
autogo.updateHud("处理完成!")
autogo.sleep(1000)
autogo.hideHud()
```

---

### toast
显示自动消失的提示。

```
autogo.toast(text, duration)
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| text | string | — | 提示内容 |
| duration | number | 1.5 | 显示时长（秒） |

```js
autogo.toast("操作成功!")
autogo.toast("即将跳转", 2.0)
```

---

## OCR 文字识别

### ocr
对当前屏幕截图进行 OCR 文字识别。

```
autogo.ocr()
```

**返回值** {string} 识别出的文字，每行识别结果用换行分隔。

```js
var text = autogo.ocr()
console.log("识别结果: " + text)

// 判断是否包含特定文字
if (text.indexOf("微信") >= 0) {
    autogo.tap(100, 200)
}
```

---

## 工具类

### sleep
暂停脚本执行。

```
autogo.sleep(ms)
```

| 参数 | 类型 | 说明 |
|---|---|---|
| ms | number | 暂停毫秒数 |

```js
autogo.tap(500, 300)
autogo.sleep(1000)   // 等待 1 秒
autogo.tap(500, 500)
```

---

## TCP 远程控制协议

通过 TCP 连接到 `设备IP:9999` 发送命令：

| 命令前缀 | 说明 | 示例 |
|---|---|---|
| `lua:<script>` | 执行 JS 脚本 | `lua:autogo.tap(100,200)` |
| `js:<script>` | 同 lua: | `js:autogo.swipe(0,500,0,200)` |
| `ocr` | 执行 OCR 识别 | `ocr` |
| `capture` | 截图返回 Base64 JPEG | `capture` |
| `info` | 返回设备信息 | `info` |
| `help` | 显示帮助 | `help` |
| `exit` | 断开连接 | `exit` |

**Python 远程控制示例：**

```python
import socket

def autogo(cmd):
    s = socket.socket()
    s.settimeout(5)
    s.connect(("设备IP", 9999))
    s.send((cmd + "\n").encode())
    resp = s.recv(65536).decode()
    s.close()
    return resp

# 获取设备信息
print(autogo("info"))

# 截图
autogo("lua:autogo.getScreenSize()")

# 点击坐标
autogo("lua:autogo.tap(500, 300)")

# 找色并点击
autogo("""
    var pts = autogo.findColor(255, 0, 0, 5, 1);
    if (pts.length > 0) autogo.tap(pts[0].x, pts[0].y);
""")

# OCR 识别
print(autogo("ocr"))
```

---

## 文件存放路径

| 用途 | 路径 |
|---|---|
| **Lua/JS 脚本** | `文件 App → 我的 iPhone → AutoGo → Scripts/` |
| **日志文件** | `文件 App → 我的 iPhone → AutoGo → Logs/` |

> 已开启 iTunes 文件共享，可通过电脑直接拖入脚本文件。

---

## 完整脚本示例

### 示例 1：自动签到

```js
// 等待 2 秒让界面加载
autogo.sleep(2000)

// 找红色按钮并点击
var buttons = autogo.findColor(255, 0, 0, 10, 1)
if (buttons.length > 0) {
    autogo.tap(buttons[0].x, buttons[0].y)
    autogo.toast("签到成功!")
} else {
    autogo.toast("未找到签到按钮")
}
```

### 示例 2：向上滑动浏览

```js
var size = autogo.getScreenSize()
var midX = size.width / 2

for (var i = 0; i < 5; i++) {
    autogo.swipe(midX, size.height * 0.8, midX, size.height * 0.3, 500, 30)
    autogo.sleep(1000)
}
autogo.toast("浏览完成")
```

### 示例 3：多点找色判断状态

```js
// 找"确认"按钮：红色背景(255,0,0)上白色文字(255,255,255)
var results = autogo.findMultiColors(
    "FF0000",              // 首色：红色
    "20|5|FFFFFF,40|5|FFFFFF",  // 相对位置白色文字
    5, 1
)
if (results.length > 0) {
    autogo.tap(results[0].x, results[0].y)
    autogo.toast("已点击确认")
}
```

### 示例 4：双指缩放地图

```js
var size = autogo.getScreenSize()
// 在地图中心双指放大
autogo.pinch(size.width / 2, size.height / 2, 80, 200, 500, 25)
autogo.sleep(500)
// 缩回
autogo.pinch(size.width / 2, size.height / 2, 200, 80, 500, 25)
```

### 示例 5：HUD 状态显示 + OCR

```js
autogo.showHud("AutoGo 运行中")

for (var i = 0; i < 10; i++) {
    var text = autogo.ocr()
    autogo.updateHud("第" + (i+1) + "次识别:\n" + text.substring(0, 100))
    autogo.sleep(3000)
}

autogo.hideHud()
autogo.toast("扫描完成")
```
