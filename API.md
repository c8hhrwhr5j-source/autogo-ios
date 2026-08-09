# AutoLua iOS — Lua API 文档

> 基于 Lua 5.4 的 iOS 自动化脚本引擎  
> 所有 API 通过 `autolua.*` 全局表调用

---

## 环境要求

| 项目 | 说明 |
|---|---|
| iOS 版本 | >= 14.0 |
| 脚本语言 | **Lua 5.4** |
| 脚本存放 | `/var/mobile/AutoLua/Scripts/` |
| 日志存放 | `/var/mobile/AutoLua/log/` |
| 文件扩展名 | `.lua` |

---

## API 速查表

| 分类 | API | 说明 |
|---|---|---|
| 截图 | `capture` | 截取全屏 |
| 截图 | `captureFresh` | 截取最新帧 |
| 截图 | `captureWait` | 等待新帧后截图 |
| 截图 | `getScreenSize` | 获取屏幕分辨率 |
| 取色 | `getPixelColor` | 获取指定坐标颜色 |
| 取色 | `findColor` | 获取指定坐标像素颜色值 |
| 找色 | `findColorInRegion` | 在区域内查找颜色 |
| 找色 | `findMultiColors` | 多点找色（字符串方式） |
| 找色 | `findMultiColorsEx` | 多点找色（表格方式） |
| 触摸 | `tap` | 点击 |
| 触摸 | `longPress` | 长按 |
| 触摸 | `swipe` | 滑动 |
| 触摸 | `touchDown` | 按下（多点） |
| 触摸 | `touchUp` | 抬起（多点） |
| 触摸 | `touchMove` | 移动（多点） |
| 触摸 | `multiTap` | 多点点击 |
| 手势 | `pinch` | 双指缩放 |
| HUD | `showHud` | 显示浮窗 |
| HUD | `hideHud` | 隐藏浮窗 |
| HUD | `updateHud` | 更新浮窗文字 |
| HUD | `toast` | 弹出提示 |
| 工具 | `sleep` | 延迟等待 |
| 工具 | `debug` | 写入调试日志 |

---

## 截图

### capture()
截取当前全屏截图，保存到内存缓存。

**参数：** 无

**返回值：** `boolean` — `true` 成功, `false` 失败

```lua
local ok = autolua.capture()
if ok then
    print("截图成功")
end
```

---

### captureFresh()
获取最新一帧（强制刷新），保存到内存缓存。

**参数：** 无

**返回值：** `boolean`

```lua
autolua.captureFresh()
```

---

### captureWait(timeout)
等待屏幕产生新帧后截图，超时返回 `false`。

**参数：**

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| timeout | number | 超时时间（秒） | 1.0 |

**返回值：** `boolean`

```lua
if autolua.captureWait(2.0) then
    print("新帧已到达")
else
    print("超时")
end
```

---

### getScreenSize()
获取屏幕逻辑分辨率。

**参数：** 无

**返回值：** `width, height` — 两个整数，分别表示屏幕宽度和高度

```lua
local width, height = autolua.getScreenSize()
print("屏幕: " .. width .. "x" .. height)
```

---

## 取色

### getPixelColor(x, y)
获取屏幕上指定坐标点的 RGB 颜色值。

**参数：**

| 参数 | 类型 | 说明 |
|---|---|---|
| x | integer | 横坐标 |
| y | integer | 纵坐标 |

**返回值：** `r, g, b` — 三个整数 (0-255)，分别为红、绿、蓝分量；坐标无效时返回 `nil, nil, nil`

```lua
local r, g, b = autolua.getPixelColor(500, 300)
if r then
    print(string.format("颜色: R=%d G=%d B=%d", r, g, b))
end
```

---

## 找色

### findColor(x, y)
获取指定坐标像素的十六进制 RGB 颜色值。

**参数：**

| 参数 | 类型 | 说明 |
|---|---|---|
| x | integer | 横坐标 |
| y | integer | 纵坐标 |

**返回值：** `integer` — 十六进制颜色值（如 `0xFF0000` 表示红色）；坐标无效时返回 `nil`

```lua
local c = autolua.findColor(100, 100)
if c then
    print(string.format("颜色: 0x%06X", c))
end

-- 判断是否为红色
if c == 0xFF0000 then
    autolua.toast("该位置是红色")
end
```

---

### findColorInRegion(r, g, b, tolerance, x, y, w, h, maxResults)
在指定矩形区域内查找颜色。

