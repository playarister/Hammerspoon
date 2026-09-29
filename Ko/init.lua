-------------------------------------------------------------------------------- 
-- SpaceLayerKey
-- release :2026/09/29
--
-- [키 매핑 및 조작 가이드]
--
-- 1. 네비모드 진입/종료
--    - Space 홀드 (150ms 이상) : 임시 네비모드 (Space를 떼면 종료)
--    - ★ 좌측 Control 2연타 (400ms 이내) : 토글 네비모드 (다시 연타하면 종료)
--    - ★ Space + 네비키 : 즉시 임시 네비모드 활성화
--    - ★ Space 짧게 탭 (150ms 이내) : 일반 Space 입력 (문서에 공백)
--    - ★ Shift + Space   : 한/영 전환
--    - Ctrl + Space      : 시스템 한영 전환 (통과)
--    - ESC               : 네비모드 강제 탈출
--
-- 2. 방향키 모드 & 마우스 모드
--    - I / K / J / L           : 방향키 / 마우스 이동
--    - W / S / A / D           : 마우스 이동 (4배속)
--    - Y / P                   : Home / End
--    - U / O / . / Q / E       : 크롤 (천천히 시작 → 빠르게 가속)
--    - N 또는 Z                : 마우스 좌클릭
--    - M 또는 X                : 마우스 가운데클릭
--    - , 또는 C                : 마우스 우클릭
--      ★ Shift + 클릭 → 선택 영역 추가/확장 (물리 Shift rawFlags 그대로 사용)
--    - V                       : 브라우저 뒤로
--    - B                       : 브라우저 앞으로
--    - H                       : BackSpace
--    - ;                       : ForwardDelete / 3배 부스터
--    - - / =                   : 볼륨 다운 / 업 (5%씩, 내부 추적 방식)
--    - Space + '               : 다음 모니터 전환
--
-- 3. 전역 단축키
--    - Cmd + Option + J/L : 창을 이전/다음 모니터로 이동
--    - Cmd + Option + I   : 창 최대화/복원 토글
--    - Cmd + Option + K   : 창 하이드
--
-- 4. 무시앱 등록
--   Space 키를 Panning으로 사용하는 2D앱에서는 스크립트 기능이 무시됨
--   예) ClipStudio Paint, PhotoShop 등
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 0. C-LUA BINDING & CONSTANTS
--------------------------------------------------------------------------------
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local math_ceil = math.ceil
local math_exp = math.exp
local now_sec = hs.timer.secondsSinceEpoch
local string_find = string.find
local string_lower = string.lower
local string_upper = string.upper
local string_format = string.format
local EVT_TYPES = hs.eventtap.event.types
local EVT_PROPS = hs.eventtap.event.properties
local EVT_LEFT_DOWN = EVT_TYPES.leftMouseDown
local EVT_LEFT_UP = EVT_TYPES.leftMouseUp
local EVT_LEFT_DRAG = EVT_TYPES.leftMouseDragged
local EVT_RIGHT_DOWN = EVT_TYPES.rightMouseDown
local EVT_RIGHT_UP = EVT_TYPES.rightMouseUp
local EVT_RIGHT_DRAG = EVT_TYPES.rightMouseDragged
local EVT_OTHER_DOWN = EVT_TYPES.otherMouseDown
local EVT_OTHER_UP = EVT_TYPES.otherMouseUp
local EVT_MOUSE_MOVE = EVT_TYPES.mouseMoved
local EVT_KEY_DOWN = EVT_TYPES.keyDown
local EVT_KEY_UP = EVT_TYPES.keyUp
local CG_FLAG_SHIFT = 0x00020000
local CG_FLAG_CONTROL = 0x00040000
local CG_FLAG_ALTERNATE = 0x00080000
local CG_FLAG_COMMAND = 0x00100000
--------------------------------------------------------------------------------
-- 1. 설정값
--------------------------------------------------------------------------------
local CONFIG = {
    HOLD_TIMEOUT = 0.150,
    LEFT_CONTROL_KEYCODE = 59,
    LEFT_CONTROL_TAP_WINDOW = 0.400,
    LEFT_CONTROL_TAP_COUNT = 2,
    ARROW_MODE_SWITCH_TIMEOUT = 0.250,
    ARROW_KEY_DELAY = 0.040,
    MOUSE_CLICK_TIMEOUT = 0.250,
    SPACE_KEYCODE = 49,
    BASE_SPEED = 5,
    EXP_FACTOR = 3,
    MAX_SPEED = 55,
    INERTIA_DECAY = 0.35,
    PHYSICS_INTERVAL = 0.016,
    EXTERNAL_MOUSE_CHECK_INTERVAL = 0.050,
    HUD_OFFSET_X = 20,
    HUD_OFFSET_Y = 15,
    HUD_PADDING = 12,
    HUD_V_PADDING = 6,
    HUD_GAP = 6,
    HUD_MIN_W = 100,
    HUD_FONT = ".AppleSystemUIFontBold",
    HUD_FONT_SIZE = 16,
    HUD_ALPHA = 0.55,
    SCREEN_BORDER_STROKE = 15,
    SCREEN_BORDER_DURATION = 1.5,
    SCREEN_BORDER_COLOR = { red = 1, green = 0.2, blue = 0.2, alpha = 0.9 },
    SCREEN_BORDER_RADIUS = 12,
    PAINTING_APP_CACHE_DURATION = 0.5,
    WINDOW_ZOOM_STATE_MAX = 50,
    SCROLL_SPEED_MULTIPLIER = 15,
    SCROLL_START_MULTIPLIER = 1,
    VOLUME_STEP = 5,
    INPUT_SOURCE_CACHE_DURATION = 5.0,
    LANG_CACHE_DURATION = 0.5,
    BROWSER_CHECK_DURATION = 0.3,
    -- ★ 한영전환 안정성: 입력 소스 변경 최소 간격 (macOS 처리 시간 확보)
    SOURCE_CHANGE_MIN_INTERVAL = 0.050,  -- 50ms
    IME_COMMIT_DELAY = 0.003,  -- 3ms (포커스 리프레시 지연)
}
CONFIG.HUD_H = CONFIG.HUD_FONT_SIZE + CONFIG.HUD_V_PADDING * 2
local HUD_TEXT_STYLE = {
    font = CONFIG.HUD_FONT,
    size = CONFIG.HUD_FONT_SIZE
}
--------------------------------------------------------------------------------
-- 2. 키코드 매핑
--------------------------------------------------------------------------------
local function getKC(keyStr, defaultCode)
    return (hs.keycodes and hs.keycodes.map and hs.keycodes.map[keyStr]) or defaultCode
