script_name('Fast Send Money');
script_author("S&D Scripts");
script_description('Send money when player online.')
script_version('1.0')
script_version_number(1)

--## loading modules ##--
local lib = {
    imgui = require 'imgui',
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
            status = false, -- displaying status in a table
        },
        checker = {
            interval = 3, -- check every 3 seconds
            after_action = 60, -- delay 10 seconds after last transfer
            last = 0, -- time of the last transfer
        }
    }
    if lib.ini.save(data, 'FSM') then
        cfg = lib.ini.load(nil, 'FSM')
    end
end

lib.encoding.default = 'CP1251'
u8 = lib.encoding.UTF8
local imgui = lib.imgui
local activate = false
local window = imgui.ImBool(false)
local activate_window = imgui.ImBool(false)
local update = imgui.ImBool(false)
local sw, sh = getScreenResolution()
local new_name = imgui.ImBuffer('', 256)
local new_sum = imgui.ImBuffer('', 256)
local pincode = imgui.ImBuffer(tostring(cfg.main.pincode), 256)
local one_step = imgui.ImBool(false)
local table_status = imgui.ImBool(cfg.main.status)
local msg = imgui.ImBool(cfg.main.msg)
local scr = imgui.ImBool(cfg.main.screen)
local onstart = imgui.ImBool(cfg.main.onstart)
local delay = imgui.ImInt(cfg.checker.interval)
local after = imgui.ImInt(cfg.checker.after_action)
local selects = nil
local upd = {}


--## functions of interaction with file ##-
local file = {
    path = getWorkingDirectory() .. '\\config\\FSM.list',
    log = getWorkingDirectory() .. '\\config\\FSM.log'
}
file.read = function(dir) -- get text from file
    if not doesFileExist(dir) then return 'file empty' end
    local f = io.open(dir, 'r+'); 
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
file.newlinelog = function(text) -- add new line to file log
    local f = io.open(file.log, 'a+');
    f:write(text.. '\n'); f:close()
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
    local players = file.read(file.path)
    if players ~= 'file empty' then 
        local array = {}
        for name, sum in players:gmatch('(%w+_%w+)\\(%d+)') do 
            if array[name] and checker.state then
                chatMessage('{DC143C}[WARNING]{FF4500} Никнейм ' .. name .. ' в списке дублируется! Чекер останавливается.', -1)
                checker.state = false; checker.th:terminate()
            end
            array[name] = sum
        end
        return array
    else
        if checker.state then chatMessage('{FFA500}[ERROR]{F0E68C} Файл пуст. Чекер остановлен.') end
        checker.state = false; checker.th:terminate()
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
    if msg:find('Переводить деньги можно раз в минуту') and checker.state then
        chatMessage('{FFA500}[ERROR]{F0E68C} Переводить деньги можно раз в минуту. Чекер остановлен.')
        sampSendClickTextdraw(65535)
        checker.state = false; checker.th:terminate()
        return false
    end
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
            chatMessage('{FFA500}[ERROR]{F0E68C} Для работы скрипта нужен телефон Samsung Galaxy S10 или IPHONE X.') 
            checker.state = false; checker.th:terminate()
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
        local balance = text:match('На вашем балансе сейчас%: %$([%d.]+)'):gsub('%.', '')
        if tonumber(_G.fsm.sum) <= tonumber(balance) then
            sampSendDialogResponse(41, 1, 0, _G.fsm.sum)
            cfg.checker.last = os.time()
            lib.ini.save(cfg, 'FSM')
            file.newlinelog('[ '..os.date('%d/%m/%y').. ' | ' ..os.date('%H:%M:%S').. ' ] '.._G.fsm.name..' $' .._G.fsm.sum)
            _G.fsm.next = true
        else
            sampSendClickTextdraw(65535)
            chatMessage('{FFA500}[ERROR]{F0E68C} На банковском счёте ' .. formatMoney('$' ..balance) .. '. Данной суммы недостаточно для перевода. Чекер остановлен.')
            checker.state = false; checker.th:terminate()
        end
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
    -- ## CHECK ACTIVATE SERIAL NUMBER ## --
    mySerialNumber = tostring(getSerialNumber())
    local i = 0
    while not getListSerialNumber() and i < 2 do wait(100); i = i + 1 end
    -- ## CHECK UPDATE ## --
    local update_file = getWorkingDirectory() .. '\\fsm_update.json';
    downloadUrlToFile('https://raw.githubusercontent.com/darksoorok/fsm/main/update.json', update_file, function(id, status, p1, p2)
        if status == 6 then    
            local f = io.open(update_file, 'r+')
            if f then
                upd = decodeJson(f:read('a*'))
                f:close()
                --os.remove(update_file)
            end
        end
    end)
    while not sampIsLocalPlayerSpawned() do wait(130) end
    wait(1000)
    local result, server = checkServer(select(1, sampGetCurrentServerAddress()))
    if result then
        chatMessage((activate and 'Скрипт успешно запущен и полностью готов к работе!' or '{DC143C}[WARNING]{FF4500} Скрипт не имеет активации на этом компьютере!') .. ' {228B22}[ Меню: /fsm ]') 
        if cfg.main.onstart then checker.th:run() end
    else
		chatMessage('{FFA500}[ERROR]{F0E68C} Cкрипт завершает работу, т.к. работает только на проекте {FA8072}Arizona RP')
		thisScript():unload()
    end
    if upd.version and upd.version > thisScript().version_num then
        chatMessage('Доступно новое обновление. Введите команду {228B22}/fsmupd{ffffff} для обновления.')
        sampRegisterChatCommand('fsmupd', function()
            update.v = not update.v
        end)
    end
    sampRegisterChatCommand('fsm', function()
        if not activate then
            activate_window.v = true
        else
            window.v = not window.v; imgui.Process = window.v
        end
    end)
    while true do wait(0) imgui.Process = window.v or activate_window.v or update.v; imgui.LockPlayer = window.v or activate_window.v or update.v end
