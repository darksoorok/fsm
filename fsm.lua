script_name('Fast Send Money');
script_author("S&D Scripts");
script_description('Send money when player online.')
script_version('1.0')
script_version_number(1)

--## loading modules ##--
local lib = {
    keys = require 'vkeys',
    events = require 'lib.samp.events', 
    ini = require 'inicfg',
    mem = require 'memory',
    encoding = require 'encoding'
}

--## script settings ##-- 
cfg = lib.ini.load(nil, 'FSM')
if not cfg then
    local data = {
        main = {
            onstart = false, -- run checker thread with script load
            pincode = "", -- pincode
            msg = true, -- choise of the place of sending the message
            screen = true, -- after successful transfer take a screenshot
        },
        checker = {
            interval = 3, -- check every 3 seconds
            after_action = 60, -- delay 10 seconds after last transfer
        }
    }
    if lib.ini.save(data, 'FSM') then
        cfg = lib.ini.load(nil, 'FSM')
    end
end

lib.encoding.default = 'CP1251'
u8 = lib.encoding.UTF8
local imgui = require 'imgui'
local window = imgui.ImBool(false)
local activate_window = imgui.ImBool(false)
local sw, sh = getScreenResolution()
local new_name = imgui.ImBuffer('', 256)
local new_sum = imgui.ImBuffer('', 256)
local pincode = imgui.ImBuffer(tostring(cfg.main.pincode), 256)
local save = false
local one_step = imgui.ImBool(false)
local msg = imgui.ImBool(cfg.main.msg)
local scr = imgui.ImBool(cfg.main.screen)
local onstart = imgui.ImBool(cfg.main.onstart)
local delay = imgui.ImInt(cfg.checker.interval)
local after = imgui.ImInt(cfg.checker.after_action)
local select = nil