**参数：**

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| r, g, b | integer | 目标颜色 | — |
| tolerance | integer | 容差 | — |
| x | integer | 区域左上角横坐标 | — |
| y | integer | 区域左上角纵坐标 | — |
| w | integer | 区域宽度 | — |
| h | integer | 区域高度 | — |
| maxResults | integer | 最大返回数量 | 500 |

```lua
-- 在左上区域 (0,0,600,400) 找蓝白
local pts = autolua.findColorInRegion(66, 133, 244, 10, 0, 0, 600, 400, 50)
if #pts > 0 then
    autolua.tap(pts[1].x, pts[1].y)
end
```

---

### findMultiColors(firstColorHex, pointsStr, tolerance, maxResults)
按相对位置多点找色（字符串格式）。

**参数：**

| 参数 | 类型 | 说明 |
|---|---|---|
| firstColorHex | string | 首色 RGB 十六进制，如 `"FF0000"` |
| pointsStr | string | 后续点，格式 `"dx,dy,RRGGBB|dx,dy,RRGGBB|..."` |
| tolerance | integer | 容差，默认 5 |
| maxResults | integer | 最大返回数量，默认 100 |

```lua
-- 找"确定"按钮：红色 → 右边30px同色
local pts = autolua.findMultiColors("FF0000", "30,0,FF0000", 5, 10)
```

---

### findMultiColorsEx(r, g, b, tolerance, points, maxResults)
按相对位置多点找色（表格格式）。

**参数：**

| 参数 | 类型 | 说明 |
|---|---|---|
| r, g, b | integer | 首色 RGB | 
| tolerance | integer | 容差 |
| points | table | 相对点数组 `{{dx, dy, r, g, b}, ...}` |
| maxResults | integer | 最大返回数量，默认 100 |

```lua
-- 找"签到"按钮：蓝底 + 白字
local refs = {
    {dx = 0,  dy = 0,  r = 66, g = 133, b = 244},
    {dx = 10, dy = 5,  r = 255, g = 255, b = 255},
}
local pts = autolua.findMultiColorsEx(66, 133, 244, 5, refs, 10)

if #pts > 0 then
    autolua.tap(pts[1].x, pts[1].y)
end
```

---

## 触摸（单指）

### tap(x, y, delayMs)
点击屏幕指定坐标。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| x | number | 横坐标 | — |
| y | number | 纵坐标 | — |
| delayMs | integer | 按下持续时间（毫秒） | 30 |

```lua
autolua.tap(300, 500)       -- 快速点击
autolua.tap(300, 500, 100)  -- 稍长点击
```

---

### longPress(x, y, durationMs)
长按指定坐标。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| x | number | 横坐标 | — |
| y | number | 纵坐标 | — |
| durationMs | integer | 按压时长（毫秒） | 800 |

```lua
autolua.longPress(300, 500, 1500)  -- 长按 1.5 秒
```

---

### swipe(fromX, fromY, toX, toY, durationMs, steps)
从起点滑动到终点。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| fromX, fromY | number | 起点坐标 | — |
| toX, toY | number | 终点坐标 | — |
| durationMs | integer | 滑动时长（毫秒） | 300 |
| steps | integer | 分步数 | 30 |

```lua
-- 向上滑动（浏览）
autolua.swipe(200, 600, 200, 200, 300)

-- 慢速滑动
autolua.swipe(100, 500, 300, 500, 800, 50)
```

---

## 触摸（多点）

### touchDown(x, y, fingerIndex)
手指按下。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| x | number | 横坐标 | — |
| y | number | 纵坐标 | — |
| fingerIndex | integer | 手指编号 | 0 |

```lua
autolua.touchDown(200, 300, 0)  -- 手指 0 按下
```

---

### touchUp(x, y, fingerIndex)
手指抬起。

```lua
autolua.touchUp(300, 300, 0)    -- 手指 0 抬起
```

---

### touchMove(x, y, fingerIndex)
手指移动。

```lua
autolua.touchMove(400, 300, 0)  -- 手指 0 移动到新位置
```

---

### multiTap(points, delayMs)
同时点击多个坐标。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| points | table | `{{x, y}, ...}` 坐标数组 | — |
| delayMs | integer | 按下时长（毫秒） | 30 |

```lua
-- 同时点击两个位置
local pts = {
    {x = 200, y = 300},
    {x = 400, y = 300},
}
autolua.multiTap(pts, 50)
```

---

## 手势

### pinch(centerX, centerY, fromDistance, toDistance, durationMs, steps)
双指缩放。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| centerX, centerY | number | 缩放中心 | — |
| fromDistance | number | 起始双指距离 | — |
| toDistance | number | 结束双指距离 | — |
| durationMs | integer | 动画时长（毫秒） | 300 |
| steps | integer | 分步数 | 20 |