end
local KC = {
    w = getKC("w", 13), a = getKC("a", 0),
    s = getKC("s", 1), d = getKC("d", 2),
    q = getKC("q", 12), e = getKC("e", 14),
    i = getKC("i", 34), k = getKC("k", 40),
    j = getKC("j", 38), l = getKC("l", 37),
    u = getKC("u", 32), o = getKC("o", 31),
    y = getKC("y", 16), p = getKC("p", 35),
    v = getKC("v", 9), b = getKC("b", 11),
    h = getKC("h", 4),
    semicolon = getKC(";", 41),
    z = getKC("z", 6), x = getKC("x", 7),
    c = getKC("c", 8), n = getKC("n", 45),
    m = getKC("m", 46),
    comma = getKC(",", 43), period = getKC(".", 47),
    quote = getKC("'", 39),
    minus = getKC("-", 27), equals = getKC("=", 24),
    escape = getKC("escape", 53),
    up = getKC("up", 126), down = getKC("down", 125),
    left = getKC("left", 123), right = getKC("right", 124),
    home = getKC("home", 115), end_key = getKC("end", 119),
    delete = getKC("delete", 51), forwarddelete = getKC("forwarddelete", 117),
    bracket_left = getKC("[", 33), bracket_right = getKC("]", 30),
}
local WSAD_MAP = { [KC.w]='w', [KC.a]='a', [KC.s]='s', [KC.d]='d' }
local IKJL_NAME_MAP = { [KC.i]='i', [KC.k]='k', [KC.j]='j', [KC.l]='l' }
local ARROW_KC_MAP = { i=KC.up, k=KC.down, j=KC.left, l=KC.right }
local NAV_KEYS = {
    [KC.w]=true, [KC.a]=true, [KC.s]=true, [KC.d]=true,
    [KC.q]=true, [KC.e]=true,
    [KC.i]=true, [KC.k]=true, [KC.j]=true, [KC.l]=true,
    [KC.u]=true, [KC.o]=true, [KC.y]=true, [KC.p]=true,
    [KC.n]=true, [KC.m]=true, [KC.comma]=true, [KC.period]=true,
    [KC.z]=true, [KC.x]=true, [KC.c]=true,
    [KC.v]=true, [KC.b]=true,
    [KC.h]=true, [KC.semicolon]=true,
    [KC.quote]=true,
    [KC.minus]=true, [KC.equals]=true,
}
--------------------------------------------------------------------------------
-- 3. 상태 변수
--------------------------------------------------------------------------------
local state = {
    isNavActive = false,
    isToggleNav = false,
    isMouseLocked = false,
    semicolonPressed = false,
    spacePressed = false,
    holdTimer = nil,
    spaceDownWasMouseLocked = false,
    leftControlTapCount = 0,
    lastLeftControlTapTime = 0,
    leftControlWasDown = false,
    mouseButtonsHeld = { left=false, right=false, middle=false },
    lastMouseClickTime = { left=0, right=0, middle=0 },
    mouseClickCount = { left=1, right=1, middle=1 },
    currentVx = 0, currentVy = 0,
    keyPressStartTime = nil,
    currentScrollV = 0,
    scrollKeyPressStartTime = nil,
    scrollUpPressed = false,
    scrollDownPressed = false,
    keys = { w=false, a=false, s=false, d=false },
    ikjlKeys = { i=false, k=false, j=false, l=false },
    arrowKeyTimers = { i=nil, k=nil, j=nil, l=nil },
    moveTimer = nil,
    spaceTap = nil,
    navKeyTap = nil,
    screenBorder = nil,
    screenBorderTimer = nil,
    hudCanvas = nil,
    cachedMousePos = { x=0, y=0 },
    lastHudX = 0, lastHudY = 0,
    currentHudW = CONFIG.HUD_MIN_W,
    currentLangCache = "A",
    lastHudMode = nil, lastHudLang = nil,
    cachedGlobalFrame = { x=0, y=0, w=1920, h=1080 },
    screenWatcher = nil,
    screenFrame = { x=0, y=0, w=1920, h=1080 },
    windowZoomState = {},
    isPaintingAppCached = false,
    lastPaintingAppCheck = 0,
    physicalMods = { shift=false, alt=false, ctrl=false, cmd=false },
    syntheticBypass = false,
    syntheticBypassTimer = nil,
    clickHandled = { left=false, right=false, middle=false },
    volumeIndicatorTimer = nil,
    currentVolume = nil,
    -- ★ 한영전환 안정성 상태 (단순화)
    lastSourceChangeTime = 0,
    imeCommitTimer = nil,
}
local lastExternalMouseCheck = 0
local hudSizeCache = {}
local tmpPos = { x=0, y=0 }
local tmpScrollDelta = { 0, 0 }
local log = hs.logger.new("NavMode", "info")

local cachedInputSources = { korean = nil, english = nil, lastUpdate = 0 }
local lastLangCacheUpdate = 0
local lastBrowserCheck = 0
local cachedIsBrowser = false
--------------------------------------------------------------------------------
-- 4. 한/영 입력 소스
--------------------------------------------------------------------------------
local function findInputSources()
    local now = now_sec()
    if cachedInputSources.korean and cachedInputSources.english and
       (now - cachedInputSources.lastUpdate) < CONFIG.INPUT_SOURCE_CACHE_DURATION then
        return cachedInputSources.korean, cachedInputSources.english
    end
    
    local koreanSrc, englishSrc = nil, nil
    local okL, layouts = pcall(hs.keycodes.layouts, true)
    if okL and type(layouts) == "table" then
        for _, src in ipairs(layouts) do
            if type(src) ~= "string" then goto c1 end
            local id = string_lower(src)
            if string_find(id, "com.apple.keylayout.abc", 1, true) then
                englishSrc = src
            elseif not englishSrc and string_find(id, "com.apple.keylayout.us", 1, true) then
                englishSrc = src
            end
            ::c1::
        end
    end
    local okM, methods = pcall(hs.keycodes.methods, true)
    if okM and type(methods) == "table" then
        for _, src in ipairs(methods) do
            if type(src) ~= "string" then goto c2 end
            if string_find(string_lower(src), "korean", 1, true) then
                koreanSrc = src
            end
            ::c2::
        end
    end
    
    cachedInputSources.korean = koreanSrc
    cachedInputSources.english = englishSrc
    cachedInputSources.lastUpdate = now
    
    return koreanSrc, englishSrc
end

-- ★ IME 커밋 (단순화: 플래그 제거, 이전 타이머만 취소)
local function forceImeCommit()
    -- 이전 타이머 취소 (중복 실행 방지)
    if state.imeCommitTimer then
        state.imeCommitTimer:stop()
        state.imeCommitTimer = nil
    end
    
    local win = hs.window.focusedWindow()
    if not win then return end
    
    -- 현재 창 포커스 재호출
    pcall(function() win:focus() end)
    
    -- 다른 창 찾기
    local allWindows = hs.window.allWindows()
    local altWin = nil
    local winId = win:id()
    
    for _, w in ipairs(allWindows) do
        if w:id() ~= winId and w:isVisible() then
            altWin = w
            break
        end
    end
    
    if altWin then
        -- 다른 창으로 포커스 이동 후 복귀
        pcall(function() altWin:focus() end)
        state.imeCommitTimer = hs.timer.doAfter(0.0005, function()
            pcall(function() win:focus() end)
            state.imeCommitTimer = nil
        end)
    end
end

-- ★ 한영전환 (입력 소스 변경은 항상 수행, 간격만 보장)
local function toggleKoreanEnglish()
    local now = now_sec()
    
    -- 입력 소스 변경 최소 간격 보장 (macOS race condition 방지)
    if (now - state.lastSourceChangeTime) < CONFIG.SOURCE_CHANGE_MIN_INTERVAL then
        -- 너무 빠르면 무시 (사용자가 연타한 것으로 간주)
        return
    end
    state.lastSourceChangeTime = now
    
    local ok, err = pcall(function()
        local cur = hs.keycodes.currentSourceID()
        if not cur or type(cur) ~= "string" then return end
        local kr, en = findInputSources()
        if not kr or not en then return end
        
        -- 입력 소스 변경 (항상 수행)
        if cur == kr then
            hs.keycodes.currentSourceID(en)
        elseif cur == en then
            hs.keycodes.currentSourceID(kr)
        else
            hs.keycodes.currentSourceID(kr)
        end
        
        -- IME 커밋 (지연 실행)
        hs.timer.doAfter(CONFIG.IME_COMMIT_DELAY, function()
            forceImeCommit()
        end)
    end)
    if not ok then log:wf("한영전환 실패: %s", tostring(err)) end