end

function imgui.OnDrawFrame()
    imgui.CenterText = function(text)
        imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(u8(text)).x)/2)
        imgui.Text(u8(text))
    end
    imgui.CenterTextDisabled = function(text)
        imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(u8(text)).x)/2)
        imgui.TextColored(imgui.GetStyle().Colors[imgui.Col.TextDisabled], text)
    end
    if update.v then
        imgui.ShowCursor = update.v
        imgui.SetNextWindowSize(imgui.ImVec2(335,230), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2((sw/2),(sh/2)), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5), imgui.WindowFlags.AlwaysAutoResize)
        imgui.Begin('Fast Send Money', update, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
        imgui.CenterText('Описание обновления v' ..tostring(upd.name).. ':')
        imgui.BeginChild('##infoupdate', imgui.ImVec2(0,115), true)
            local text = upd.info
            if text then
                imgui.TextWrapped(text)
            else
                imgui.SetCursorPosY(50); imgui.SetCursorPosX(25)
                imgui.Text(u8'Не удалось загрузить описание обновления.')
            end
        imgui.EndChild()
        imgui.NewLine()
        if imgui.Button(u8'Обновить скрипт', imgui.ImVec2(150,25)) then
            -- update
        end
        imgui.SameLine()
        if imgui.Button(u8'Закрыть', imgui.ImVec2(150,25)) then update.v = false end
        imgui.End()
    end
    if activate_window.v then
        imgui.ShowCursor = activate_window.v
        imgui.SetNextWindowSize(imgui.ImVec2(335,315), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2((sw/2),(sh/2)), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5), imgui.WindowFlags.AlwaysAutoResize)
        imgui.Begin('Fast Send Money', activate_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
        imgui.CenterText('Ваш компьютер не имеет активации продукта!')
        imgui.BeginChild('##textserialnumber', imgui.ImVec2(0, 115), true) 
            imgui.TextWrapped(u8'  Если вы официально приобретали скрипт, от вас требуется ещё одно маленькое действие.')
            imgui.TextWrapped(u8'  Вам необходимо нажать на кнопку Продолжить, после сообщить серийный номер, который будет скопирован в буфер обмена (вставить в строку сообщения: CTRL+V).')
        imgui.EndChild()
        imgui.CenterText('Серийный номер:')
        imgui.BeginChild('##serialnumber', imgui.ImVec2(0, 35), true) imgui.CenterText(mySerialNumber) imgui.EndChild()
        if imgui.Button(u8'Продолжить', imgui.ImVec2(315, 25)) then activate_window.v = false;  imgui.SetClipboardText(u8("Здравствуйте!\nСкрипт: FSM. Прошу активировать мой код.\nКод: " .. mySerialNumber)); os.execute('explorer "https://vk.me/sd_scripts"') end
        imgui.Hint(u8'Нажав на кнопку, серийный номер сохранится в буфер обмена, после чего откроется браузер, где вы попадёте на страницу личных сообщений нашего сообщества ВКонтакте.', 0)
        if imgui.Button(u8'Перезапустить', imgui.ImVec2(315, 25)) then thisScript():reload() end
        imgui.Separator()
        imgui.CenterTextDisabled('S&D Scripts')
        if imgui.IsItemClicked() then
            os.execute('explorer "https://vk.com/sd_scripts"')
        end
        imgui.Hint(u8'Нажав на этот текст откроется браузер, где вы попадёте на страницу нашего сообщества ВКонтакте.', 1)
        imgui.End()
    end
    if window.v then
        local fileread = file.read(file.log)
        local cooldown = os.time() - cfg.checker.last
        imgui.ShowCursor = window.v
        imgui.SetNextWindowSize(imgui.ImVec2(400,450), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2((sw/2),(sh/2)), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5), imgui.WindowFlags.AlwaysAutoResize)
        imgui.Begin('Fast Send Money', window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
        if imgui.Button(u8(checker.state and 'Остановить' or 'Запустить'),imgui.ImVec2(140, 40)) then
            if not checker.state and (cooldown < 60) then 
                chatMessage('Подождите, сейчас нельзя переводить средства.') 
            elseif checker.list and checker.list ~= 'file empty' then
                checker.state = not checker.state
                if not checker.state then checker.th:terminate() else checker.th:run(); window.v = false end
                chatMessage('Чекер был ' .. (checker.state and 'запущен' or 'остановлен') .. '.')
            elseif checker.list == 'file empty' then
                chatMessage('Невозможно запустить чекер, так как файл пуст.')
            end
        end
        imgui.SameLine()
        imgui.BeginChild('##last', imgui.ImVec2(0, 40), true)
            imgui.AlignTextToFramePadding()
            if cooldown < 60 then
                imgui.Text(u8('Следующий перевод через ' ..(60 - cooldown).. ' сек.'))
            else
                imgui.Text(u8'            Можете переводить.')
            end
        imgui.EndChild()
        imgui.NewLine()
        imgui.BeginChild('##button', imgui.ImVec2(0, 75), true)
            if imgui.Button(u8(selects and 'Редактировать' or 'Добавить'), imgui.ImVec2(110, 23)) then
                local warnings = false
                if new_name.v ~= '' and new_sum.v ~= '' then
                    if new_name.v:match('(%d+)') then
                        if sampIsPlayerConnected(tonumber(new_name.v)) and (tonumber(new_name.v) >= 0 and tonumber(new_name.v) < 1001) then
                            new_name.v = sampGetPlayerNickname(tonumber(new_name.v))
                        end
                    end
                    if file.read(file.path):match(new_name.v .. '\\' .. new_sum.v) and not selects then
                        chatMessage('{FFA500}[ERROR]{F0E68C} Данная запись уже есть в списке.')
                        warnings = true
                    end
                end
                selects = nil
                if new_name.v:match('(.+)') and new_sum.v:match('(%d+)') and not warnings then
                    if new_name.v == show_by_name then
                        checker.list[show_by_name] = nil
                        checker.save()
                    end
                    if new_name.v:match('(%d+)') then
                        if not (tonumber(new_name.v) >= 0 and tonumber(new_name.v) < 1001) or not sampIsPlayerConnected(tonumber(new_name.v)) then
                            chatMessage('{FFA500}[ERROR]{F0E68C} Введен несуществующий ID.')
                        else
                            local nick = sampGetPlayerNickname(tonumber(new_name.v))
                            file.newline(nick .. '\\' .. new_sum.v)
                            checker.list = checker.getplayers()
                            chatMessage(string.format('Добавлена новая запись: %s, сумма: $%d.', nick, tonumber(new_sum.v))); new_name.v = ''; new_sum.v = ''
                        end
                    elseif new_name.v:match('(%A+)') then 
                        file.newline(new_name.v .. '\\' .. new_sum.v)
                        checker.list = checker.getplayers()
                        chatMessage(string.format('Добавлена новая запись: %s, сумма: $%d.', tostring(new_name.v), tonumber(new_sum.v))); new_name.v = ''; new_sum.v = ''
                    end
                elseif warnings then
                    new_name.v = ''; new_sum.v = ''
                else
                    chatMessage('{FFA500}[ERROR]{F0E68C} В полях не указаны Nick_Name или сумма. Заполните все поля.')
                end
            end
            imgui.SameLine()
            if imgui.ButtonClickable(selects, u8'Удалить', imgui.ImVec2(110, 23)) then
                chatMessage('Была удалена строка из списка: '..show_by_name..', сумма: $' ..sum_by_name.. '!')
                checker.list[show_by_name], selects, show_by_name = nil
                new_name.v = ''; new_sum.v = ''
                checker.save()
            end
            imgui.SameLine()
            if imgui.ButtonClickable(selects or new_name.v ~= '' or new_sum.v ~= '', u8('Очистить'), imgui.ImVec2(110, 23)) then new_name.v = ''; new_sum.v = ''; selects = nil end
            imgui.Spacing()
            if imgui.NewInputText('##new_name', new_name, 170, u8'NickName или ID игрока', 2) then
                if selects and (new_name.v ~= show_by_name) then selects = false end
            end
            imgui.SameLine()
            imgui.SetCursorPosX(200)
            imgui.NewInputText('##new_sum', new_sum, 170, u8'Сумма перевода', 2)
        imgui.EndChild()

        checker.list = checker.getplayers()
        imgui.NewLine()
        
        imgui.BeginGroup()
            imgui.BeginChild('##list', imgui.ImVec2(380, 170), true)
                if checker.list and checker.list ~= 'file empty' then
                    imgui.Columns((cfg.main.status and 3 or 2), nil, false)
                    imgui.SetColumnWidth(-1, (cfg.main.status and 155 or 190)); imgui.Text(u8'Никнейм'); imgui.NextColumn()
                    imgui.SetColumnWidth(-1, 110);imgui.Text(u8'Сумма'); imgui.NextColumn()
                    if cfg.main.status then imgui.Text(u8'Статус'); imgui.NextColumn() end
                    imgui.Separator()
                    local count = 0
                    for k,v in pairs(checker.list) do
                        count = count + 1
                        local id = sampGetPlayerIdByNickname(k)
                        if imgui.Selectable(k.. '##' ..count, selects == count, 2) then
                            selects, show_by_name, sum_by_name, check_id = count, k, v, sampGetPlayerIdByNickname(k)
                            new_name.v = show_by_name
                            new_sum.v = sum_by_name
                        end
                        imgui.NextColumn()
                        imgui.Text(formatMoney('$' ..v)); imgui.NextColumn()
                        if cfg.main.status then
                            if id and sampGetPlayerScore(id) > 0 then
                                player_status = 'Online [' ..id .. ']'
                            else
                                player_status = 'Offline'
                            end
                            imgui.Text(player_status); imgui.NextColumn()
                        end
                    end
                else
                    imgui.Text(u8'Файл пуст') 
                end
            imgui.EndChild()
        imgui.EndGroup()
        imgui.NewLine()
        if imgui.Button(u8'Список переводов', imgui.ImVec2(180, 30)) then 
            if fileread ~= 'file empty' then imgui.OpenPopup(u8'Список переводов') else chatMessage('{FFA500}[ERROR]{F0E68C} Вы ещё никому не осуществляли перевод.') end
        end
        imgui.SameLine()
        if imgui.Button(u8'Настройки', imgui.ImVec2(185, 30)) then imgui.OpenPopup(u8'Настройки') end
        imgui.Separator()
        imgui.CenterTextDisabled('S&D Scripts')
        if imgui.IsItemClicked() then
            os.execute('explorer "https://vk.com/sd_scripts"')
        end
        imgui.Hint(u8'Нажав на этот текст откроется браузер, где вы попадёте на страницу нашего сообщества ВКонтакте.', 1)        
        
        if imgui.BeginPopupModal(u8'Настройки', _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
            imgui.NewInputText('##pincode', pincode, 200, u8'Введите пин-код от карты', 2)
            imgui.Hint(u8'Требуется для автоматического ввода пин-кода от банковской карточки.')
            if imgui.Checkbox(u8('Сообщения в ' .. (cfg.main.msg and 'чат' or 'консоль')), msg) then cfg.main.msg = msg.v end
            imgui.Hint(u8('Сообщения от скрипта будут выводится в ' .. (cfg.main.msg and 'чат' or 'консоль SampFuncs') .. '.'), 1.6)
            imgui.Text(u8'Интервал работы чекера (сек):')
            imgui.Hint(u8('Через каждые ' ..cfg.checker.interval.. ' секунд(-ы) скрипт будет проверять наличие\nигрока из списка в сети.'), 0.1)
            imgui.PushItemWidth(200)
            if imgui.SliderInt('##delay', delay, 1, 60) then cfg.checker.interval = delay.v end
            imgui.Text(u8'Задержка после выдачи (сек):')
            imgui.Hint(u8'Интервал ожидания после выдачи денежных средств (сервером разрешено раз в минуту переводить деньги).', 0.1)
            imgui.PushItemWidth(200)
            if imgui.SliderInt('##after', after, 60, 180) then cfg.checker.after_action = after.v; end
            if imgui.Checkbox(u8('Автоскриншот ' .. (cfg.main.screen and 'активен' or 'неактивен')), scr) then cfg.main.screen = scr.v end
            imgui.Hint(u8('После перевода денежных средств скрипт сможет самостоятельно сделать скриншот.'), 1.6)
            if imgui.Checkbox(u8('Статус онлайна ' .. (cfg.main.status and 'включён' or 'выключен')), table_status) then cfg.main.status = table_status.v end
            imgui.Hint(u8('При включении показывает статус онлайна.\nИспользовать на свой страх и риск!!!\nЗа данную фичу могут забанить, т.к. это своего рода чекер (на администрацию также действует).'), 1)
            if imgui.Checkbox(u8((cfg.main.onstart and 'Запускать' or 'Не запускать') .. ' после спавна'), onstart) then cfg.main.onstart = onstart.v end 
            imgui.Hint(u8('Данная функция запустит чекер сразу после захода в игру.'), 1.6)
            if imgui.Button(u8'Перезапустить скрипт', imgui.ImVec2(200, 25)) then thisScript():reload() end
            imgui.Separator()
            if imgui.Button(u8'Сохранить', imgui.ImVec2(200, 25)) then 
                cfg.main.pincode = pincode.v
                lib.ini.save(cfg, 'FSM')
                imgui.CloseCurrentPopup()
            end

            imgui.EndPopup()
        end

        if imgui.BeginPopupModal(u8'Список переводов', _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
            imgui.BeginChild('##log', imgui.ImVec2(460, 230), true)
                imgui.Columns(5, nil, false)
                imgui.SetColumnWidth(-1, 30); imgui.Text('#'); imgui.NextColumn()
                imgui.SetColumnWidth(-1, 80); imgui.Text(u8'Дата'); imgui.NextColumn()
                imgui.SetColumnWidth(-1, 80); imgui.Text(u8'Время'); imgui.NextColumn()
                imgui.SetColumnWidth(-1, 155); imgui.Text(u8'Никнейм'); imgui.NextColumn()
                imgui.SetColumnWidth(-1, 110);imgui.Text(u8'Сумма'); imgui.NextColumn()
                imgui.Separator()
                local count = 0
                for line in string.gmatch(fileread, '[^\n]+') do
                    count = count + 1
                    local date, time, nick, money = line:match('%[ (%d+%/%d+/%d+) %| (%d+%:%d+%:%d+) %] (%w+_%w+) (%$%d+)')
                    imgui.Text(tostring(count)); imgui.NextColumn()
                    imgui.Text(date); imgui.NextColumn()
                    imgui.Text(time); imgui.NextColumn()
                    imgui.Text(nick); imgui.NextColumn()
                    imgui.Text(formatMoney(money)); imgui.NextColumn()
                    imgui.Separator()
                end
            imgui.EndChild()
            if imgui.Button(u8'Очистить список', imgui.ImVec2(210, 25)) then chatMessage('Список переводов успешно очищен.'); imgui.CloseCurrentPopup(); os.remove(file.log) end
            imgui.SameLine()
            if imgui.Button(u8'Закрыть', imgui.ImVec2(235, 25)) then imgui.CloseCurrentPopup() end
            imgui.EndPopup()
        end    

        imgui.End()
    end
end

function formatMoney(sum)
    local s1, s2, s3 = string.match(sum,'^([^%d]*%d)(%d*)(.-)$')
    local formatSum = (tonumber(sum) == 0 and 0 or (s1 .. (s2:reverse():gsub('(%d%d%d)','%1.'):reverse()) .. s3))
    return formatSum
end

function chatMessage(msg)
    if cfg.main.msg then
        sampAddChatMessage('[FSM] {ffffff}' .. msg, 0x228B22)
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
    local listSerialNumber = getWorkingDirectory() .. '\\config\\listSerialNumber.json'
    downloadUrlToFile('https://sd-scripts.ru/api/?start.auth={"code":' .. mySerialNumber .. '}', listSerialNumber, function(id, status, p1, p2)
        if status == 6 then
            local f = io.open(listSerialNumber, 'r+')
            if f then
                local dec = decodeJson(f:read('a*')).response.result
                f:close()
                activate = (dec.registered and dec.accepted)
            end
            os.remove(listSerialNumber)
        end
    end)
    return activate
end

function imgui.Hint(text, delay, action)
    if imgui.IsItemHovered() then
        if go_hint == nil then go_hint = os.clock() + (delay and delay or 0.0) end
        local alpha = (os.clock() - go_hint) * 5
        if os.clock() >= go_hint then
            imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(10, 10))
            imgui.PushStyleVar(imgui.StyleVar.Alpha, (alpha <= 1.0 and alpha or 1.0))
                imgui.PushStyleColor(imgui.Col.PopupBg, imgui.ImVec4(0.11, 0.11, 0.11, 1.00))
                    imgui.BeginTooltip()
                    imgui.PushTextWrapPos(450)
                    imgui.TextColored(imgui.GetStyle().Colors[imgui.Col.ButtonHovered], u8'Подсказка:')
                    imgui.TextUnformatted(text)
                    if action ~= nil then
                        imgui.TextColored(imgui.GetStyle().Colors[imgui.Col.TextDisabled], '\n'..action)
                    end
                    if not imgui.IsItemVisible() and imgui.GetStyle().Alpha == 1.0 then go_hint = nil end
                    imgui.PopTextWrapPos()
                    imgui.EndTooltip()
                imgui.PopStyleColor()
            imgui.PopStyleVar(2)
        end
    end
end

function imgui.NewInputText(lable, val, width, hint, hintpos)
    local hint = hint and hint or ''
    local hintpos = tonumber(hintpos) and tonumber(hintpos) or 1
    local cPos = imgui.GetCursorPos()
    imgui.PushItemWidth(width)
    local result = imgui.InputText(lable, val)
    if #val.v == 0 then
        local hintSize = imgui.CalcTextSize(hint)
        if hintpos == 2 then imgui.SameLine(cPos.x + (width - hintSize.x) / 2)
        elseif hintpos == 3 then imgui.SameLine(cPos.x + (width - hintSize.x - 5))
        else imgui.SameLine(cPos.x + 5) end
        imgui.TextColored(imgui.ImVec4(1.00, 1.00, 1.00, 0.40), tostring(hint))
    end
    imgui.PopItemWidth()
    return result
end

function imgui.ButtonClickable(clickable, ...)
    if clickable then
        return imgui.Button(...)

    else
        local r, g, b, a = imgui.ImColor(imgui.GetStyle().Colors[imgui.Col.Button]):GetFloat4()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, a/2) )
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r, g, b, a/2))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r, g, b, a/2))
        imgui.PushStyleColor(imgui.Col.Text, imgui.GetStyle().Colors[imgui.Col.TextDisabled])
            imgui.Button(...)
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
    end
end

function checkServer(ip)
    for k, v in pairs({
        ['Phoenix'] 	= '185.169.134.3',
        ['Tucson'] 		= '185.169.134.4',
        ['Scottdale']	= '185.169.134.43',
        ['Chandler'] 	= '185.169.134.44', 
        ['Brainburg'] 	= '185.169.134.45',
        ['Saint Rose'] 	= '185.169.134.5',
        ['Mesa'] 		= '185.169.134.59',
        ['Red Rock'] 	= '185.169.134.61',
        ['Yuma'] 		= '185.169.134.107',
        ['Surprise'] 	= '185.169.134.109',
        ['Prescott'] 	= '185.169.134.166',
        ['Glendale'] 	= '185.169.134.171',
        ['Kingman'] 	= '185.169.134.172',
        ['Winslow'] 	= '185.169.134.173',
        ['Payson'] 		= '185.169.134.174',
        ['Gilbert']     = '80.66.82.191'
    }) do
        if v == ip then 
            return true, k
        end
    end
    return false
end

function onScriptTerminate(LuaScript, quitGame)
    if LuaScript == thisScript() then
        if imgui then imgui.ShowCursor = false; showCursor(false) end
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