```lua
-- 放大
autolua.pinch(200, 300, 50, 150, 500)

-- 缩小
autolua.pinch(200, 300, 150, 50, 500)
```

---

## HUD 浮窗

### showHud(text, x, y)
显示半透明浮窗。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| text | string | 显示文字 | — |
| x | number | 横坐标 | 屏幕水平居中 |
| y | number | 纵坐标 | 屏幕垂直居中 |

```lua
autolua.showHud("执行中...")
autolua.showHud("点这里", 200, 400)
```

---

### hideHud()
隐藏浮窗。

```lua
autolua.hideHud()
```

---

### updateHud(text)
更新浮窗文字内容。

```lua
autolua.updateHud("进度: 50%")
```

---

### toast(text, duration)
弹出短暂提示（底部 Toast）。

| 参数 | 类型 | 说明 | 默认值 |
|---|---|---|---|
| text | string | 提示文字 | — |
| duration | number | 显示时长（秒） | 1.5 |

```lua
autolua.toast("操作完成")
autolua.toast("已保存", 2.0)
```

---

## 工具

### sleep(ms)
暂停执行指定毫秒。

| 参数 | 类型 | 说明 |
|---|---|---|
| ms | integer | 暂停时长（毫秒） |

```lua
autolua.sleep(1000)   -- 等待 1 秒
autolua.sleep(500)    -- 等待 0.5 秒
```

### debug(msg)
写入一条调试日志。日志会保存到 `/var/mobile/AutoLua/log/` 目录，并显示在手机的日志页面中。

**注意：** 脚本中的 `print()` 也会自动重定向写入日志，效果等同于 `autolua.debug()`。

| 参数 | 类型 | 说明 |
|---|---|---|
| msg | string | 日志文本 |

```lua
autolua.debug("脚本运行开始")

-- print() 也会自动写入日志，无需修改现有代码
print("当前颜色: " .. autolua.findColor(100, 200))
print("执行完毕")
```

---

## 完整脚本示例

### 示例 1：自动签到

```lua
-- auto_signin.lua
autolua.capture()
autolua.sleep(500)

-- 找签到按钮（假设是蓝色）
local pts = autolua.findColorInRegion(0, 122, 255, 10, 0, 500, 400, 300, 10)

if #pts > 0 then
    autolua.tap(pts[1].x, pts[1].y)
    print("签到成功")
    autolua.toast("签到完成")
else
    print("未找到签到按钮")
end
```

### 示例 2：滑动浏览

```lua
-- scroll_browse.lua
for i = 1, 10 do
    autolua.swipe(200, 600, 200, 200, 400)
    autolua.sleep(1500)
    print("第 " .. i .. " 次滑动")
end
print("浏览完成")
```

### 示例 3：多点找色 + 点击

```lua
-- find_end_click.lua
autolua.capture()

local refs = {
    {dx = 0,  dy = 0,  r = 255, g = 255, b = 255},  -- 白字
    {dx = 10, dy = 0,  r = 255, g = 255, b = 255},
    {dx = 0,  dy = 5,  r = 255, g = 255, b = 255},
}

local pts = autolua.findMultiColorsEx(255, 255, 255, 3, refs, 1)

if #pts > 0 then
    autolua.tap(pts[1].x + 5, pts[1].y)
    autolua.toast("已点击")
else
    autolua.toast("未找到目标")
end
```

### 示例 4：双指缩放

```lua
-- pinch_zoom.lua
autolua.pinch(200, 300, 50, 150, 800)   -- 放大
autolua.sleep(1000)
autolua.pinch(200, 300, 150, 50, 800)   -- 缩小
print("缩放完成")
```

---

## TCP 远程控制

AutoLua 在端口 **9999** 上监听 TCP 连接，可直接从电脑远程执行脚本。

### 协议命令

| 命令 | 说明 |
|---|---|
| `lua:<code>` | 远程执行 Lua 代码 |
| `capture` | 截图并返回 JPEG Base64 |
| `info` | 返回设备信息 |
| `exit` | 断开连接 |

### Python 远程示例

```python
import socket

s = socket.socket()
s.connect(("192.168.1.100", 9999))

# 执行 Lua 脚本
s.send(b"lua:autolua.capture(); autolua.tap(300, 500)\n")
print(s.recv(4096).decode())

# 查看设备信息
s.send(b"info\n")
print(s.recv(4096).decode())

s.close()
```

---

## 目录结构

```
/var/mobile/AutoLua/
├── Scripts/          ← .lua 脚本文件
└── log/              ← 日志文件（autolua_YYYYMMDD.log）
```