--## functions of interaction with file ##-
local file = {
    path = getWorkingDirectory() .. '\\config\\FSM.list'
}
file.read = function() -- get text from file
    if not doesFileExist(file.path) then return 'file empty' end
    local f = io.open(file.path, 'r+'); 
    local text = f:read('a*'); f:close(); 
    return (#text > 5 and text or 'file empty')
end
file.write = function(text) -- rewrite text in file 
    local f = io.open(file.path, 'w+'); 
    f:write(text); f:close();
end
file.newline = function(line) -- add new line to file
    local f = io.open(file.path, 'a+');
    f:write(line); f:close();
end

--## players online checker ##--
local checker = {}
checker.th = lua_thread.create_suspended(function()
    checker.state = true;
    checker.list = checker.getplayers()
    while true do 
        if checker.state and checker.list and checker.list ~= 'file empty' then
            for k, v in pairs(checker.list) do
                local id = sampGetPlayerIdByNickname(k)
                if id and sampGetPlayerScore(id) > 0 then
                    sampSendClickTextdraw(65535) 
                    _G.fsm = {stage = 1, name = k, sum = v}
                    sampSendChat('/phone')
                    while not _G.fsm.next do
                        wait(0)
                        if _G.fsm.next then break end
                    end
                    _G.fsm = {stage=0,name=nil,sum=nil}
                    wait(150);
                    if cfg.main.screen then
                        sampSendChat('/time')
                        wait(600)
                        lib.mem.setuint8(sampGetBase() + 0x119CBC, 1)
                    end
                    checker.list[k] = nil
                    checker.save()
                    wait(3000)
                    sampSendClickTextdraw(65535)
                    wait(cfg.checker.after_action * 1000)
                end
                wait(cfg.checker.interval * 1000)
            end
        else 
            checker.th:terminate()
            wait(0)
        end
    end 
end)
checker.getplayers = function()
    local players = file.read()
    if players ~= 'file empty' then 
        local array = {}
        for name, sum in players:gmatch('(%w+_%w+)\\(%d+)') do 
            if array[name] and checker.state then
                chatMessage('[WARNING] Никнейм ' .. name .. ' в списке дублируется! Чекер останавливается.', -1)
                checker.state = false; checker.th:terminate()
            end
            array[name] = sum
        end
        return array
    else
        if checker.state then chatMessage('Файл пуст. Чекер остановлен.') end
        checker.state = false;
        checker.th:terminate();
        return players
    end
end
checker.save = function()
    local text = ''
    for k, v in pairs(checker.list) do 
        text = string.format('%s%s\\%d', text, k, v)
    end
    file.write(text)
end

function lib.events.onServerMessage(clr, msg)
    -- if msg:find('Переводить деньги можно раз в минуту') and 
end

function lib.events.onShowDialog(id, style, name, btn1, btn2, text)
    local stage = (_G.fsm and _G.fsm.stage or -1)
    if id == 1000 and stage == 1 then
        _G.fsm.stage = 2
        local line = 0
        local linephone = false
        for v in string.gmatch(text, '[^\n]+') do
            if (v:find('Samsung Galaxy S10') or v:find('IPHONE X')) and not linephone then
                namephone = v:match('([%w%s%d]+)\t.+'); sampSendDialogResponse(1000, 1, line - 1, 0); linephone = true; break
            end
            line = line + 1
        end
        if not linephone then  
            chatMessage('Для работы скрипта нужен телефон Samsung Galaxy S10 или IPHONE X.') 
            checker.state = false; checker.th:terminate(); 
        end
        return false
    end
    if id == 991 then 
        sampSendDialogResponse(991, 1, 0, cfg.main.pincode)
        return false
    end
    if id == 0 and text:find('PIN%-код принят') then
        sampSendDialogResponse(0, 1, 0, 0)
        if stage == 2 then
            _G.fsm.stage = 1
            sampSendClickTextdraw(65535)
            sampSendChat('/phone')
        end
        return false
    end
    if id == 6565 and stage == 3 or stage == 2 then 
        _G.fsm.stage = 4
        sampSendDialogResponse(6565, 1, 2, 0); id_textdraw = nil
        return false
    end
    if id == 37 and stage == 4 then 
        _G.fsm.stage = 5
        sampSendDialogResponse(37, 1, 0, _G.fsm.name)
        return false
    end
    if id == 41 and stage == 5 then
        sampSendDialogResponse(41, 1, 0, _G.fsm.sum)
        _G.fsm.next = true
        return false
    end
end

function lib.events.onShowTextDraw(id, data)
    local t = { 
        ["Samsung Galaxy S10"] = {x = "72.334", y = "259.429"},
        ["IPHONE X"] = {x = "72.334", y = "261.029"}    
    }
    local stage = (_G.fsm and _G.fsm.stage or -1)
    if stage == 2 then
        if string.format('%0.3f', tostring(data.position.x)) == t[namephone].x and string.format('%0.3f', tostring(data.position.y)) == t[namephone].y then
            id_textdraw = id; sampSendClickTextdraw(id_textdraw)
        end
    end
end

function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(120) end
    if cfg.main.onstart then checker.th:run() end
    getListSerialNumber()
    sampRegisterChatCommand('fsm', function()
        if not activate then 
            activate_window.v = true 
        else
            window.v = not window.v; imgui.Process = window.v
        end
    end)
    while true do wait(0) imgui.Process = window.v or activate_window.v; imgui.LockPlayer = window.v or activate_window.v end
end

function imgui.OnDrawFrame()
    if activate_window.v then
        local mySerialNumber = tostring(getSerialNumber())
        imgui.CenterText = function(text)
            imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(u8(text)).x)/2)
            imgui.Text(u8(text))
        end
        imgui.ShowCursor = activate_window.v
        imgui.SetNextWindowSize(imgui.ImVec2(330,250), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2((sw/2),(sh/2)), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5), imgui.WindowFlags.AlwaysAutoResize)
        imgui.Begin('Fast Send Money', activate_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
        
        imgui.CenterText('Ваш компьютер не имеет активации продукта!')
        imgui.NewLine()
        imgui.TextWrapped(u8'  Если вы официально приобретали данный скрипт, от вас требуется ещё одно маленькое действие.')
        imgui.TextWrapped(u8'  Вам необходимо нажать на кнопку ниже и сообщить код, который будет скопирован в буфер обмена (вставить в строку сообщения: CTRL+V).')
        imgui.NewLine()
        imgui.BeginChild('serialnumber', imgui.ImVec2(0, 35), true) imgui.CenterText(mySerialNumber) imgui.EndChild()
        if imgui.Button(u8'Продолжить', imgui.ImVec2(310, 25)) then activate_window.v = false; setClipboardText(mySerialNumber); os.execute('explorer "https://vk.me/sd_scripts"') end
        if imgui.IsItemHovered() then imgui.BeginTooltip() imgui.TextUnformatted(u8('Нажав на кнопку откроется браузер, где вы попадёте на страницу\nличных сообщений нашего сообщества ВКонтакте.')) imgui.EndTooltip() end
        imgui.End()
    end
    if window.v then
        imgui.ShowCursor = window.v
        imgui.SetNextWindowSize(imgui.ImVec2(400,395), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2((sw/2),(sh/2)), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5), imgui.WindowFlags.AlwaysAutoResize)
        imgui.Begin('Fast Send Money', window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
        
        if imgui.Button(u8(checker.state and 'Остановить' or 'Запустить'),imgui.ImVec2(140, 25)) then
            if checker.list and checker.list ~= 'file empty' then
                checker.state = not checker.state
                if not checker.state then checker.th:terminate() else checker.th:run(); window.v = false end
                chatMessage('Чекер был ' .. (checker.state and 'запущен' or 'остановлен') .. '.')
            else
                chatMessage('Невозможно запустить чекер, так как файл пуст.')
            end
        end
        imgui.SameLine()
        imgui.SetCursorPosX(280)
        imgui.Text(u8'Автор: S&D Scripts')
        imgui.NewLine()
        imgui.BeginChild('button', imgui.ImVec2(0, 75), true)
            if imgui.Button(u8(select and 'Редактировать' or 'Добавить'), imgui.ImVec2(110, 23)) then
                local warnings = false
                if file.read():match(new_name.v .. '\\' .. new_sum.v) and not select then
                    chatMessage('Ошибка: данная запись уже есть в списке.')
                    warnings = true
                end
                select = nil
                if new_name.v:match('(.+)') and new_sum.v:match('(%d+)') and not warnings then
                    if new_name.v == show_by_name then
                        checker.list[show_by_name] = nil
                        checker.save()
                    end
                    local args = new_name.v.. ' ' ..new_sum.v 
                    local var, sum = args:match('(.+)%s(%d+)')
                    if var:match('(%d+)') then 
                        if not (tonumber(var) >= 0 and tonumber(var) < 1001) or not sampIsPlayerConnected(tonumber(var)) then
                            chatMessage('Введен несуществующий ID.')
                        else
                            local var = sampGetPlayerNickname(tonumber(var))
                            file.newline(var .. '\\' .. sum)
                            checker.list = checker.getplayers()
                            chatMessage(string.format('Добавлена новая запись: %s, сумма: $%d.', var, sum)); new_name.v = ''; new_sum.v = ''
                        end
                    elseif var:match('(%A+)') then 
                        file.newline(var .. '\\' .. sum)
                        checker.list = checker.getplayers()
                        chatMessage(string.format('Добавлена новая запись: %s, сумма: $%d.', var, sum)); new_name.v = ''; new_sum.v = ''
                    end
                elseif warnings then
                    new_name.v = ''; new_sum.v = ''
                else
                    chatMessage('Ошибка: не введён никнейм или сумма.')
                end
            end
            imgui.SameLine()
            if imgui.Button(u8'Удалить', imgui.ImVec2(110, 23)) then
                if not select then
                    chatMessage('Ошибка: выберите строку из списка для удаления.')
                else
                    chatMessage('Была удалена строка из списка: '..show_by_name..', сумма: $' ..sum_by_name.. '!')
                    checker.list[show_by_name], select, show_by_name = nil
                    new_name.v = ''; new_sum.v = ''
                    checker.save()
                end
            end
            imgui.SameLine()
            if imgui.Button(u8'Очистить', imgui.ImVec2(110, 23)) then new_name.v = ''; new_sum.v = ''; select = nil end
            
            imgui.Spacing()
            imgui.AlignTextToFramePadding()
            imgui.Text('Nick / ID:')
            imgui.SameLine()
            imgui.PushItemWidth(132)
            if imgui.InputText('##name', new_name) then
                if select and (new_name.v ~= show_by_name) then select = false end
            end
            imgui.SameLine()
            imgui.AlignTextToFramePadding()
            imgui.Text(u8'Сумма:')
            imgui.SameLine()
            imgui.PushItemWidth(90)
            imgui.InputText('##sum', new_sum)
        imgui.EndChild()

        checker.list = checker.getplayers()
        imgui.NewLine()
        
        imgui.BeginGroup()
            imgui.BeginChild('##list', imgui.ImVec2(380, 150), true)
                if checker.list and checker.list ~= 'file empty' then
                    imgui.Columns(3, nil, false)
                    imgui.SetColumnWidth(-1, 155); imgui.Text(u8'Никнейм'); imgui.NextColumn()
                    imgui.SetColumnWidth(-1, 110);imgui.Text(u8'Сумма'); imgui.NextColumn()
                    imgui.Text(u8'Статус'); imgui.NextColumn()
                    imgui.Separator()
                    local count = 0
                    for k,v in pairs(checker.list) do
                        count = count + 1
                        local id = sampGetPlayerIdByNickname(k)
                        if imgui.Selectable(k .. '##' ..count, select == count, 2) then
                            select, show_by_name, sum_by_name, check_id = count, k, v, sampGetPlayerIdByNickname(k)
                            new_name.v = show_by_name
                            new_sum.v = sum_by_name
                        end
                        imgui.NextColumn()
                        local s1, s2, s3 = string.match('$' ..v,'^([^%d]*%d)(%d*)(.-)$')
                        local summ = (tonumber('$' ..v) == 0 and 0 or (s1 .. (s2:reverse():gsub('(%d%d%d)','%1.'):reverse()) .. s3))
                        imgui.Text(summ); imgui.NextColumn()
                        if id and sampGetPlayerScore(id) > 0 then
                            player_status = 'Online [' ..id .. ']'
                        else
                            player_status = 'Offline'
                        end
                        imgui.Text(player_status); imgui.NextColumn()
                    end
                else
                    imgui.Text(u8'Файл пуст') 
                end
            imgui.EndChild()
        imgui.EndGroup()
        imgui.NewLine()
        if imgui.Button(u8'Перезапустить', imgui.ImVec2(180, 30)) then thisScript():reload() end
        imgui.SameLine()
        if imgui.Button(u8'Настройки', imgui.ImVec2(185, 30)) then imgui.OpenPopup(u8'Настройки') end

        if imgui.BeginPopupModal(u8'Настройки', _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
            imgui.AlignTextToFramePadding()
            imgui.Text(u8'Пин-код от банка:')
            imgui.SameLine(); imgui.PushItemWidth(80)
            imgui.InputText('##pincode', pincode)
            if imgui.Checkbox(u8('Сообщения в ' .. (cfg.main.msg and 'чат' or 'консоль')), msg) then cfg.main.msg = msg.v end
            imgui.Text(u8'Интервал работы чекера (сек):')
            imgui.PushItemWidth(200)
            if imgui.SliderInt('##delay', delay, 1, 60) then cfg.checker.interval = delay.v end
            imgui.Text(u8'Задержка после выдачи (сек):')
            imgui.PushItemWidth(200)
            if imgui.SliderInt('##after', after, 60, 180) then cfg.checker.after_action = after.v; end
            if imgui.Checkbox(u8('Скриншот ' .. (cfg.main.screen and 'активен' or 'неактивен')), scr) then cfg.main.screen = scr.v end
            if imgui.Checkbox(u8((cfg.main.onstart and 'Запускать' or 'Не запускать') .. ' после спавна'), onstart) then cfg.main.onstart = onstart.v end 
            if imgui.Button(u8'Сохранить', imgui.ImVec2(200, 20)) then 
                cfg.main.pincode = pincode.v
                lib.ini.save(cfg, 'FSM')
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end
        imgui.End()
    end
end

function chatMessage(msg)
    if cfg.main.msg then
        sampAddChatMessage('[FSM] {ffffff}' .. msg, 0xFACC2E)
    else
        print('[FSM] {ffffff}' ..msg)
    end
end

function sampGetPlayerIdByNickname(nick)
    if type(nick) == "string" then
        for id = 0, 1000 do
            local _, myid = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if sampIsPlayerConnected(id) or id == myid then
                local name = sampGetPlayerNickname(id)
                if nick == name then
                    return id
                end
            end
        end
    end
end

function onWindowMessage(msg, wparam, lparam)
    if msg == 0x100 or msg == 0x101 then
        if (wparam == lib.keys.VK_ESCAPE and (window.v or activate_window.v)) and not isPauseMenuActive() then
            consumeWindowMessage(true, false)
            if msg == 0x101 then
                window.v = false; activate_window.v = false
            end
        end
    end
end

function getSerialNumber()
    local ffi = require("ffi")
    ffi.cdef[[
    int __stdcall GetVolumeInformationA(
    const char* lpRootPathName,
    char* lpVolumeNameBuffer,
    uint32_t nVolumeNameSize,
    uint32_t* lpVolumeSerialNumber,
    uint32_t* lpMaximumComponentLength,
    uint32_t* lpFileSystemFlags,
    char* lpFileSystemNameBuffer,
    uint32_t nFileSystemNameSize
    );
    ]]
    local serial = ffi.new("unsigned long[1]", 0)
    ffi.C.GetVolumeInformationA(nil, nil, 0, serial, nil, nil, nil, 0)
    return serial[0]
end

function getListSerialNumber()
    local update_file = getWorkingDirectory() .. '\\config\\listSerialNumber.json'
    local listSerialNumber = settings_load({}, update_file)
    downloadUrlToFile('https://raw.githubusercontent.com/darksoorok/fsm/main/listSerialNumber.json', update_file, function(id, status, p1, p2)
        if status == 6 then
            local f = io.open(update_file, 'r+')
            if f then
                listSerialNumber = settings_load(decodeJson(f:read('a*')), update_file)
                f:close()
                os.remove(update_file)
                if listSerialNumber and listSerialNumber ~= '{}' then
                    for k, v in pairs(listSerialNumber) do
                        if tostring(v) == tostring(getSerialNumber()) then
                            listSerialNumber = '{}'
                            activate = true
                            break
                        end
                    end
                else
                    chatMessage('[WARNING] Не удалось проверить ваш компьютер на наличие покупки продукта.')
                    thisScript():unload()
                end
            end
        end
    end)
end

function settings_load(table, dir)
    if not doesFileExist(dir) then
        local f = io.open(dir, 'w+'); local suc = f:write(encodeJson(table)); f:close()
        if suc then return table end
        return table
    else
        local f = io.open(dir, 'r+'); local array = decodeJson(f:read('a*')); f:close()
        if not array then return table end
        return array
    end
end

function darkTheme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2

    style.WindowRounding         = 6.0
    style.WindowTitleAlign       = ImVec2(0.5, 0.5)
    style.ChildWindowRounding    = 8.0
    style.FrameRounding          = 5.3
    style.ItemSpacing            = ImVec2(15, 5)
    style.ScrollbarSize          = 7
    style.ScrollbarRounding      = 0
    style.GrabMinSize            = 9.6
    style.GrabRounding           = 1.0
    style.WindowPadding          = ImVec2(10, 10)
    style.AntiAliasedLines       = true
    style.AntiAliasedShapes      = true
    style.FramePadding           = ImVec2(5, 4)
    style.DisplayWindowPadding   = ImVec2(27, 27)
    style.DisplaySafeAreaPadding = ImVec2(5, 5)
    style.ButtonTextAlign        = ImVec2(0.5, 0.5)

    colors[clr.Text]                   = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[clr.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[clr.WindowBg]               = ImVec4(0.00, 0.00, 0.00, 0.94)
    colors[clr.ChildWindowBg]          = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94)
    colors[clr.Border]                 = ImVec4(0.12, 0.91, 0.09, 0.50)
    colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.FrameBg]                = ImVec4(0.44, 0.44, 0.44, 0.60)
    colors[clr.FrameBgHovered]         = ImVec4(0.57, 0.57, 0.57, 0.70)
    colors[clr.FrameBgActive]          = ImVec4(0.76, 0.76, 0.76, 0.80)
    colors[clr.TitleBg]                = ImVec4(0.00, 0.00, 0.00, 1.00)
    colors[clr.TitleBgActive]          = ImVec4(0.02, 0.42, 0.10, 1.00)
    colors[clr.TitleBgCollapsed]       = ImVec4(0.00, 0.00, 0.00, 0.60)
    colors[clr.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
    colors[clr.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
    colors[clr.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
    colors[clr.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
    colors[clr.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
    colors[clr.ComboBg]                = ImVec4(0.20, 0.20, 0.20, 0.99)
    colors[clr.CheckMark]              = ImVec4(0.13, 0.75, 0.55, 0.80)
    colors[clr.SliderGrab]             = ImVec4(0.13, 0.75, 0.75, 0.80)
    colors[clr.SliderGrabActive]       = ImVec4(0.13, 0.75, 1.00, 0.80)
    colors[clr.Button]                 = ImVec4(0.02, 0.42, 0.10, 1.00)
    colors[clr.ButtonHovered]          = ImVec4(0.02, 0.33, 0.07, 1.00)
    colors[clr.ButtonActive]           = ImVec4(0.04, 0.56, 0.13, 1.00)
    colors[clr.Header]                 = ImVec4(0.13, 0.75, 0.55, 0.40)
    colors[clr.HeaderHovered]          = ImVec4(0.10, 0.84, 0.30, 0.60)
    colors[clr.HeaderActive]           = ImVec4(0.09, 0.92, 0.05, 0.80)
    colors[clr.Separator]              = ImVec4(0.13, 0.75, 0.55, 0.40)
    colors[clr.SeparatorHovered]       = ImVec4(0.09, 0.84, 0.30, 0.60)
    colors[clr.SeparatorActive]        = ImVec4(0.09, 0.92, 0.05, 0.80)
    colors[clr.ResizeGrip]             = ImVec4(0.13, 0.75, 0.55, 0.40)
    colors[clr.ResizeGripHovered]      = ImVec4(0.09, 0.84, 0.30, 0.60)
    colors[clr.ResizeGripActive]       = ImVec4(0.09, 0.92, 0.05, 0.80)
    colors[clr.CloseButton]            = ImVec4(0.02, 0.42, 0.10, 1.00)
    colors[clr.CloseButtonHovered]     = ImVec4(0.93, 0.16, 0.07, 1.00)
    colors[clr.CloseButtonActive]      = ImVec4(1.00, 0.00, 0.00, 1.00)
    colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[clr.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
    colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
    colors[clr.TextSelectedBg]         = ImVec4(0.26, 0.59, 0.98, 0.35)
    colors[clr.ModalWindowDarkening]   = ImVec4(0.80, 0.80, 0.80, 0.35)


end
darkTheme()