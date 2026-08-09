function main()
    print("脚本运行开始")
    local width, height = autolua.getScreenSize()
    print("屏幕: " .. width .. "x" .. height)
    while true do
        sleep(500)
        if autolua.findColor(951, 2144) == 0x8E8E93 then
            print("找到设置按钮")
            autolua.tap(951, 2144)       -- 点击设置
            sleep(1000)
        end
        if autolua.findColor(1106, 842) == 0x632C08 then
            print("找到横屏公告确定按钮")
            autolua.tap(1106, 842)       -- 点击确定
            sleep(1000)
        end
        if autolua.findColor(410, 1103) == 0x845529 then
            print("找到坚屏公告确定按钮")
            autolua.tap(410, 1103)       -- 点击确定
            sleep(1000)
        end
    end   
end

main()