end

local function updateLangCache(force)
    local now = now_sec()
    if not force and (now - lastLangCacheUpdate) < CONFIG.LANG_CACHE_DURATION then
        return
    end
    
    local ok, src = pcall(hs.keycodes.currentSourceID)
    if not ok or not src or type(src) ~= "string" then
        state.currentLangCache = "?"
        return
    end
    local id = string_lower(src)
    if string_find(id, "korean", 1, true) or
       string_find(id, "hangul", 1, true) or
       string_find(id, "2set", 1, true) then
        state.currentLangCache = "한"
    else
        state.currentLangCache = "A"
    end
    
    lastLangCacheUpdate = now
end

pcall(function()
    hs.keycodes.inputSourceChanged(function()
        cachedInputSources.lastUpdate = 0
        lastLangCacheUpdate = 0
    end)
end)
--------------------------------------------------------------------------------
-- 5. 헬퍼
--------------------------------------------------------------------------------
local function sendQuickKey(keyCode, mods)
    local evDown = hs.eventtap.event.newKeyEvent(mods, keyCode, true)
    local evUp = hs.eventtap.event.newKeyEvent(mods, keyCode, false)
    if evDown then evDown:post() end
    if evUp then evUp:post() end
end
local function getDeviceVolume()
    local ok, dev = pcall(hs.audiodevice.defaultOutputDevice)
    if not ok or not dev then return 50 end
    local ok2, v = pcall(function() return dev:volume() end)
    if not ok2 or type(v) ~= "number" then return 50 end
    if v <= 1.0 then v = v * 100 end
    return math_floor(v + 0.5)
end
local function sendSystemVolumeKey(isUp)
    local ok, err = pcall(function()
        local dev = hs.audiodevice.defaultOutputDevice()
        if not dev then return end

        if state.currentVolume == nil then
            state.currentVolume = getDeviceVolume()
        end

        local step = CONFIG.VOLUME_STEP
        local newVol
        if isUp then
            newVol = math_min(100, state.currentVolume + step)
            pcall(function() if dev:muted() then dev:setMuted(false) end end)
        else
            newVol = math_max(0, state.currentVolume - step)
        end
        newVol = math_floor(newVol + 0.5)

        state.currentVolume = newVol

        pcall(function() dev:setVolume(newVol) end)

        if state.hudCanvas then
            state.hudCanvas:elementAttribute(3, "text", tostring(newVol) .. "%")
        end

        if state.volumeIndicatorTimer then
            state.volumeIndicatorTimer:stop()
        end
        state.volumeIndicatorTimer = hs.timer.doAfter(1.0, function()
            state.volumeIndicatorTimer = nil
            if state.isNavActive then updateHudText() end
        end)
    end)
    if not ok then log:ef("볼륨 조절 실패: %s", tostring(err)) end
end
local function buildModsArray(flags, includeCmd)
    local n = 0
    local buf = {}
    if flags.shift then n=n+1; buf[n]='shift' end
    if flags.alt then n=n+1; buf[n]='alt' end
    if flags.ctrl then n=n+1; buf[n]='ctrl' end
    if includeCmd then n=n+1; buf[n]='cmd' end
    return buf
end
local function buildMouseMods(flags)
    local n = 0
    local buf = {}
    if flags.shift then n=n+1; buf[n]='shift' end
    if flags.alt then n=n+1; buf[n]='alt' end
    if flags.ctrl then n=n+1; buf[n]='ctrl' end
    if flags.cmd then n=n+1; buf[n]='cmd' end
    return buf
end
local function emitSpaceKey()
    state.spaceTap:stop()
    pcall(function() hs.eventtap.keyStroke({}, "space", 0) end)
    state.spaceTap:start()
end
--------------------------------------------------------------------------------
-- 5.1 물리 modifier 상태를 반영한 마우스 클릭
--------------------------------------------------------------------------------
local function getModsRawFlags(mods)
    local ok, raw = pcall(hs.eventtap.checkKeyboardModifiers)
    if not ok or type(raw) ~= "number" then raw = 0 end
    for _, m in ipairs(mods or {}) do
        if m == "shift" then raw = raw + CG_FLAG_SHIFT
        elseif m == "alt" then raw = raw + CG_FLAG_ALTERNATE
        elseif m == "ctrl" then raw = raw + CG_FLAG_CONTROL
        elseif m == "cmd" then raw = raw + CG_FLAG_COMMAND
        end
    end
    return raw
end
local function postModifierMouseClick(buttonType, isDown, mods)
    local downType, upType, btnNum
    if buttonType == "right" then
        downType, upType = EVT_RIGHT_DOWN, EVT_RIGHT_UP
    elseif buttonType == "middle" then
        downType, upType, btnNum = EVT_OTHER_DOWN, EVT_OTHER_UP, 2
    else
        downType, upType = EVT_LEFT_DOWN, EVT_LEFT_UP
    end
    local pos = { x = state.cachedMousePos.x, y = state.cachedMousePos.y }
    local raw = getModsRawFlags(mods)
    local evtType = isDown and downType or upType
    local evt = hs.eventtap.event.newMouseEvent(evtType, pos)
    if not evt then return false end
    evt:setProperty(EVT_PROPS.mouseEventClickState, 1)
    if btnNum then
        evt:setProperty(EVT_PROPS.mouseEventButtonNumber, btnNum)
    end
    evt:rawFlags(raw)
    evt:post()
    return true
end
--------------------------------------------------------------------------------
-- 6. HUD Canvas
--------------------------------------------------------------------------------
local function calculateHudWidth(modeText, langText)
    local cacheKey = modeText .. "|" .. langText
    if hudSizeCache[cacheKey] then
        return hudSizeCache[cacheKey][1], hudSizeCache[cacheKey][2], hudSizeCache[cacheKey][3]
    end
    local modeSize = hs.drawing.getTextDrawingSize(modeText, HUD_TEXT_STYLE)
    local langSize = hs.drawing.getTextDrawingSize(langText, HUD_TEXT_STYLE)
    local modeW = (modeSize and modeSize.w) or 0
    local langW = (langSize and langSize.w) or 0
    local totalW = CONFIG.HUD_PADDING + modeW + CONFIG.HUD_GAP + langW + CONFIG.HUD_PADDING
    if totalW < CONFIG.HUD_MIN_W then totalW = CONFIG.HUD_MIN_W end
    hudSizeCache[cacheKey] = {totalW, modeW, langW}
    return totalW, modeW, langW
end
local function createHudCanvas()
    if state.hudCanvas then return end
    local modeText = (state.isMouseLocked and "마우스" or "방향키") .. " /"
    local langText = state.currentLangCache
    local totalW, modeW, langW = calculateHudWidth(modeText, langText)
    state.currentHudW = totalW
    state.hudCanvas = hs.canvas.new({ x=0, y=0, w=totalW, h=CONFIG.HUD_H })
    state.hudCanvas:level("overlay")
    state.hudCanvas[1] = {
        type="rectangle", action="fill",
        fillColor={red=0.1, green=0.1, blue=0.1, alpha=CONFIG.HUD_ALPHA},
        roundedRectRadii={xRadius=6, yRadius=6}
    }
    state.hudCanvas[2] = {
        type="text", text=modeText,
        textColor={red=1, green=1, blue=1, alpha=CONFIG.HUD_ALPHA},
        textSize=CONFIG.HUD_FONT_SIZE, textFont=CONFIG.HUD_FONT,
        textAlignment="left",
        frame={x=CONFIG.HUD_PADDING, y=CONFIG.HUD_V_PADDING, w=modeW, h=CONFIG.HUD_FONT_SIZE}
    }
    state.hudCanvas[3] = {
        type="text", text=langText,
        textColor={red=0.3, green=0.7, blue=1.0, alpha=CONFIG.HUD_ALPHA},
        textSize=CONFIG.HUD_FONT_SIZE, textFont=CONFIG.HUD_FONT,
        textAlignment="left",
        frame={x=CONFIG.HUD_PADDING + modeW + CONFIG.HUD_GAP, y=CONFIG.HUD_V_PADDING, w=langW, h=CONFIG.HUD_FONT_SIZE}
    }
