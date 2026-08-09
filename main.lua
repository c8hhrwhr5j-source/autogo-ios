function main()
    print("脚本运行开始")
    local width, height = autolua.getScreenSize()
    print("屏幕: " .. width .. "x" .. height)
    while true do
        autolua.sleep(500)

        -- 先获取各坐标颜色，再比较
        local c1 = autolua.findColor(951, 2144)
        local c2 = autolua.findColor(1106, 842)
        local c3 = autolua.findColor(410, 1103)

        if c1 == 0x8E8E93 then
            print("找到设置按钮")
            autolua.tap(951, 2144)       -- 点击设置
            autolua.sleep(1000)
        elseif c2 == 0x632C08 then
            print("找到横屏公告确定按钮")
            autolua.tap(1106, 842)       -- 点击确定
            autolua.sleep(1000)
        elseif c3 == 0x845529 then
            print("找到坚屏公告确定按钮")
            autolua.tap(410, 1103)       -- 点击确定
            autolua.sleep(1000)
        else
            print("未找到任何按钮，当前坐标实际颜色：")
            if c1 then
                print(string.format("  (951,2144) 实际=0x%06X 期望=0x8E8E93", c1))
            else
                print("  (951,2144) 取色失败")
            end
            if c2 then
                print(string.format("  (1106,842) 实际=0x%06X 期望=0x632C08", c2))
            else
                print("  (1106,842) 取色失败")
            end
            if c3 then
                print(string.format("  (410,1103) 实际=0x%06X 期望=0x845529", c3))
            else
                print("  (410,1103) 取色失败")
            end
        end
    end   
end

main()