end
local function updateHudPosition()
    if not state.isNavActive or not state.hudCanvas then return end
    local mx = state.cachedMousePos.x
    local my = state.cachedMousePos.y
    local ix = math_floor(mx + CONFIG.HUD_OFFSET_X)
    local iy = math_floor(my + CONFIG.HUD_OFFSET_Y)
    local sf = state.screenFrame
    local hudW = state.currentHudW
    local hudH = CONFIG.HUD_H
    if ix + hudW > sf.x + sf.w - 5 then
        ix = math_floor(mx - CONFIG.HUD_OFFSET_X - hudW)
    end
    if iy + hudH > sf.y + sf.h - 5 then
        iy = math_floor(my - CONFIG.HUD_OFFSET_Y - hudH)
    end
    if ix == state.lastHudX and iy == state.lastHudY then return end
    state.lastHudX = ix; state.lastHudY = iy
    state.hudCanvas:frame({x=ix, y=iy, w=hudW, h=hudH})
end
local function updateHudText()
    if not state.isNavActive or not state.hudCanvas then return end
    local mode = state.isMouseLocked and "mouse" or "arrow"
    local lang = state.currentLangCache
    if mode == state.lastHudMode and lang == state.lastHudLang then return end
    state.lastHudMode = mode; state.lastHudLang = lang
    local modeText = (state.isMouseLocked and "마우스" or "방향키") .. " /"
    local langText = lang
    local newW, newModeW, newLangW = calculateHudWidth(modeText, langText)
    state.currentHudW = newW
    state.hudCanvas:elementAttribute(2, "text", modeText)
    state.hudCanvas:elementAttribute(2, "frame", {
        x=CONFIG.HUD_PADDING, y=CONFIG.HUD_V_PADDING, w=newModeW, h=CONFIG.HUD_FONT_SIZE
    })
    state.hudCanvas:elementAttribute(3, "text", langText)
    state.hudCanvas:elementAttribute(3, "frame", {
        x=CONFIG.HUD_PADDING + newModeW + CONFIG.HUD_GAP, y=CONFIG.HUD_V_PADDING, w=newLangW, h=CONFIG.HUD_FONT_SIZE
    })
    state.hudCanvas:frame({x=state.lastHudX, y=state.lastHudY, w=state.currentHudW, h=CONFIG.HUD_H})
end
local function showHud()
    if not state.isNavActive then return end
    local p = hs.mouse.getAbsolutePosition()
    if p then
        state.cachedMousePos.x = p.x
        state.cachedMousePos.y = p.y
    end
    createHudCanvas()
    updateLangCache(true)
    state.lastHudMode = nil; state.lastHudLang = nil
    local mx = state.cachedMousePos.x
    local my = state.cachedMousePos.y
    local ix = math_floor(mx + CONFIG.HUD_OFFSET_X)
    local iy = math_floor(my + CONFIG.HUD_OFFSET_Y)
    local sf = state.screenFrame
    local hudW = state.currentHudW
    local hudH = CONFIG.HUD_H
    if ix + hudW > sf.x + sf.w - 5 then
        ix = math_floor(mx - CONFIG.HUD_OFFSET_X - hudW)
    end
    if iy + hudH > sf.y + sf.h - 5 then
        iy = math_floor(my - CONFIG.HUD_OFFSET_Y - hudH)
    end
    state.lastHudX = ix
    state.lastHudY = iy
    updateHudText()
    state.hudCanvas:show()
end
local function hideHud()
    if state.hudCanvas then state.hudCanvas:hide() end
end
--------------------------------------------------------------------------------
-- 7. 헬퍼
--------------------------------------------------------------------------------
local function getIkjlCount()
    local c = 0
    if state.ikjlKeys.i then c=c+1 end
    if state.ikjlKeys.k then c=c+1 end
    if state.ikjlKeys.j then c=c+1 end
    if state.ikjlKeys.l then c=c+1 end
    return c
end
local function allMouseButtonsReleased()
    return not state.mouseButtonsHeld.left
       and not state.mouseButtonsHeld.right
       and not state.mouseButtonsHeld.middle
end
local function cancelAllArrowKeyTimers()
    for k, t in pairs(state.arrowKeyTimers) do
        if t then t:stop() end
        state.arrowKeyTimers[k] = nil
    end
end
--------------------------------------------------------------------------------
-- 8. 모니터 프레임
--------------------------------------------------------------------------------
local function updateGlobalDesktopFrame()
    local screens = hs.screen.allScreens()
    if #screens == 0 then
        local scr = hs.mouse.getCurrentScreen()
        state.cachedGlobalFrame = scr and scr:fullFrame() or { x=0, y=0, w=1920, h=1080 }
        state.screenFrame = state.cachedGlobalFrame
        return
    end
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    for _, s in ipairs(screens) do
        local f = s:fullFrame()
        if f.x < minX then minX = f.x end
        if f.y < minY then minY = f.y end
        if f.x+f.w > maxX then maxX = f.x+f.w end
        if f.y+f.h > maxY then maxY = f.y+f.h end
    end
    state.cachedGlobalFrame = { x=minX, y=minY, w=maxX-minX, h=maxY-minY }
    local curScr = hs.mouse.getCurrentScreen()
    if curScr then state.screenFrame = curScr:fullFrame() end
end
pcall(function()
    state.screenWatcher = hs.screen.watcher.new(updateGlobalDesktopFrame)
    state.screenWatcher:start()
end)
updateGlobalDesktopFrame()
--------------------------------------------------------------------------------
-- 9. 화면 테두리 + 모니터 전환
--------------------------------------------------------------------------------
local function showScreenBorder(targetScreen)
    if state.screenBorderTimer then state.screenBorderTimer:stop(); state.screenBorderTimer = nil end
    if state.screenBorder then state.screenBorder:delete(); state.screenBorder = nil end
    local frame = targetScreen:fullFrame()
    state.screenBorder = hs.canvas.new({ x=frame.x, y=frame.y, w=frame.w, h=frame.h })
    state.screenBorder:level("overlay")
    local halfStroke = CONFIG.SCREEN_BORDER_STROKE / 2
    state.screenBorder[1] = {
        type="rectangle", action="stroke",
        strokeColor=CONFIG.SCREEN_BORDER_COLOR, strokeWidth=CONFIG.SCREEN_BORDER_STROKE,
        roundedRectRadii={xRadius=CONFIG.SCREEN_BORDER_RADIUS, yRadius=CONFIG.SCREEN_BORDER_RADIUS},
        frame={x=halfStroke, y=halfStroke,
               w=frame.w - CONFIG.SCREEN_BORDER_STROKE, h=frame.h - CONFIG.SCREEN_BORDER_STROKE}
    }
    state.screenBorder:show()
    state.screenBorderTimer = hs.timer.doAfter(CONFIG.SCREEN_BORDER_DURATION, function()
        if state.screenBorder then state.screenBorder:delete(); state.screenBorder = nil end
        state.screenBorderTimer = nil
    end)
end
local function cycleNextScreen()
    local screens = hs.screen.allScreens()
    if #screens <= 1 then return end
    local cur = hs.mouse.getCurrentScreen()
    local nxt = nil
    for i, s in ipairs(screens) do
        if s == cur then nxt = screens[(i % #screens) + 1]; break end
    end
    if nxt then
        local f = nxt:frame()
        tmpPos.x = f.x + math_floor(f.w / 2)
        tmpPos.y = f.y + math_floor(f.h / 2)
        hs.eventtap.leftClick(tmpPos)
        showScreenBorder(nxt)
        updateHudPosition()
    end
end
--------------------------------------------------------------------------------
-- 10. 마우스 클릭
--------------------------------------------------------------------------------
local function mouseClickEvent(buttonType, isDown, mods)
    local now = now_sec()
    local hasMods = mods and #mods > 0
    if hasMods and not isDown and state.clickHandled[buttonType] then
        state.clickHandled[buttonType] = false
        return
    end
    if hasMods and isDown then
        if postModifierMouseClick(buttonType, true, mods) then
            postModifierMouseClick(buttonType, false, mods)
            state.clickHandled[buttonType] = true
            return
        end
    end
    state.mouseButtonsHeld[buttonType] = isDown
    if isDown then
        if (now - state.lastMouseClickTime[buttonType]) <= CONFIG.MOUSE_CLICK_TIMEOUT then
            state.mouseClickCount[buttonType] = state.mouseClickCount[buttonType] + 1
        else
            state.mouseClickCount[buttonType] = 1
        end
        state.lastMouseClickTime[buttonType] = now
    end
    local count = state.mouseClickCount[buttonType]
    local evt = nil
    if buttonType == "left" then
        evt = hs.eventtap.event.newMouseEvent(
            isDown and EVT_LEFT_DOWN or EVT_LEFT_UP, state.cachedMousePos)
        if evt then evt:setProperty(EVT_PROPS.mouseEventClickState, count) end
    elseif buttonType == "right" then
        evt = hs.eventtap.event.newMouseEvent(
            isDown and EVT_RIGHT_DOWN or EVT_RIGHT_UP, state.cachedMousePos)
        if evt then evt:setProperty(EVT_PROPS.mouseEventClickState, count) end
    elseif buttonType == "middle" then
        evt = hs.eventtap.newMouseEvent(
            isDown and EVT_OTHER_DOWN or EVT_OTHER_UP, state.cachedMousePos)
        if evt then
            evt:setProperty(EVT_PROPS.mouseEventButtonNumber, 2)
            evt:setProperty(EVT_PROPS.mouseEventClickState, count)
        end
    end
    if evt then evt:post() end
end
local function releaseAllMouseButtons()
    if state.mouseButtonsHeld.left then
        mouseClickEvent("left", false, {}); state.mouseButtonsHeld.left = false
    end
    if state.mouseButtonsHeld.right then
        mouseClickEvent("right", false, {}); state.mouseButtonsHeld.right = false
    end
    if state.mouseButtonsHeld.middle then
        mouseClickEvent("middle", false, {}); state.mouseButtonsHeld.middle = false
    end
end
--------------------------------------------------------------------------------
-- 11. 페인팅 앱 감지 + 브라우저 감지
--------------------------------------------------------------------------------
local PAINTING_APP_BUNDLES = {
    ["jp.co.celsys.CLIPSTUDIOPAINT"] = true,
    ["com.adobe.Photoshop"] = true,
    ["com.adobe.PhotoshopBeta"] = true,
    ["com.adobe.illustrator"] = true,
    ["com.adobe.LightroomClassicCC"] = true,
    ["com.krita.krita"] = true,
    ["org.kde.krita"] = true,
    ["com.artrage.ArtRage"] = true,
    ["com.corel.Painter"] = true,
    ["com.paintstormstudio.paintstorm"] = true,
}
local PAINTING_APP_NAMES = {
    "clip studio", "clipstudio", "photoshop", "illustrator",
    "krita", "artrage", "painter"
}
local function checkPaintingApp()
    local ok, app = pcall(function() return hs.application.frontmostApplication() end)
    if not ok or not app then return false end
    local bid = app:bundleID()
    if bid and PAINTING_APP_BUNDLES[bid] then return true end
    if bid then
        local lbid = string_lower(bid)
        if string_find(lbid, "celsys", 1, true) and
           string_find(lbid, "clipstudiopaint", 1, true) then return true end
    end
    local name = app:name()
    if name then
        local lname = string_lower(name)
        for _, pattern in ipairs(PAINTING_APP_NAMES) do
            if string_find(lname, pattern, 1, true) then return true end
        end
    end
    return false
end
local function shouldBlockInPaintingApp()
    local now = now_sec()
    if (now - state.lastPaintingAppCheck) < CONFIG.PAINTING_APP_CACHE_DURATION then
        return state.isPaintingAppCached
    end
    state.isPaintingAppCached = checkPaintingApp()
    state.lastPaintingAppCheck = now
    return state.isPaintingAppCached
end
pcall(function()
    hs.application.watcher.new(function(_, eventType, _)
        if eventType == hs.application.watcher.activated then
            state.lastPaintingAppCheck = 0
            hs.timer.doAfter(0.05, function()
                if shouldBlockInPaintingApp() and state.isNavActive then
                    stopNavMode()
                end
            end)
        end
    end):start()
end)
local BROWSER_APP_NAMES = {
    ["GOOGLE CHROME"] = true,
    ["SAFARI"] = true,
    ["FIREFOX"] = true,
    ["FIREFOX DEVELOPER EDITION"] = true,
    ["FIREFOX NIGHTLY"] = true,
    ["MICROSOFT EDGE"] = true,
    ["BRAVE BROWSER"] = true,
    ["VIVALDI"] = true,
    ["OPERA"] = true,
    ["ARC"] = true,
    ["ORION"] = true,
    ["SIGMAOS"] = true,
    ["WHALE"] = true,
    ["네이버 웨일"] = true,
    ["네이버웨일"] = true,
    ["SAMSUNG INTERNET"] = true,
    ["TOR BROWSER"] = true,
    ["WATERFOX"] = true,
    ["PALE MOON"] = true,
    ["EPIC PRIVATE BROWSER"] = true,
}

local function isMouseOverBrowserApp()
    local now = now_sec()
    if (now - lastBrowserCheck) < CONFIG.BROWSER_CHECK_DURATION then
        return cachedIsBrowser
    end
    
    local mousePos = hs.mouse.getAbsolutePosition()
    local orderedWindows = hs.window.orderedWindows()
    local result = false
    
    for _, win in ipairs(orderedWindows) do
        local frame = win:frame()
        if frame:contains(mousePos.x, mousePos.y) then
            local app = win:application()
            if app then
                local appName = app:name()
                if appName and type(appName) == "string" then
                    local upperName = string_upper(appName)
                    result = BROWSER_APP_NAMES[upperName] or false
                end
            end
            break
        end
    end
    
    cachedIsBrowser = result
    lastBrowserCheck = now
    return result
end
--------------------------------------------------------------------------------
-- 12. 물리 엔진
--------------------------------------------------------------------------------
local function updatePhysics()
    local now = now_sec()
    if now - lastExternalMouseCheck > CONFIG.EXTERNAL_MOUSE_CHECK_INTERVAL then
        lastExternalMouseCheck = now
        if state.currentVx == 0 and state.currentVy == 0 then
            local p = hs.mouse.getAbsolutePosition()
            state.cachedMousePos.x = p.x
            state.cachedMousePos.y = p.y
        end
    end
    local wsadActive = (state.keys.w or state.keys.a or state.keys.s or state.keys.d)
    local wsadMul = wsadActive and 4 or 1
    local spdMul = (state.isMouseLocked and state.semicolonPressed) and (3*wsadMul) or wsadMul
    local dx, dy = 0, 0
    if state.keys.w then dy=dy-1 end
    if state.keys.s then dy=dy+1 end
    if state.keys.a then dx=dx-1 end
    if state.keys.d then dx=dx+1 end
    if state.isMouseLocked then
        if state.ikjlKeys.i then dy=dy-1 end
        if state.ikjlKeys.k then dy=dy+1 end
        if state.ikjlKeys.j then dx=dx-1 end
        if state.ikjlKeys.l then dx=dx+1 end
    end
    if dx ~= 0 or dy ~= 0 then
        if not state.keyPressStartTime then state.keyPressStartTime = now end
        local dur = now - state.keyPressStartTime
        local eBase = CONFIG.BASE_SPEED * spdMul
        local eMax = CONFIG.MAX_SPEED * spdMul
        local spd = eBase
        if dur > 0.3 then
            spd = eBase * math_exp((dur-0.3) * CONFIG.EXP_FACTOR)
            if spd > eMax then spd = eMax end
        end
        if dx ~= 0 and dy ~= 0 then dx=dx*0.7071; dy=dy*0.7071 end
        state.currentVx = dx * spd; state.currentVy = dy * spd
    else
        state.keyPressStartTime = nil
        state.currentVx = state.currentVx * CONFIG.INERTIA_DECAY
        state.currentVy = state.currentVy * CONFIG.INERTIA_DECAY
        if math_abs(state.currentVx) < 0.2 then state.currentVx = 0 end
        if math_abs(state.currentVy) < 0.2 then state.currentVy = 0 end
    end
    if state.currentVx ~= 0 or state.currentVy ~= 0 then
        tmpPos.x = state.cachedMousePos.x + state.currentVx
        tmpPos.y = state.cachedMousePos.y + state.currentVy
        local gf = state.cachedGlobalFrame
        tmpPos.x = math_max(gf.x, math_min(gf.x+gf.w-1, tmpPos.x))
        tmpPos.y = math_max(gf.y, math_min(gf.y+gf.h-1, tmpPos.y))
        if state.mouseButtonsHeld.left then
            local e = hs.eventtap.event.newMouseEvent(EVT_LEFT_DRAG, tmpPos)
            if e then e:setProperty(EVT_PROPS.mouseEventClickState, state.mouseClickCount.left); e:post() end
        elseif state.mouseButtonsHeld.right then
            local e = hs.eventtap.event.newMouseEvent(EVT_RIGHT_DRAG, tmpPos)
            if e then e:setProperty(EVT_PROPS.mouseEventClickState, state.mouseClickCount.right); e:post() end
        else
            hs.mouse.setAbsolutePosition(tmpPos)
            local e = hs.eventtap.event.newMouseEvent(EVT_MOUSE_MOVE, tmpPos)
            if e then e:post() end
        end
        state.cachedMousePos.x = tmpPos.x; state.cachedMousePos.y = tmpPos.y
        updateHudPosition()
    else
        updateHudPosition()
    end
    local scrMul = (state.isMouseLocked and state.semicolonPressed) and 3 or 1
    local sDir = 0
    if state.scrollUpPressed then sDir=sDir+1 end
    if state.scrollDownPressed then sDir=sDir-1 end
    if sDir ~= 0 then
        if not state.scrollKeyPressStartTime then state.scrollKeyPressStartTime = now end
        local dur = now - state.scrollKeyPressStartTime
        local scrollStartSpeed = CONFIG.BASE_SPEED * CONFIG.SCROLL_START_MULTIPLIER
        local scrollMaxSpeed = CONFIG.MAX_SPEED * CONFIG.SCROLL_SPEED_MULTIPLIER * scrMul
        local spd = scrollStartSpeed
        if dur > 0.3 then
            spd = scrollStartSpeed * math_exp((dur-0.3) * CONFIG.EXP_FACTOR)
            if spd > scrollMaxSpeed then spd = scrollMaxSpeed end
        end
        state.currentScrollV = sDir * spd
    else
        state.scrollKeyPressStartTime = nil
        state.currentScrollV = state.currentScrollV * CONFIG.INERTIA_DECAY
        if math_abs(state.currentScrollV) < 0.2 then state.currentScrollV = 0 end
    end
    if state.currentScrollV ~= 0 then
        tmpScrollDelta[1] = 0
        tmpScrollDelta[2] = math_floor(state.currentScrollV)
        local e = hs.eventtap.event.newScrollEvent(tmpScrollDelta, {}, "pixel")
        if e then e:post() end
    end
end
--------------------------------------------------------------------------------
-- 13. 네비게이션 제어
--------------------------------------------------------------------------------
local function startNavMode()
    if state.isNavActive then return end
    state.isNavActive = true
    state.semicolonPressed = false
    if state.holdTimer then state.holdTimer:stop(); state.holdTimer = nil end
    showHud()
    if not state.moveTimer then
        state.moveTimer = hs.timer.doEvery(CONFIG.PHYSICS_INTERVAL, updatePhysics)
    end
end
local function stopNavMode()
    state.isNavActive = false
    state.isToggleNav = false
    state.semicolonPressed = false
    hideHud()
    releaseAllMouseButtons()
    state.keys.w=false; state.keys.a=false; state.keys.s=false; state.keys.d=false
    state.ikjlKeys.i=false; state.ikjlKeys.k=false; state.ikjlKeys.j=false; state.ikjlKeys.l=false
    cancelAllArrowKeyTimers()
    state.isMouseLocked = false
    state.keyPressStartTime = nil; state.currentVx=0; state.currentVy=0
    state.scrollKeyPressStartTime = nil; state.currentScrollV=0
    state.scrollUpPressed=false; state.scrollDownPressed=false
    if state.holdTimer then state.holdTimer:stop(); state.holdTimer=nil end
    if state.moveTimer then state.moveTimer:stop(); state.moveTimer=nil end
    state.lastHudMode=nil; state.lastHudLang=nil
    state.lastHudX=0; state.lastHudY=0
    state.clickHandled.left=false; state.clickHandled.right=false; state.clickHandled.middle=false
    state.syntheticBypass = false
    if state.syntheticBypassTimer then
        state.syntheticBypassTimer:stop()
        state.syntheticBypassTimer = nil
    end
    if state.volumeIndicatorTimer then
        state.volumeIndicatorTimer:stop()
        state.volumeIndicatorTimer = nil
    end
    state.currentVolume = nil
    -- ★ IME 커밋 타이머 정리
    if state.imeCommitTimer then
        state.imeCommitTimer:stop()
        state.imeCommitTimer = nil
    end
end
--------------------------------------------------------------------------------
-- 14. 좌측 Control 연타 처리
--------------------------------------------------------------------------------
local function handleLeftControlTap()
    local now = now_sec()
    if (now - state.lastLeftControlTapTime) <= CONFIG.LEFT_CONTROL_TAP_WINDOW then
        state.leftControlTapCount = state.leftControlTapCount + 1
    else
        state.leftControlTapCount = 1
    end
    state.lastLeftControlTapTime = now
    if state.leftControlTapCount >= CONFIG.LEFT_CONTROL_TAP_COUNT then
        state.leftControlTapCount = 0
        state.lastLeftControlTapTime = 0
        if state.isToggleNav then
            stopNavMode()
            log:i("좌측 Control 2연타: 토글 네비모드 종료")
        else
            state.isToggleNav = true
            state.isMouseLocked = false
            startNavMode()
            log:i("좌측 Control 2연타: 토글 네비모드 진입")
        end
    end
end
--------------------------------------------------------------------------------
-- 15. 전역 창 관리 핫키
--------------------------------------------------------------------------------
local function moveWindowToScreen(direction)
    local ok, err = pcall(function()
        local win = hs.window.focusedWindow()
        if not win then return end
        local screens = hs.screen.allScreens()
        if #screens <= 1 then return end
        local curScreen = win:screen()
        if not curScreen then return end
        local curFrame = win:frame()
        local curScreenFrame = curScreen:frame()
        if not curScreenFrame.w or curScreenFrame.w <= 0 then return end
        if not curScreenFrame.h or curScreenFrame.h <= 0 then return end
        local relX = (curFrame.x - curScreenFrame.x) / curScreenFrame.w
        local relY = (curFrame.y - curScreenFrame.y) / curScreenFrame.h
        local relW = curFrame.w / curScreenFrame.w
        local relH = curFrame.h / curScreenFrame.h
        local curIndex = nil
        for i, s in ipairs(screens) do
            if s == curScreen then curIndex = i; break end
        end
        if not curIndex then return end
        local targetIndex
        if direction == "prev" then
            targetIndex = ((curIndex - 2) % #screens) + 1
        else
            targetIndex = (curIndex % #screens) + 1
        end
        local targetScreen = screens[targetIndex]
        local targetScreenFrame = targetScreen:frame()
        local newFrame = {
            x = targetScreenFrame.x + relX * targetScreenFrame.w,
            y = targetScreenFrame.y + relY * targetScreenFrame.h,
            w = relW * targetScreenFrame.w,
            h = relH * targetScreenFrame.h
        }
        pcall(function() win:setFrame(newFrame, 0.3) end)
    end)
    if not ok then log:ef("moveWindowToScreen 오류: %s", tostring(err)) end
end
hs.hotkey.bind({"cmd", "alt"}, "j", function() moveWindowToScreen("prev") end)
hs.hotkey.bind({"cmd", "alt"}, "l", function() moveWindowToScreen("next") end)
hs.hotkey.bind({"cmd", "alt"}, "i", function()
    pcall(function()
        local win = hs.window.focusedWindow()
        if not win then return end
        local winId = win:id()
        if not winId then return end
        local screen = win:screen()
        if not screen then return end
        local screenFrame = screen:frame()
        local curFrame = win:frame()
        if state.windowZoomState[winId] then
            local prevFrame = state.windowZoomState[winId]
            pcall(function() win:setFrame(prevFrame, 0.3) end)
            state.windowZoomState[winId] = nil
        else
            local count = 0
            for _ in pairs(state.windowZoomState) do count = count + 1 end
            if count >= CONFIG.WINDOW_ZOOM_STATE_MAX then
                for k in pairs(state.windowZoomState) do
                    state.windowZoomState[k] = nil
                    break
                end
            end
            state.windowZoomState[winId] = {
                x=curFrame.x, y=curFrame.y, w=curFrame.w, h=curFrame.h
            }
            pcall(function() win:setFrame(screenFrame, 0.3) end)
        end
    end)
end)
hs.hotkey.bind({"cmd", "alt"}, "k", function()
    pcall(function() hs.eventtap.keyStroke({"cmd"}, "h", 0) end)
end)
log:i("Cmd+Option+J/K/L/I 전역 창 관리 핫키 등록 완료")
--------------------------------------------------------------------------------
-- 16. 네비게이션 키 이벤트
--------------------------------------------------------------------------------
state.navKeyTap = hs.eventtap.new({
    EVT_KEY_DOWN, EVT_KEY_UP, EVT_TYPES.flagsChanged
}, function(event)
    local ok, result = pcall(function()
        local eventType = event:getType()
        if eventType == EVT_TYPES.flagsChanged then
            if state.syntheticBypass then
                return false
            end
            local keyCode = event:getKeyCode()
            local flags = event:getFlags()
            state.physicalMods.shift = flags.shift and true or false
            state.physicalMods.alt   = flags.alt   and true or false
            state.physicalMods.ctrl  = flags.ctrl  and true or false
            state.physicalMods.cmd   = flags.cmd   and true or false
            local leftControlNowDown = flags.ctrl and (keyCode == CONFIG.LEFT_CONTROL_KEYCODE)
            if leftControlNowDown and not state.leftControlWasDown then
                local onlyLeftControl = not flags.cmd
                    and not flags.alt
                    and not flags.shift
                    and not flags.fn
                if onlyLeftControl then
                    handleLeftControlTap()
                end
            end
            state.leftControlWasDown = leftControlNowDown
            return false
        end
        local keyCode = event:getKeyCode()
        local isDown = (eventType == EVT_KEY_DOWN)
        local isRepeat = (event:getProperty(EVT_PROPS.keyboardEventAutorepeat) == 1)
        local flags = event:getFlags()
        if isDown and not isRepeat
           and state.spacePressed
           and not state.isNavActive
           and not shouldBlockInPaintingApp()
           and NAV_KEYS[keyCode] then
            if state.holdTimer then state.holdTimer:stop(); state.holdTimer = nil end
            state.isToggleNav = false
            startNavMode()
        end
        if not state.isNavActive then return false end
        if shouldBlockInPaintingApp() then
            stopNavMode()
            return false
        end
        if keyCode == KC.escape then
            if isDown then stopNavMode() end
            return true
        end
        if keyCode==KC.w or keyCode==KC.a or keyCode==KC.s or keyCode==KC.d then
            if flags.cmd or flags.ctrl then
                local m = WSAD_MAP[keyCode]; if m then state.keys[m]=false end
                return false
            end
            local m = WSAD_MAP[keyCode]
            if m then state.keys[m] = isDown end
            if isDown and not state.isMouseLocked then
                state.isMouseLocked = true; updateHudText()
            end
            return true
        end
        if keyCode==KC.i or keyCode==KC.k or keyCode==KC.j or keyCode==KC.l then
            if flags.cmd or flags.ctrl then
                local m = IKJL_NAME_MAP[keyCode]; if m then state.ikjlKeys[m]=false end
                return false
            end
            local kName = IKJL_NAME_MAP[keyCode]
            if not kName then return true end
            if isDown then
                state.ikjlKeys[kName] = true
                if getIkjlCount() >= 2 then
                    cancelAllArrowKeyTimers()
                    if not state.isMouseLocked then
                        state.isMouseLocked = true; updateHudText()
                    end
                elseif not state.isMouseLocked then
                    if state.arrowKeyTimers[kName] then state.arrowKeyTimers[kName]:stop() end
                    local capturedFlags = {
                        shift = flags.shift,
                        alt = flags.alt,
                        ctrl = flags.ctrl
                    }
                    state.arrowKeyTimers[kName] = hs.timer.doAfter(CONFIG.ARROW_KEY_DELAY, function()
                        state.arrowKeyTimers[kName] = nil
                        if state.ikjlKeys[kName] and not state.isMouseLocked then
                            local arrowCode = ARROW_KC_MAP[kName]
                            if arrowCode then
                                sendQuickKey(arrowCode, buildModsArray(capturedFlags, false))
                            end
                        end
                    end)
                end
            else
                state.ikjlKeys[kName] = false
                if state.arrowKeyTimers[kName] then
                    state.arrowKeyTimers[kName]:stop()
                    state.arrowKeyTimers[kName] = nil
                end
            end
            return true
        end
        if keyCode == KC.minus then
            if isDown and not isRepeat then sendSystemVolumeKey(false) end
            return true
        end
        if keyCode == KC.equals then
            if isDown and not isRepeat then sendSystemVolumeKey(true) end
            return true
        end
        if keyCode==KC.u or keyCode==KC.q then
            state.scrollUpPressed=isDown
            return true
        end
        if keyCode==KC.o or keyCode==KC.e or keyCode==KC.period then
            state.scrollDownPressed=isDown
            return true
        end
        if keyCode==KC.y then
            if isDown and not isRepeat then sendQuickKey(KC.home, buildModsArray(flags, false)) end
            return true
        end
        if keyCode==KC.p then
            if isDown and not isRepeat then sendQuickKey(KC.end_key, buildModsArray(flags, false)) end
            return true
        end
        if keyCode==KC.n or keyCode==KC.z then
            local mods = buildMouseMods(flags)
            if isDown then
                if not state.isMouseLocked then
                    state.isMouseLocked = true
                    updateHudText()
                end
                if not isRepeat then mouseClickEvent("left", true, mods) end
            else
                if not isRepeat then mouseClickEvent("left", false, mods) end
                if allMouseButtonsReleased() and state.isMouseLocked then
                    if isMouseOverBrowserApp() then
                        log:i("브라우저 앱 - 마우스 모드 유지")
                    else
                        state.isMouseLocked = false
                        updateHudText()
                    end
                end
            end
            return true
        end
        if keyCode==KC.m or keyCode==KC.x then
            local mods = buildMouseMods(flags)
            if isDown then
                if not state.isMouseLocked then
                    state.isMouseLocked = true
                    updateHudText()
                end
                if not isRepeat then mouseClickEvent("middle", true, mods) end
            else
                if not isRepeat then mouseClickEvent("middle", false, mods) end
                if allMouseButtonsReleased() and state.isMouseLocked then
                    if isMouseOverBrowserApp() then
                        log:i("브라우저 앱 - 마우스 모드 유지")
                    else
                        state.isMouseLocked = false
                        updateHudText()
                    end
                end
            end
            return true
        end
        if keyCode==KC.comma or keyCode==KC.c then
            local mods = buildMouseMods(flags)
            if isDown then
                if not state.isMouseLocked then
                    state.isMouseLocked = true
                    updateHudText()
                end
                if not isRepeat then mouseClickEvent("right", true, mods) end
            else
                if not isRepeat then mouseClickEvent("right", false, mods) end
                if allMouseButtonsReleased() and state.isMouseLocked then
                    if isMouseOverBrowserApp() then
                        log:i("브라우저 앱 - 마우스 모드 유지")
                    else
                        state.isMouseLocked = false
                        updateHudText()
                    end
                end
            end
            return true
        end
        if keyCode==KC.v then
            if isDown and not isRepeat then sendQuickKey(KC.bracket_left, buildModsArray(flags, true)) end
            return true
        end
        if keyCode==KC.b then
            if isDown and not isRepeat then sendQuickKey(KC.bracket_right, buildModsArray(flags, true)) end
            return true
        end
        if keyCode==KC.quote then
            if isDown and not isRepeat then cycleNextScreen() end
            return true
        end
        if keyCode == KC.h then
            if isDown and not isRepeat then sendQuickKey(KC.delete, buildModsArray(flags, false)) end
            return true
        end
        if keyCode == KC.semicolon then
            state.semicolonPressed = isDown
            if not state.isMouseLocked then
                if isDown and not isRepeat then sendQuickKey(KC.forwarddelete, buildModsArray(flags, false)) end
            end
            return true
        end
        return false
    end)
    if not ok then log:ef("navKeyTap: %s", tostring(result)) end
    return result or false
end)
--------------------------------------------------------------------------------
-- 17. Spacebar
--------------------------------------------------------------------------------
state.spaceTap = hs.eventtap.new({ EVT_KEY_DOWN, EVT_KEY_UP }, function(event)
    local ok, result = pcall(function()
        local keyCode = event:getKeyCode()
        if keyCode ~= CONFIG.SPACE_KEYCODE then return false end
        if shouldBlockInPaintingApp() then
            if state.isNavActive then stopNavMode() end
            return false
        end
        local flags = event:getFlags()
        if flags.cmd or flags.ctrl then return false end
        local isDown = (event:getType() == EVT_KEY_DOWN)
        local isRepeat = (event:getProperty(EVT_PROPS.keyboardEventAutorepeat) == 1)
        if isRepeat then return true end
        
        if flags.shift then
            if isDown and not isRepeat then
                local ok, err = pcall(toggleKoreanEnglish)
                if not ok then log:wf("한영전환 실: %s", tostring(err)) end
                
                if state.isNavActive then
                    updateLangCache(true)
                    updateHudText()
                end
            end
            return true
        end
        
        if isDown then
            state.spacePressed = true
            if state.isToggleNav and state.isMouseLocked then
                state.spaceDownWasMouseLocked = true
                if state.holdTimer then state.holdTimer:stop() end
                state.holdTimer = hs.timer.doAfter(CONFIG.ARROW_MODE_SWITCH_TIMEOUT, function()
                    state.holdTimer = nil
                    if state.spacePressed and state.isToggleNav and state.isMouseLocked then
                        state.isMouseLocked = false
                        updateHudText()
                        log:i("Space 250ms 홀드: 방향키 모드로 전환")
                    end
                end)
                return true
            end
            if state.isToggleNav then
                state.spaceDownWasMouseLocked = false
                return true
            end
            state.spaceDownWasMouseLocked = false
            if state.holdTimer then state.holdTimer:stop() end
            state.holdTimer = hs.timer.doAfter(CONFIG.HOLD_TIMEOUT, function()
                state.holdTimer = nil
                if state.spacePressed and not state.isToggleNav then
                    startNavMode()
                end
            end)
            return true
        end
        state.spacePressed = false
        if state.isToggleNav then
            if state.holdTimer then
                state.holdTimer:stop()
                state.holdTimer = nil
                emitSpaceKey()
                log:i("Space 250ms 미만 : 일반 Space 입력")
            elseif state.spaceDownWasMouseLocked then
                log:i("Space 250ms 이상 홀드: 방향키 모드 전환 완료")
            else
                emitSpaceKey()
                log:i("토글+방향키 모드 Space: 일반 Space 입력")
            end
            return true
        end
        if state.isNavActive then
            stopNavMode()
            return true
        end
        if state.holdTimer then
            state.holdTimer:stop()
            state.holdTimer = nil
            emitSpaceKey()
            return true
        end
        return true
    end)
    if not ok then log:ef("spaceTap: %s", tostring(result)) end
    return result or false
end)
--------------------------------------------------------------------------------
-- 18. 초기화
--------------------------------------------------------------------------------
state.spaceTap:start()
state.navKeyTap:start()
log:i("네비모드 초기화 완료")
log:i("  - 좌측 Control 2연타로 토글 네비모드 진입/종료")
log:i("  - HUD 폰트 크기: 16px, 프레임 높이: 28px")
log:i("  - Shift+클릭 → rawFlags 방식으로 선택 영역 추가/확장")
log:i("  - 토글+방향키 모드에서 Space → 일반 Space 입력")
log:i("  - IJKL 40ms 딜레이 기반 방향키 전송")
log:i("  - - / = 키로 시스템 볼륨 조절 (5%씩, 내부 추적 방식)")
log:i("  - ★ 성능 최적화: 입력 소스 캐싱 (5초), 언어 캐싱 (0.5초), 브라우저 감지 캐싱 (0.3초)")
log:i("  - ★ 한영전환 안정성: 입력 소스 변경 간격 50ms 보장, 플래그 제거로 race condition 방지")
hs.alert.show("Hammerspoon 설정 적용 완료")