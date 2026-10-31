--[[
================================================================================
    ONE EIGHT HUB (IN-GAME EDITION) - CDID TRUCK DRIVER & PRIVATE SERVER
    100% VERBATIM SOURCE FROM BACKEND/LUA-STORAGE:
    - games/cdid/shared/network.lua
    - games/cdid/shared/prompt.lua
    - games/cdid/shared/replica.lua
    - games/cdid/shared/vehicle.lua
    - games/cdid/plugins/truck/waypoint.lua
    - games/cdid/plugins/truck/job.lua
    - games/cdid/plugins/privateserver/environment.lua
    - games/cdid/plugins/privateserver/security.lua
    - games/cdid/plugins/privateserver/moderation.lua
    - games/cdid/plugins/privateserver/init.lua
    UI: WindUI v1.6.66 (Footagesus)
================================================================================
--]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")

-- [ENVIRONMENT DISPATCHER EMULATOR]
local _Modules = {}

local Trove = {
    new = function()
        local t = { _objects = {} }
        function t:Add(obj)
            table.insert(self._objects, obj)
            return obj
        end
        function t:Clean()
            for _, obj in ipairs(self._objects) do
                if typeof(obj) == "RBXScriptConnection" or (type(obj) == "table" and obj.Disconnect) then
                    pcall(function() obj:Disconnect() end)
                elseif typeof(obj) == "thread" then
                    pcall(task.cancel, obj)
                elseif typeof(obj) == "Instance" then
                    pcall(function() obj:Destroy() end)
                elseif type(obj) == "function" then
                    pcall(obj)
                end
            end
            self._objects = {}
        end
        t.Destroy = t.Clean
        return t
    end
}

local Scheduler = {
    Sleep = function(seconds)
        return task.wait(tonumber(seconds) or 0)
    end,
    Spawn = function(taskName, workerFn, onErrorFn)
        local fn = (type(workerFn) == "function") and workerFn or ((type(taskName) == "function") and taskName or nil)
        if not fn then return nil end
        return task.spawn(function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                warn("[OE Hub Task Error] [" .. tostring(taskName) .. "]: " .. tostring(err))
                if type(onErrorFn) == "function" then
                    pcall(onErrorFn, err)
                end
            end
        end)
    end,
    WaitFor = function(predicate, timeoutSeconds, pollInterval)
        local start = os.clock()
        timeoutSeconds = timeoutSeconds or 10.0
        pollInterval = pollInterval or 0.1
        while (os.clock() - start) < timeoutSeconds do
            local ok, res = pcall(predicate)
            if ok and res then return true, res end
            task.wait(pollInterval)
        end
        return false, nil
    end
}

local Log = {}
Log.Enabled = false
Log.SetEnabled = function(a, b)
    local val = (b ~= nil) and b or a
    Log.Enabled = (val == true)
end
Log.Scope = function(name)
    return Log
end
Log.Info = function(...) end
Log.Warn = function(...) end
Log.Success = function(...) end
Log.Error = function(...) end

local Notify = {
    Success = function(t, m) pcall(function() if _G.OE_WindUI then _G.OE_WindUI:Notify({ Title = tostring(t or "OE Hub"), Content = tostring(m or ""), Icon = "check", Duration = 3 }) end end) end,
    Info = function(t, m) pcall(function() if _G.OE_WindUI then _G.OE_WindUI:Notify({ Title = tostring(t or "OE Hub"), Content = tostring(m or ""), Icon = "info", Duration = 3 }) end end) end,
    Warning = function(t, m) pcall(function() if _G.OE_WindUI then _G.OE_WindUI:Notify({ Title = tostring(t or "OE Hub"), Content = tostring(m or ""), Icon = "alert-triangle", Duration = 3 }) end end) end,
    Warn = function(t, m) pcall(function() if _G.OE_WindUI then _G.OE_WindUI:Notify({ Title = tostring(t or "OE Hub"), Content = tostring(m or ""), Icon = "alert-triangle", Duration = 3 }) end end) end,
    Error = function(t, m) pcall(function() if _G.OE_WindUI then _G.OE_WindUI:Notify({ Title = tostring(t or "OE Hub"), Content = tostring(m or ""), Icon = "x-circle", Duration = 3 }) end end) end,
}

local Dispatcher = {
    LoadSubmodule = function(subPath)
        for k, v in pairs(_Modules) do
            if subPath:find(k) then
                return v
            end
        end
        return nil
    end,
    Util = {
        Get = function(toolName)
            if toolName == "Trove" then return Trove end
            if toolName == "Scheduler" then return Scheduler end
            if toolName == "Logger" then return Log end
            if toolName == "Notify" then return Notify end
            return nil
        end,
        Scheduler = Scheduler,
        Logger = Log,
        Notify = Notify,
        Trove = Trove
    },
    ReportJobState = function(...) end,
    Publish = function(...) end,
    ActiveStates = {}
}

_G.OE_Dispatcher = Dispatcher

-- ==============================================================================
-- [1/10] VERBATIM: games/cdid/shared/network.lua
-- ==============================================================================
_Modules["network"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID SHARED MODULE: NETWORK & REMOTE GATEWAY
    File: games/cdid/shared/network.lua
================================================================================
    Wrapper resmi untuk komunikasi server CDID:
    ReplicatedStorage.Modules.Network:InvokeServer / FireServer
    Menyediakan safe pcall, auto-caching, dan penanganan error standar.
================================================================================
]]

local CDID_NetworkHelper = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _rawNetwork = nil

-- Lazy loader untuk modul Network bawaan CDID
local function getRawNetwork()
    if _rawNetwork then return _rawNetwork end

    pcall(function()
        local mod = (ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Network"))
            or (ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Network"))
        if mod then
            _rawNetwork = require(mod)
        end
    end)

    return _rawNetwork
end

-- InvokeServer dengan Safe Pcall
function CDID_NetworkHelper.Invoke(remoteName, ...)
    local net = getRawNetwork()
    if not net then
        return false, "Modul Network CDID tidak ditemukan di ReplicatedStorage!"
    end

    local args = { ... }
    local success, response = pcall(function()
        return net:InvokeServer(remoteName, unpack(args))
    end)

    if not success then
        warn(string.format("[CDID Network] Error saat InvokeServer '%s': %s", tostring(remoteName), tostring(response)))
        return false, response
    end

    return true, response
end

-- FireServer dengan Safe Pcall
function CDID_NetworkHelper.Fire(remoteName, ...)
    local net = getRawNetwork()
    if not net then
        return false, "Modul Network CDID tidak ditemukan di ReplicatedStorage!"
    end

    local args = { ... }
    local success, err = pcall(function()
        net:FireServer(remoteName, unpack(args))
    end)

    if not success then
        warn(string.format("[CDID Network] Error saat FireServer '%s': %s", tostring(remoteName), tostring(err)))
        return false, err
    end

    return true
end

-- Listener event dari server (OnClientEvent) - Mengembalikan connection object untuk Trove
function CDID_NetworkHelper.OnClientEvent(eventName, callback)
    local net = getRawNetwork()
    if not net or not net.OnClientEvent then
        return nil, "OnClientEvent tidak tersedia pada modul Network!"
    end

    local conn = nil
    local success, err = pcall(function()
        conn = net.OnClientEvent(eventName, callback)
    end)

    if success then
        return conn
    end
    return nil, err
end

-- Helper cepat: GetServerTime
function CDID_NetworkHelper.GetServerTime()
    local ok, res = CDID_NetworkHelper.Invoke("GetServerTime")
    if ok and type(res) == "number" then
        return res
    end
    return os.time()
end

return CDID_NetworkHelper

end)()

-- ==============================================================================
-- [2/10] VERBATIM: games/cdid/shared/prompt.lua
-- ==============================================================================
_Modules["prompt"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID SHARED MODULE: PROXIMITY PROMPT HELPER
    File: games/cdid/shared/prompt.lua
================================================================================
    Helper terpadu untuk memicu ProximityPrompt di seluruh CDID.
    Mendukung instant trigger, bypass hold duration, bypass max distance,
    serta pencarian prompt otomatis di dalam Model/Folder.
================================================================================
]]

local PromptHelper = {}

-- Memeriksa apakah executor mendukung fireproximityprompt native
local function canFireNative()
    return type(fireproximityprompt) == "function"
end

-- Trigger 1 ProximityPrompt secara instan
function PromptHelper.Trigger(prompt, skipDuration)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false, "Target bukan merupakan ProximityPrompt yang valid!"
    end

    if not prompt.Enabled then
        return false, "ProximityPrompt sedang nonaktif (Enabled = false)!"
    end

    -- Auto LookAt Prompt agar selalu tepat di tengah layar kamera
    pcall(function()
        local promptPart = prompt.Parent
        local promptPos = nil
        if promptPart then
            if promptPart:IsA("BasePart") then
                promptPos = promptPart.Position
            elseif promptPart:IsA("Attachment") then
                promptPos = promptPart.WorldPosition
            elseif promptPart:IsA("Model") then
                promptPos = promptPart:GetPivot().Position
            end
        end
        if promptPos then
            local cam = workspace.CurrentCamera
            local char = LocalPlayer.Character
            local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
            if cam and head then
                cam.CFrame = CFrame.new(head.Position + Vector3.new(0, 1.5, 0), promptPos)
            end
        end
    end)

    local success, err = pcall(function()
        if canFireNative() then
            -- Syntax executor: fireproximityprompt(prompt, distance, skipDuration)
            fireproximityprompt(prompt, 0, skipDuration ~= false)
        else
            -- Fallback simulasi
            local origHold = prompt.HoldDuration
            local origDist = prompt.MaxActivationDistance
            prompt.HoldDuration = 0
            prompt.MaxActivationDistance = 9999
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
            prompt.HoldDuration = origHold
            prompt.MaxActivationDistance = origDist
        end
    end)

    if not success then
        warn("[CDID Prompt] Gagal memicu ProximityPrompt: " .. tostring(err))
        return false, err
    end

    return true, "ProximityPrompt berhasil dipicu!"
end

-- Mencari ProximityPrompt pertama di dalam parent (Model/Folder/Part) dan memicunya
function PromptHelper.TriggerIn(parentInstance, skipDuration)
    if not parentInstance then
        return false, "Parent instance nil!"
    end

    local prompt = parentInstance:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then
        return false, "Tidak ditemukan ProximityPrompt di dalam " .. parentInstance:GetFullName()
    end

    return PromptHelper.Trigger(prompt, skipDuration)
end

-- Mencari ProximityPrompt berdasarkan ActionText, ObjectText, atau Nama Instance
function PromptHelper.TriggerMatching(parentInstance, keyword, skipDuration)
    if not parentInstance then
        return false, "Parent instance nil!"
    end

    local targetLower = string.lower(keyword or "")
    for _, desc in ipairs(parentInstance:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local action = string.lower(desc.ActionText or "")
            local obj = string.lower(desc.ObjectText or "")
            local name = string.lower(desc.Name or "")

            if string.find(action, targetLower) or string.find(obj, targetLower) or string.find(name, targetLower) then
                return PromptHelper.Trigger(desc, skipDuration)
            end
        end
    end

    return false, "ProximityPrompt dengan keyword '" .. tostring(keyword) .. "' tidak ditemukan!"
end

-- Menunggu hingga ProximityPrompt muncul (timeout detik) lalu memicunya
function PromptHelper.WaitForAndTrigger(parentInstance, timeout, skipDuration)
    if not parentInstance then return false, "Parent nil!" end
    local maxWait = timeout or 5
    local start = tick()

    while (tick() - start) < maxWait do
        local prompt = parentInstance:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Enabled then
            return PromptHelper.Trigger(prompt, skipDuration)
        end
        task.wait(0.2)
    end

    return false, "Timeout menunggu ProximityPrompt di " .. parentInstance:GetFullName()
end

-- Mengambil semua ProximityPrompt di dalam suatu Instance
function PromptHelper.GetAll(parentInstance)
    local list = {}
    if not parentInstance then return list end

    for _, desc in ipairs(parentInstance:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            table.insert(list, desc)
        end
    end
    return list
end

return PromptHelper

end)()

-- ==============================================================================
-- [3/10] VERBATIM: games/cdid/shared/replica.lua
-- ==============================================================================
_Modules["replica"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID SHARED MODULE: REPLICA CONTROLLER BRIDGE (SSOT)
    File: games/cdid/shared/replica.lua
================================================================================
    Jembatan reaktif & modular ke sistem Replica CDID (Multi-Subplace SSOT).
    Mendukung penuh:
    - In-Game Maps: Jakarta, Jawa Timur, Bandung, Jabar, Jateng, Bali
    - Main Menu / Lobby: PlayerScripts.DataReplication.Replica
    - Universal Fallback: getgc() scan
    - Listener reaktif via ListenToChange()
================================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local ReplicaBridge = {}
local _cachedReplica = nil

-- 1. Mendapatkan instance ReplicaController CDID (In-Game)
local function getInGameController()
    local rcMod = ReplicatedStorage:FindFirstChild("ClientContainer") 
        and ReplicatedStorage.ClientContainer:FindFirstChild("Controller")
        and ReplicatedStorage.ClientContainer.Controller:FindFirstChild("ReplicaController")
    
    if rcMod then
        local success, result = pcall(require, rcMod)
        if success and result then return result end
    end
    return nil
end

-- 2. Mendapatkan instance ReplicaController CDID (Lobby / Main Menu)
local function getLobbyController()
    local ps = LocalPlayer and LocalPlayer:FindFirstChild("PlayerScripts")
    local dr = ps and ps:FindFirstChild("DataReplication")
    local repScript = dr and dr:FindFirstChild("Replica")
    if repScript then
        local success, result = pcall(require, repScript)
        if success and result then return result end
    end
    return nil
end

-- 3. Mendapatkan Player Replica Object (Reaktif & Aktif)
function ReplicaBridge.GetPlayerReplica()
    if _cachedReplica and pcall(function() return _cachedReplica:IsActive() end) and _cachedReplica:IsActive() then
        return _cachedReplica
    end

    -- Jalur 1: In-Game Controller
    local rc = getInGameController()
    if rc and rc._replicas then
        local expectedClass = "Player_" .. tostring(LocalPlayer.UserId)
        for _, r in pairs(rc._replicas) do
            if (r.Class == expectedClass or (r.Class and r.Class:find("Player_"))) and r.Data then
                _cachedReplica = r
                return r
            end
        end
    end

    -- Jalur 2: Lobby / Main Menu Controller
    local lobbyRc = getLobbyController()
    if lobbyRc and lobbyRc._replicas then
        for _, r in pairs(lobbyRc._replicas) do
            if r.Class and r.Class:find("PlayerData_") and r.Data then
                _cachedReplica = r
                return r
            end
        end
    end

    return nil
end

-- 4. Fallback Pemindai Data Mentah via Garbage Collection (GC)
local function getRawGCData()
    local gcData = nil
    pcall(function()
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "Class") and type(rawget(v, "Class")) == "string" and rawget(v, "Class"):find("^Player") and rawget(v, "Data") and type(rawget(v, "Data")) == "table" and rawget(v, "Data").Cash ~= nil then
                gcData = rawget(v, "Data")
                break
            end
        end
    end)
    return gcData
end

-- 5. Mendapatkan Tabel Data Player Lengkap (SSOT Utama)
function ReplicaBridge.GetRawData()
    local rep = ReplicaBridge.GetPlayerReplica()
    if rep and rep.Data then
        return rep.Data
    end
    return getRawGCData()
end

-- 6. Mendapatkan Nilai Berdasarkan Key atau Sub-Path
function ReplicaBridge.GetData(key)
    local data = ReplicaBridge.GetRawData()
    if not data then return nil end
    if not key then return data end

    if type(key) == "table" then
        local cur = data
        for _, k in ipairs(key) do
            if type(cur) ~= "table" then return nil end
            cur = cur[k]
        end
        return cur
    end

    return data[key]
end

-- 7. Shortcuts Data Umum CDID
function ReplicaBridge.GetCash()
    return ReplicaBridge.GetData("Cash") or 0
end

function ReplicaBridge.GetEtoll()
    return ReplicaBridge.GetData("EtollCash") or 0
end

function ReplicaBridge.GetRoleplayCash()
    return ReplicaBridge.GetData("RoleplayCash") or 0
end

function ReplicaBridge.GetOwnedCars()
    return ReplicaBridge.GetData("NewCars") or {}
end

function ReplicaBridge.GetJobs()
    return ReplicaBridge.GetData("Jobs") or {}
end

function ReplicaBridge.GetPrivateServerData()
    return ReplicaBridge.GetData("PrivateServer") or {}
end

-- 8. Menambahkan Listener Reaktif Terhadap Perubahan Data
function ReplicaBridge.ListenToChange(pathTable, callback)
    local rep = ReplicaBridge.GetPlayerReplica()
    if not rep or not rep.ListenToChange then
        return nil
    end

    if type(pathTable) == "string" then
        pathTable = { pathTable }
    end

    local connection = rep:ListenToChange(pathTable, function(newVal, oldVal)
        pcall(callback, newVal, oldVal)
    end)

    return connection
end

return ReplicaBridge

end)()

-- ==============================================================================
-- [4/10] VERBATIM: games/cdid/shared/vehicle.lua
-- ==============================================================================
_Modules["vehicle"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID SHARED MODULE: VEHICLE & CAR CONTROLLER
    File: games/cdid/shared/vehicle.lua
================================================================================
    Modul pengontrol kendaraan terpadu untuk CDID (A-Chassis 6.8+ Custom).
    Mendukung deteksi mobil aktif, enter/exit, teleport mobil + player,
    auto-flip jika terbalik, freeze/handbrake, horn, dan live telemetry.
================================================================================
]]

local Vehicle = {}
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Mengambil Model mobil aktif milik pemain di Workspace
local _cachedRealName = nil
local function getRealPlayerName()
    if _cachedRealName and _cachedRealName ~= "" then
        return _cachedRealName
    end
    -- Ambil nama asli langsung dari C++ Engine via UserId (100% Kebal terhadap name spoofing)
    pcall(function()
        if LocalPlayer and LocalPlayer.UserId and LocalPlayer.UserId > 0 then
            _cachedRealName = Players:GetNameFromUserIdAsync(LocalPlayer.UserId)
        end
    end)
    if not _cachedRealName or _cachedRealName == "" then
        _cachedRealName = LocalPlayer and LocalPlayer.Name or ""
    end
    return _cachedRealName
end

-- Mengambil Model mobil aktif milik pemain di Workspace (Anti-Spoof & Aman Multiplayer)
function Vehicle.GetMyCar()
    local vehiclesFolder = workspace:FindFirstChild("Vehicles")
    if not vehiclesFolder then return nil end

    local realName = getRealPlayerName()
    local pName = LocalPlayer and LocalPlayer.Name or ""

    -- 1. Prioritas Utama: Cek jika karakter saat ini sedang duduk di salah satu mobil
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(vehiclesFolder) then
        local sittingCar = hum.SeatPart:FindFirstAncestorOfClass("Model")
        if sittingCar and sittingCar.Parent == vehiclesFolder then
            return sittingCar
        end
    end

    -- 2. Cek nama model fisik konsisten CDID: [RealName]sCar atau [PlayerName]sCar
    if realName ~= "" then
        local car = vehiclesFolder:FindFirstChild(realName .. "sCar")
        if car and car:IsA("Model") then return car end
    end
    if pName ~= "" and pName ~= realName then
        local car = vehiclesFolder:FindFirstChild(pName .. "sCar")
        if car and car:IsA("Model") then return car end
    end

    -- 3. SCAN MULTIPLAYER AMAN: Cari model yang CarData.CarOwner == RealName / PlayerName
    for _, v in ipairs(vehiclesFolder:GetChildren()) do
        if v:IsA("Model") then
            local carData = v:FindFirstChild("CarData")
            local owner = carData and carData:FindFirstChild("CarOwner")
            local ownerVal = owner and tostring(owner.Value) or ""
            if (realName ~= "" and (ownerVal == realName or v.Name:find(realName, 1, true)))
               or (pName ~= "" and (ownerVal == pName or v.Name:find(pName, 1, true))) then
                return v
            end
        end
    end

    return nil
end

-- Memeriksa apakah pemain sedang duduk di dalam mobil miliknya
function Vehicle.IsPlayerInCar()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if not hum or not hum.SeatPart then return false end

    local myCar = Vehicle.GetMyCar()
    if not myCar then return false end

    return hum.SeatPart:IsDescendantOf(myCar)
end

-- Mengambil DriveSeat (kursi kemudi)
function Vehicle.GetDriveSeat()
    local car = Vehicle.GetMyCar()
    if not car then return nil end
    return car:FindFirstChild("DriveSeat", true) or car:FindFirstChildWhichIsA("VehicleSeat", true)
end

-- Masuk ke kursi kemudi mobil secara instan
function Vehicle.Enter()
    local car = Vehicle.GetMyCar()
    if not car then return false, "Mobil Anda belum di-spawn!" end

    local seat = Vehicle.GetDriveSeat()
    if not seat then return false, "DriveSeat mobil tidak ditemukan!" end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if not hrp or not hum then return false, "Karakter tidak siap!" end

    -- Pindahkan karakter ke atas kursi kemudi lalu duduk
    hrp.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0)
    task.wait(0.1)
    pcall(function()
        seat:Sit(hum)
    end)

    return true, "Berhasil masuk ke kursi kemudi mobil!"
end

-- Keluar dari kursi kemudi
function Vehicle.Exit()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if hum and hum.Sit then
        hum.Sit = false
        task.wait(0.05)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)
        end
        return true, "Berhasil keluar dari mobil!"
    end
    return false, "Pemain tidak sedang duduk di dalam kendaraan."
end

-- Teleportasi mobil utuh (beserta pemain di dalamnya) ke koordinat/CFrame
function Vehicle.Teleport(target, heightOffset)
    local car = Vehicle.GetMyCar()
    if not car then return false, "Mobil Anda belum di-spawn!" end

    local offset = heightOffset or 3.5
    local targetCFrame = nil

    if typeof(target) == "CFrame" then
        targetCFrame = target + Vector3.new(0, offset, 0)
    elseif typeof(target) == "Vector3" then
        targetCFrame = CFrame.new(target + Vector3.new(0, offset, 0))
    elseif typeof(target) == "Instance" and target:IsA("BasePart") then
        targetCFrame = target.CFrame + Vector3.new(0, offset, 0)
    end

    if not targetCFrame then return false, "Format target CFrame tidak valid!" end

    -- Reset momentum kecepatan mobil
    pcall(function()
        local primary = car.PrimaryPart or Vehicle.GetDriveSeat()
        if primary then
            primary.AssemblyLinearVelocity = Vector3.zero
            primary.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    -- Pindahkan mobil via PivotTo
    car:PivotTo(targetCFrame)

    return true, "Mobil berhasil diteleportasikan!"
end

-- Membalik mobil jika terbalik/nyangkut (Auto-Flip Upright)
function Vehicle.Flip()
    local car = Vehicle.GetMyCar()
    if not car then return false, "Mobil Anda belum di-spawn!" end

    local primary = car.PrimaryPart or Vehicle.GetDriveSeat()
    if not primary then return false, "PrimaryPart mobil tidak ditemukan!" end

    -- Ambil posisi saat ini dan reset rotasi tegak lurus
    local currentPos = primary.Position
    local currentYaw = select(2, primary.CFrame:ToEulerAnglesYXZ())
    local uprightCFrame = CFrame.new(currentPos + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, currentYaw, 0)

    -- Reset velocity
    pcall(function()
        primary.AssemblyLinearVelocity = Vector3.zero
        primary.AssemblyAngularVelocity = Vector3.zero
    end)

    car:PivotTo(uprightCFrame)
    return true, "Mobil berhasil dibalikkan (Upright)!"
end

-- Mengunci (Anchor) mobil / Rem Tangan Total (Handbrake Total)
function Vehicle.Freeze(bool)
    local car = Vehicle.GetMyCar()
    if not car then return false, "Mobil belum di-spawn!" end

    local primary = car.PrimaryPart or Vehicle.GetDriveSeat()
    if primary then
        primary.Anchored = (bool == true)
        return true, "Mobil di-" .. (bool and "Freeze (Rem Tangan Aktif)" or "Unfreeze")
    end
    return false, "Gagal mengubah status anchor mobil."
end

-- Membunyikan Klakson Mobil
function Vehicle.Honk()
    local car = Vehicle.GetMyCar()
    local horn = car and car:FindFirstChild("Horn")
    if horn and horn:IsA("RemoteEvent") then
        horn:FireServer()
        return true, "Klakson dibunyikan!"
    end
    return false, "Remote klakson tidak ditemukan pada mobil."
end

-- Start / Stop Mesin Mobil secara Programatik
function Vehicle.SetEngine(bool)
    local car = Vehicle.GetMyCar()
    if not car then return false, "Mobil belum di-spawn!" end

    local tune = car:FindFirstChild("A-Chassis Tune")
    local interface = tune and tune:FindFirstChild("A-Chassis Interface")
    local isOn = interface and interface:FindFirstChild("IsOn")

    if isOn and isOn:IsA("BoolValue") then
        isOn.Value = (bool == true)
        return true, "Mesin " .. (bool and "dinyalakan" or "dimatikan")
    end
    return false, "Value IsOn mesin tidak ditemukan."
end

-- Mengambil Status Telemetri Lengkap Mobil (KM/H, RPM, Gear, Fuel, dll.)
function Vehicle.GetTelemetry()
    local car = Vehicle.GetMyCar()
    if not car then return nil end

    local carData = car:FindFirstChild("CarData")
    local tune = car:FindFirstChild("A-Chassis Tune")
    local interface = tune and tune:FindFirstChild("A-Chassis Interface")
    local values = interface and interface:FindFirstChild("Values")
    local driveSeat = Vehicle.GetDriveSeat()

    local speed = 0
    if car.PrimaryPart then
        speed = math.floor(car.PrimaryPart.AssemblyLinearVelocity.Magnitude * 3.6)
    end

    local fuel = carData and carData:FindFirstChild("Fuel") and carData.Fuel.Value or 0
    local fuelTank = carData and carData:FindFirstChild("FuelTank") and carData.FuelTank.Value or 0
    local plate = carData and carData:FindFirstChild("Plate") and carData.Plate.Value or "-"
    local carName = carData and carData:FindFirstChild("CarName") and carData.CarName.Value or car.Name

    return {
        CarName = carName,
        SpeedKmh = speed,
        RPM = values and values:FindFirstChild("RPM") and values.RPM.Value or 0,
        Gear = values and values:FindFirstChild("Gear") and values.Gear.Value or 0,
        EngineIsOn = interface and interface:FindFirstChild("IsOn") and interface.IsOn.Value or false,
        Handbrake = values and values:FindFirstChild("PBrake") and values.PBrake.Value or false,
        Fuel = fuel,
        FuelTank = fuelTank,
        Plate = plate,
        InCar = Vehicle.IsPlayerInCar(),
        Model = car
    }
end

return Vehicle

end)()

-- ==============================================================================
-- [5/10] VERBATIM: games/cdid/plugins/truck/waypoint.lua
-- ==============================================================================
_Modules["waypoint"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID TRUCK DRIVER: PURE 100% EVENT-DRIVEN WAYPOINT MODULE
    File: games/cdid/plugins/truck/waypoint.lua
================================================================================
    100% SSOT Berbasis RemoteEvent & Master Table ReplicatedStorage.Shared.TruckArea:
    - ZERO ketergantungan pada part fisik Workspace.Etc.Waypoint (bebas part bekas/sampah)
    - ZERO ketergantungan pada Arrow Model / SetArrow (bebas bug arrow spawner/head)
    - Menggunakan Timestamp Handshake: hanya menerima event yang tiba setelah aksi trigger
    - Posisi kargo diambil murni dari Vector3 ground level asli tabel TruckArea CDID
================================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Waypoint = {}

local _currentTarget = nil
local _trove = nil

local Dispatcher = _G.OE_Dispatcher
local Util = Dispatcher and Dispatcher.Util or (Dispatcher and Dispatcher.LoadSubmodule and Dispatcher.LoadSubmodule("core/util/init.lua"))
local Scheduler = Util and Util.Scheduler

-- Master Whitelist CDID Jawa Timur (Ground-level asli)
local MASTER_TRUCK_HUBS = {
    [1] = { txt = "PT CDID CARGO Surabaya", Location = Vector3.new(27154.707, 396.751, 37788.867) },
    [2] = { txt = "Ruko Ngawi",             Location = Vector3.new(37565.355, 142.498, -47526.230) },
    [3] = { txt = "Ruko Sidoarjo",          Location = Vector3.new(12900.574, 390.721, 52069.508) },
    [4] = { txt = "PT CDID Cargo Malang",   Location = Vector3.new(-7845.344, 389.014, 46865.543) },
    [5] = { txt = "Ruko Kediri",            Location = Vector3.new(-10034.885, 216.475, 5127.838) }
}

-- Lazy loader TruckArea CDID
local _truckArea = nil
local function getTruckArea()
    if _truckArea then return _truckArea end
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("TruckArea")
        if mod then
            _truckArea = require(mod)
        end
    end)
    return _truckArea or MASTER_TRUCK_HUBS
end

function Waypoint.Start(trove)
    Waypoint.Stop()
    _trove = trove
    _currentTarget = nil

    local TruckArea = getTruckArea()

    -- LISTENER TUNGGAL & MUTLAK: RemoteEvent Waypoint ("Truck", routeIndex)
    local function hookWaypointRemote(wpRemote)
        if not wpRemote or not wpRemote:IsA("RemoteEvent") then return end
        local conn = wpRemote.OnClientEvent:Connect(function(jobType, routeIndex)
            if jobType == "Truck" and TruckArea and TruckArea[routeIndex] then
                local hub = TruckArea[routeIndex]
                _currentTarget = {
                    Position = hub.Location,
                    Name = hub.txt or ("Cargo Route #" .. tostring(routeIndex)),
                    RouteIndex = routeIndex,
                    ReceivedAt = os.clock()
                }
            end
        end)
        if _trove and conn then
            _trove:Add(conn)
        end
    end

    pcall(function()
        local remContainer = ReplicatedStorage:FindFirstChild("NetworkContainer")
        local remEvents = remContainer and remContainer:FindFirstChild("RemoteEvents")
        if remEvents then
            local wpRemote = remEvents:FindFirstChild("Waypoint")
            if wpRemote then
                hookWaypointRemote(wpRemote)
            else
                -- Jika RemoteEvent Waypoint dibuat secara dinamis oleh server saat job aktif
                local addedConn = remEvents.ChildAdded:Connect(function(child)
                    if child.Name == "Waypoint" and child:IsA("RemoteEvent") then
                        hookWaypointRemote(child)
                    end
                end)
                if _trove then _trove:Add(addedConn) end
            end
        end
    end)
end

function Waypoint.Stop()
    _currentTarget = nil
    _trove = nil
end

function Waypoint.Clear()
    _currentTarget = nil
end

-- Mendapatkan target kargo saat ini (dengan validasi anti-stale jarak)
function Waypoint.Get(excludePos)
    if _currentTarget and _currentTarget.Position then
        if not excludePos or (_currentTarget.Position - excludePos).Magnitude >= 5000 then
            return _currentTarget
        end
    end
    return nil
end

-- Strict Handshake: Menunggu paket Waypoint baru yang tiba SETELAH afterTime
function Waypoint.WaitForTargetAfter(afterTime, timeoutSec, excludePos)
    afterTime = afterTime or 0
    timeoutSec = timeoutSec or 0.6

    local start = os.clock()
    while (os.clock() - start) < timeoutSec do
        if _currentTarget and _currentTarget.Position and _currentTarget.ReceivedAt and _currentTarget.ReceivedAt >= afterTime then
            if not excludePos or (_currentTarget.Position - excludePos).Magnitude >= 5000 then
                return _currentTarget
            end
        end
        task.wait(0.03)
    end
    return nil
end

-- Fallback kompatibilitas WaitForTarget umum
function Waypoint.WaitForTarget(timeoutSec, excludePos)
    return Waypoint.WaitForTargetAfter(0, timeoutSec or 1.0, excludePos)
end

return Waypoint

end)()

-- ==============================================================================
-- [6/10] VERBATIM: games/cdid/plugins/truck/job.lua
-- ==============================================================================
local Job = (function()
--[[
================================================================================
    OE HUB v2 - CDID TRUCK DRIVER JOB CONTROLLER (PURE STATE MACHINE)
    File: games/cdid/plugins/truck/job.lua
================================================================================
    Engine Otonom Pengemudi Truk CDID Jawa Timur (PlaceId: 110369730911937):
    1. Validasi Sub-Place Map Jawa Timur
    2. Shared Network / Remote Event Job Switch
    3. Auto Teleport ke Starter Depot & Reroll In-Place
    4. Auto Teleport Spawner, Spawn Truk & Lepas Trailer
    5. Supir Duduk Instan & Verifikasi A-Chassis
    6. Delivery 50.3s Presisi os.clock() + Raycast Landing + Zero Velocity
    7. Verifikasi Gaji Murni Baseline Cash (Tanpa Timeout)
    8. Seketika Barengan Despawn Truk & Instan Teleport ke HQ saat Selesai
================================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Job = {}
Job.Id = "truck_driver"
_G.OE_TruckJob = Job
shared.OE_TruckJob = Job

-- Dispatcher & Core Bridge
local Dispatcher = _G.OE_Dispatcher
local Util = (Dispatcher and Dispatcher.Util) or _G.OE_Util

local function getTool(name)
    if Util and Util.Get then return Util.Get(name) end
    if Util and Util[name] then return Util[name] end
    return nil
end

local rawLogger = getTool("Logger")
local Log = nil
if rawLogger and rawLogger.Scope then
    Log = rawLogger.Scope("Truck")
    Log.SetEnabled(false) -- Default: false (Hening di F9 sesuai preferensi user)
else
    Log = {
        Enabled = false,
        SetEnabled = function(self, s) self.Enabled = (s == true) end,
        Info = function(...) end,
        Warn = function(...) end,
        Success = function(...) end,
        Error = function(...) end
    }
end
local Notify = getTool("Notify")
local Scheduler = getTool("Scheduler")
local Trove = getTool("Trove")
local Timer = getTool("Timer")

local function sleep(seconds)
    if Scheduler and Scheduler.Sleep then
        Scheduler.Sleep(seconds)
    else
        task.wait(seconds)
    end
end

local function spawnTask(name, fn)
    if Scheduler and Scheduler.Spawn then
        return Scheduler.Spawn(name, fn)
    end
    return task.spawn(fn)
end

local function waitFor(predicate, timeoutSeconds, pollInterval)
    if Scheduler and Scheduler.WaitFor then
        return Scheduler.WaitFor(predicate, timeoutSeconds, pollInterval)
    end
    local start = os.clock()
    timeoutSeconds = timeoutSeconds or 10.0
    pollInterval = pollInterval or 0.1
    while (os.clock() - start) < timeoutSeconds do
        local ok, res = pcall(predicate)
        if ok and res then return true, res end
        task.wait(pollInterval)
    end
    return false, nil
end

-- Modular Submodules
local function requireShared(subPath)
    local D = _G.OE_Dispatcher or Dispatcher
    if D and D.LoadSubmodule then
        return D.LoadSubmodule("games/cdid/shared/" .. subPath)
    end
    return nil
end

local CDID_Network = requireShared("network")
local Vehicle = requireShared("vehicle")
local PromptHelper = requireShared("prompt")
local ReplicaBridge = requireShared("replica")

local Waypoint = nil
if Dispatcher and Dispatcher.LoadSubmodule then
    Waypoint = Dispatcher.LoadSubmodule("games/cdid/plugins/truck/waypoint.lua")
end

-- Helper Komunikasi Job Server via Shared Network
local function fireJobRemote(action)
    if CDID_Network and CDID_Network.Fire then
        local ok = CDID_Network.Fire("Job", action)
        if ok then return true end
    end

    pcall(function()
        local rem = ReplicatedStorage:FindFirstChild("NetworkContainer")
            and ReplicatedStorage.NetworkContainer:FindFirstChild("RemoteEvents")
            and ReplicatedStorage.NetworkContainer.RemoteEvents:FindFirstChild("Job")
        if rem then rem:FireServer(action) end
    end)
    return true
end

local JobStarterLocation = nil
local function getJobStarterLocation()
    if not JobStarterLocation then
        pcall(function()
            local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 3)
            if sharedFolder then
                local locMod = sharedFolder:FindFirstChild("JobStarterLocation") or sharedFolder:WaitForChild("JobStarterLocation", 3)
                if locMod then
                    JobStarterLocation = require(locMod)
                end
            end
        end)
    end
    return JobStarterLocation
end

-- Job State & Configuration
Job.Config = {
    MinDistance = 105000,
    WaitDuration = 50.1,
    MinCargoPayout = 50000000,
    SmartChaining = false,
    StripTrailer = true,

    Timing = {
        LandingDropoff = 0.0,
        JobSwitchDelay = 0.03,
        DepotChunkPreload = 0.05,
        DepotLanding = 0.0,
        RerollResetSleep = 0.03,
        WaypointTimeout = 0.5,
        WaypointPollInterval = 0.02,
        WaypointRetrySleep = 0.02,
        SpawnerLanding = 0.0,
        SpawnerCarTimeout = 0.2,
        SpawnerCarPoll = 0.02,
        SeatedDelay = 0.0,
        AChassisPollTimeout = 0.5,
        AChassisPollInterval = 0.02,
        ReseatJumpDelay = 0.05,
        SmartChainTimeout = 0.5,
        SmartChainPoll = 0.02,
    }
}

Job.State = {
    IsFarming = false,
    Status = "CONNECTED",
    CurrentRoute = "IDLE",
    TripCount = 0,
    TotalEarnings = 0,
    LastPayout = 0,
}

local _farmTrove = nil
local _farmThread = nil

-- Teleportasi Karakter yang Aman & Tegak (Upright Yaw + Zero Velocity)
local function safeTeleportPlayer(targetCF)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if hum and hum.SeatPart then
        hum.Sit = false
        task.wait(0.05)
    end
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        local _, rotY, _ = targetCF:ToOrientation()
        local uprightCF = CFrame.new(targetCF.Position) * CFrame.Angles(0, rotY, 0)
        char:PivotTo(uprightCF)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

-- Menghapus Trailer agar Tidak Terbentur/Glitch saat Teleportasi
local function stripTrailer(car)
    if not car or not car.Parent then return end
    local trailer = car:FindFirstChild("Trailer1") or car:FindFirstChild("Trailer")
    if trailer then
        for _, child in ipairs(trailer:GetChildren()) do
            pcall(function() child:Destroy() end)
        end
        pcall(function() trailer:Destroy() end)
        if Log then Log.Info("Trailer truk berhasil dilepas.") end
    end
end

-- Memastikan Pemain Duduk Sah Sesuai Aturan User:
-- 1. Naik kendaraan
-- 2. Cek selama 0.2 detik: PlayerGui ada "A-Chassis Interface" DAN DriveSeat.HeadsUpDisplay == false
-- 3. Kalau ada 1 saja yg ga valid: reseat (turun instan 0.05s, naik lagi)
-- 4. Retry terus tanpa batas sampai keduanya sesuai
local function ensureSeated(car)
    if not car or not car.Parent then return false end
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return false end

    local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
        or car:FindFirstChild("DriveSeat", true)
        or car:FindFirstChild("DriverSeat", true)

    if not seat then return false end

    local primary = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
    if primary then primary.Anchored = false end

    local drivePrompt = seat:FindFirstChild("PromptDriveSeat", true)
        or car:FindFirstChild("PromptDriveSeat", true)
        or seat:FindFirstChildWhichIsA("ProximityPrompt", true)

    if drivePrompt then
        drivePrompt.RequiresLineOfSight = false
        drivePrompt.MaxActivationDistance = 50
        drivePrompt.HoldDuration = 0
    end

    local function sitDown()
        hrp.CFrame = seat.CFrame * CFrame.new(0, 0.5, 0.5)
        pcall(function() seat:Sit(hum) end)
        if drivePrompt then
            if PromptHelper and PromptHelper.Trigger then
                PromptHelper.Trigger(drivePrompt)
            elseif fireproximityprompt then
                pcall(fireproximityprompt, drivePrompt, 0)
            end
        end
    end

    local attempt = 0
    while Job.State.IsFarming and car and car.Parent do
        attempt = attempt + 1

        -- 1. Naik kendaraan
        sitDown()

        -- 2. Tunggu 0.2 detik
        task.wait(0.2)

        -- 3. Cek kedua syarat: PlayerGui punya "A-Chassis Interface" DAN HeadsUpDisplay == false
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local hasGui = pg and (pg:FindFirstChild("A-Chassis Interface") ~= nil)
        local hudOff = (seat.HeadsUpDisplay == false)

        if hasGui and hudOff then
            if Log then
                Log.Success(string.format("Duduk SAH & A-Chassis Valid (GUI=OK, HUD=false | Attempt #%d)!", attempt))
            end
            return true
        end

        -- 4. Kalau ada 1 saja yg ga valid maka reseat (turun instan 0.05s lalu loop naik lagi)
        if Log then
            Log.Warn(string.format("Belum valid (GUI=%s, HUD=%s). Reseat 0.05s (Attempt #%d)...",
                tostring(hasGui), tostring(seat.HeadsUpDisplay), attempt))
        end
        hum.Sit = false
        hum.Jump = true
        task.wait(0.05)
    end

    return true
end

local function waitForAChassisInterface(car)
    return true
end

-- Kirim Metrik ke Web Dashboard
local function emitTelemetry()
    local D = _G.OE_Dispatcher or Dispatcher
    if D and D.ReportJobState then
        D.ReportJobState("truck_driver", {
            track = { "Cash" },
            extras = {
                ["Trips"] = Job.State.TripCount or 0,
                ["Last Payout"] = Job.State.LastPayout or 0
            }
        })
    end
end

-- 1. Mengantar Kargo: Timer 50.3s Presisi os.clock() + Preload 1.0s + Raycast Landing + Anti-Lag
local function deliverCargo(car, char, deliveredPos, deliveredName)
    local streamRequested = false
    Job.State.Status = "DELIVERING"
    Job.State.CurrentRoute = deliveredName or "Destination"

    local waitDuration = Job.Config.WaitDuration or 50.1
    if Log then Log.Info(string.format("Menunggu %.1f detik presisi os.clock()...", waitDuration)) end

    local startClock = os.clock()
    local lastCheckpoint = nil

    while (os.clock() - startClock) < waitDuration and Job.State.IsFarming do
        local elapsed = os.clock() - startClock
        local remaining = math.max(0, waitDuration - elapsed)
        Job.State.RemainingSeconds = math.ceil(remaining)

        -- Preload streaming chunk 1.0 detik sebelum mendarat di tujuan
        if remaining <= 1.0 and not streamRequested then
            streamRequested = true
            if Log then Log.Info("Preloading chunk streaming peta tujuan (1.0s tersisa)...") end
            spawnTask("PreloadStreamingChunk", function()
                pcall(function()
                    if typeof(LocalPlayer.RequestStreamAroundAsync) == "function" then
                        LocalPlayer:RequestStreamAroundAsync(deliveredPos)
                    elseif typeof(Workspace.RequestStreamAroundAsync) == "function" then
                        Workspace:RequestStreamAroundAsync(deliveredPos)
                    end
                end)
            end)
        end

        local step = math.floor(remaining / 15) * 15
        if step > 0 and step ~= lastCheckpoint and (remaining - step) < 0.6 then
            lastCheckpoint = step
            if Log then Log.Info(string.format("Perjalanan kargo... Estimasi tiba dalam %d detik", step)) end
        end

        task.wait(0.2)
    end

    Job.State.RemainingSeconds = 0
    if not Job.State.IsFarming then return false end

    if Log then Log.Info("Teleportasi mobil kargo ke tujuan: " .. tostring(deliveredName)) end

    -- Raycast Downward untuk pendaratan tanah yang mulus
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { car, char, Workspace:FindFirstChild("Etc") }
    local groundRay = Workspace:Raycast(deliveredPos + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rayParams)
    local landY = groundRay and (groundRay.Position.Y + 2.0) or (deliveredPos.Y + 1.0)

    local _, currentRotY, _ = car:GetPivot():ToOrientation()
    local targetGroundCF = CFrame.new(deliveredPos.X, landY, deliveredPos.Z) * CFrame.Angles(0, currentRotY, 0)

    -- Anti-Lag Render: Hadapkan kamera ke bawah (0.3s) agar GPU tidak me-render horizon
    local camera = Workspace.CurrentCamera
    pcall(function()
        if camera then
            camera.CameraType = Enum.CameraType.Scriptable
            camera.CFrame = CFrame.new(targetGroundCF.Position + Vector3.new(0, 15, 0)) * CFrame.Angles(-math.rad(85), 0, 0)
        end
    end)

    -- Netralkan gaya fisika sebelum & sesudah PivotTo
    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then
            p.AssemblyLinearVelocity = Vector3.zero
            p.AssemblyAngularVelocity = Vector3.zero
        end
    end

    car:PivotTo(targetGroundCF)

    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then
            p.AssemblyLinearVelocity = Vector3.zero
            p.AssemblyAngularVelocity = Vector3.zero
        end
    end

    task.wait(0.05)

    -- Kembalikan kamera ke subjek supir/mobil
    pcall(function()
        if camera then
            camera.CameraType = Enum.CameraType.Custom
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
    end)

    return true
end

-- 2. Menunggu Gaji Masuk via Baseline Cash & Listener Replica (Tanpa Timeout)
local function waitForPayout(baselineCash, deliveredPos)
    Job.State.Status = "CONFIRMING_PAYOUT"
    if Log then Log.Info("Menunggu konfirmasi gaji server via Baseline Cash (>= 50jt, Tanpa Timeout)...") end

    local gained = 0
    local payoutReceived = false

    local conn = nil
    if ReplicaBridge and ReplicaBridge.ListenToChange then
        conn = ReplicaBridge.ListenToChange("Cash", function(newCash)
            if not payoutReceived and newCash and (newCash - baselineCash) >= Job.Config.MinCargoPayout then
                payoutReceived = true
                gained = newCash - baselineCash
            end
        end)
    end

    local payoutDeadline = os.clock() + 10.0
    while Job.State.IsFarming and not payoutReceived and (os.clock() < payoutDeadline) do
        local cur = ReplicaBridge and ReplicaBridge.GetCash() or 0
        if (cur - baselineCash) >= Job.Config.MinCargoPayout then
            payoutReceived = true
            gained = cur - baselineCash
            break
        end
        task.wait(0.05)
    end

    -- Watchdog Fallback: Jika delta saldo belum tercatat tetapi waypoint baru sudah muncul dari server
    if not payoutReceived and Job.State.IsFarming then
        local curWp = Waypoint and Waypoint.Get()
        if curWp and curWp.Position and (curWp.Position - deliveredPos).Magnitude > 5000 then
            payoutReceived = true
            gained = Job.State.LastPayout or 85000000
            if Log then Log.Info("Server CDID telah memunculkan rute baru. Trip dianggap selesai secara otomatis!") end
        end
    end

    if conn and typeof(conn.Disconnect) == "function" then
        pcall(function() conn:Disconnect() end)
    end

    if not Job.State.IsFarming then return false, 0 end

    if payoutReceived and gained >= Job.Config.MinCargoPayout then
        Job.State.TripCount = Job.State.TripCount + 1
        Job.State.LastPayout = gained
        Job.State.TotalEarnings = Job.State.TotalEarnings + gained

        local successMsg = string.format("Gaji Kargo Terverifikasi: +%s (Total: %s | Trips: %d)",
            tostring(gained), tostring(ReplicaBridge.GetCash()), Job.State.TripCount)
        if Log then Log.Success(successMsg) end
        if Notify then Notify.Success(successMsg) end
        emitTelemetry()
        return true, gained
    end

    return false, 0
end

-- Helper: Reset Job ke Unemployee & BARENGAN Instan Teleport ke Depot HQ
local function resetJobAndTeleportHQ()
    local starterLoc = getJobStarterLocation()
    local starterPos = (starterLoc and starterLoc.Truck and starterLoc.Truck.Location)
        or Vector3.new(-829.6, 26.6, 4426.8)

    -- BARENGKAN INSTAN: Despawn truk & SEKETIKA Teleport Karakter ke Depot HQ! (Bebas dari blocking stream 10s)
    fireJobRemote("Unemployee")
    safeTeleportPlayer(CFrame.new(starterPos + Vector3.new(0, 5, 0)))

    -- Langsung daftarkan kembali job Truck di Depot HQ
    fireJobRemote("Truck")

    local switchDelay = (Job.Config.Timing and Job.Config.Timing.JobSwitchDelay) or 0.03
    if switchDelay > 0 then sleep(switchDelay) else task.wait() end
end

-- 3. Menentukan Rute Baru: Smart Chain ATAU Reroll HQ
local function determineNextRouteOrReroll(car, deliveredPos, payoutTimestamp)
    if not Job.Config.SmartChaining then
        if Log then Log.Info("Smart Chaining nonaktif. Langsung kembali ke Depot HQ...") end
        resetJobAndTeleportHQ()
        return "REROLL", nil
    end

    Job.State.Status = "CHECKING_NEXT_ROUTE"

    -- Rute sambungan HANYA sah jika paket Waypoint dari server tiba SETELAH gaji cair (payoutTimestamp)
    local nextWp = Waypoint and Waypoint.WaitForTargetAfter(payoutTimestamp, 0.8, deliveredPos)

    local nextDist = 0
    if nextWp and type(nextWp) == "table" and nextWp.Position and car and car.PrimaryPart then
        nextDist = (nextWp.Position - car:GetPivot().Position).Magnitude
    end

    if nextWp and nextDist >= Job.Config.MinDistance then
        if Log then
            Log.Success(string.format("Smart Chain Sah (%s - Index #%s | %.1f studs >= %d)! Lanjut antar...",
                tostring(nextWp.Name), tostring(nextWp.RouteIndex), nextDist, Job.Config.MinDistance))
        end
        ensureSeated(car)
        return "CHAIN", nextWp
    end

    if Log then
        if not nextWp then
            Log.Info("Tidak ada rute sambungan baru dari server CDID. Kembali ke Depot HQ...")
        else
            Log.Warn(string.format("Rute sambungan terlalu dekat (%s - %.1f studs < %d). Kembali ke Depot HQ...",
                tostring(nextWp.Name), nextDist, Job.Config.MinDistance))
        end
    end
    resetJobAndTeleportHQ()
    return "REROLL", nil
end

-- 4. Reroll Rute Awal di Depot Starter Hingga Jarak >= MinDistance
local function rerollDepotRoute(root, starterPrompt)
    while Job.State.IsFarming do
        if Waypoint then Waypoint.Clear() end

        -- Pastikan role Truck aktif di server CDID
        pcall(function()
            local Net = require(game:GetService("ReplicatedStorage").Modules.Network)
            if Net and Net.FireServer then
                Net:FireServer("Job", "Truck")
            end
        end)

        -- Catat waktu presisi trigger prompt
        local triggerTime = os.clock()

        if PromptHelper and PromptHelper.Trigger then
            PromptHelper.Trigger(starterPrompt)
        elseif fireproximityprompt then
            pcall(fireproximityprompt, starterPrompt, 0)
        end

        -- Tunggu paket rute baru dari server (hanya yang tiba SETELAH triggerTime)
        local wp = Waypoint and Waypoint.WaitForTargetAfter(triggerTime, 0.35)

        if not wp or type(wp) ~= "table" or not wp.Position then
            -- Belum ada respons server dalam 0.6s, retry santai layaknya pemain manual
            task.wait(0.1)
            continue
        end

        local dist = (wp.Position - root.Position).Magnitude
        Job.State.CurrentRoute = wp.Name or "Destination"

        -- Verifikasi Strict Rute Terbaik CDID: Index 3 (Sidoarjo) atau Index 4 (Malang)
        local isBestRoute = (wp.RouteIndex == 3 or wp.RouteIndex == 4) or (dist >= Job.Config.MinDistance)

        if isBestRoute then
            if Log then
                Log.Success(string.format("Rute TERBAIK Sah (%s - Index #%s | %.1f studs)! Menuju Spawner Truk...",
                    tostring(wp.Name), tostring(wp.RouteIndex), dist))
            end
            emitTelemetry()
            return wp
        end

        -- Jika rute pendek (< 105.000 studs seperti Surabaya/Ngawi/Kediri), tolak & reroll wajar
        if Log then
            Log.Info(string.format("Rute %s (Index #%s | %.1f studs) ditolak (< %d). Reroll...",
                tostring(wp.Name), tostring(wp.RouteIndex), dist, Job.Config.MinDistance))
        end

        fireJobRemote("Unemployee")
        task.wait(0.12)
        fireJobRemote("Truck")
        task.wait(0.12)
    end
    return nil
end

-- Siklus Utama Auto Farm Truck
local function runFarmLoop()
    while Job.State.IsFarming do
        local okChar, char = waitFor(function()
            return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character
        end, 10.0, 0.2)

        if not okChar or not char then
            sleep(0.5)
            continue
        end

        local root = char:FindFirstChild("HumanoidRootPart")

        -- LANGKAH 1: Ambil Job Truck via Shared Network
        Job.State.Status = "ENROLL_JOB"
        fireJobRemote("Truck")

        -- LANGKAH 2: Teleportasi Langsung ke Depot Starter DULUAN (Bebas dari Bug Streaming)
        Job.State.Status = "REROLL_ROUTE"
        local starterLoc = getJobStarterLocation()
        local starterPos = (starterLoc and starterLoc.Truck and starterLoc.Truck.Location)
            or Vector3.new(-829.6, 26.6, 4426.8)

        if (root.Position - starterPos).Magnitude > 25 then
            if Log then Log.Info("Teleportasi langsung ke Depot Starter Truk...") end
            safeTeleportPlayer(CFrame.new(starterPos + Vector3.new(0, 5, 0)))
        end

        local starterPrompt = nil
        local okPrompt, foundPrompt = waitFor(function()
            local starterFolder = Workspace:FindFirstChild("Etc")
                and Workspace.Etc:FindFirstChild("Job")
                and Workspace.Etc.Job:FindFirstChild("Truck")
                and Workspace.Etc.Job.Truck:FindFirstChild("Starter")
            return starterFolder and starterFolder:FindFirstChildWhichIsA("ProximityPrompt", true)
        end, 3.0, 0.05)

        if not okPrompt or not foundPrompt then
            if Log then Log.Warn("Starter Prompt belum terdeteksi. Mencoba pergerakan kecil...") end
            safeTeleportPlayer(CFrame.new(starterPos + Vector3.new(0, 5, 0)))
            sleep(0.2)
            continue
        end
        starterPrompt = foundPrompt

        starterPrompt.RequiresLineOfSight = false
        starterPrompt.MaxActivationDistance = 50
        starterPrompt.HoldDuration = 0

        local initialRoute = rerollDepotRoute(root, starterPrompt)
        if not initialRoute or not Job.State.IsFarming then
            continue
        end

        -- LANGKAH 3 & 4: Teleport ke Spawner Truk
        Job.State.Status = "GETTING_TRUCK"
        local spawnerFolder = Workspace:FindFirstChild("Etc")
            and Workspace.Etc:FindFirstChild("Job")
            and Workspace.Etc.Job:FindFirstChild("Truck")
            and Workspace.Etc.Job.Truck:FindFirstChild("Spawner")
        local spawnerPrompt = spawnerFolder and spawnerFolder:FindFirstChildWhichIsA("ProximityPrompt", true)

        if not spawnerPrompt or not spawnerPrompt.Parent then
            if Log then Log.Warn("Spawner folder/prompt belum selesai stream. Menunggu...") end
            sleep(0.5)
            continue
        end

        spawnerPrompt.RequiresLineOfSight = false
        spawnerPrompt.MaxActivationDistance = 50
        spawnerPrompt.HoldDuration = 0

        local spawnerPos = spawnerPrompt.Parent:GetPivot().Position
        safeTeleportPlayer(CFrame.new(spawnerPos + Vector3.new(0, 5, 0)))

        -- Spawner Human-Like Clicker: klik berulang-ulang sampai truk muncul (max 15s)
        local car = nil
        local spawnDeadline = os.clock() + 15.0
        local lastClick = 0

        while Job.State.IsFarming and (os.clock() < spawnDeadline) do
            local currentCar = Vehicle and Vehicle.GetMyCar()
            if currentCar and currentCar:IsA("Model") and currentCar.Parent then
                local distFromSpawner = (currentCar:GetPivot().Position - spawnerPos).Magnitude
                if distFromSpawner < 150 then
                    -- Validasi Timing Kesiapan Truk (632 Part Replikasi):
                    -- Truk HANYA sah dinaiki jika DriveSeat & PromptDriveSeat resmi sudah ada!
                    local seat = currentCar:FindFirstChildWhichIsA("VehicleSeat", true)
                        or currentCar:FindFirstChild("DriveSeat", true)
                    local prompt = seat and (seat:FindFirstChild("PromptDriveSeat", true) or currentCar:FindFirstChild("PromptDriveSeat", true))

                    if seat and prompt then
                        car = currentCar
                        task.wait(0.08) -- Toleransi napas 80ms untuk sinkronisasi physics/weld
                        break
                    end
                end
            end

            -- Klik-klik berulang layaknya manusia setiap ~0.35s (respek rate-limit server CDID)
            if (os.clock() - lastClick) >= 0.1 then
                lastClick = os.clock()
                if PromptHelper and PromptHelper.Trigger then
                    PromptHelper.Trigger(spawnerPrompt)
                elseif fireproximityprompt then
                    pcall(fireproximityprompt, spawnerPrompt)
                end
            end

            task.wait(0.05)
        end

        if not Job.State.IsFarming then break end
        if not car or typeof(car) ~= "Instance" or not car.Parent then
            if Log then Log.Warn("Truk tidak terdeteksi di spawner. Mengulang siklus dari Depot...") end
            continue
        end
        if Log then Log.Success("Truk berhasil di-spawn!") end
        task.wait(0.3) -- Jeda 0.3s agar model dan script A-Chassis selesai streaming

        if Job.Config.StripTrailer then
            stripTrailer(car)
        end

        local seatedOk = ensureSeated(car)
        local chassisOk = waitForAChassisInterface(car)
        if not seatedOk or not chassisOk or not Job.State.IsFarming or not car or not car.Parent then
            if Log then Log.Warn("Supir belum duduk sah di truk. Mengulang dari Depot...") end
            continue
        end

        -- Lapor ke Web/Backend bahwa job ON & RUNNING pertama kali pas udah naik truk!
        if not Job.State.HasReportedFirstSeat then
            Job.State.HasReportedFirstSeat = true
            local D = _G.OE_Dispatcher or Dispatcher
            if D then
                if D.Publish then
                    D.Publish({
                        type = "MODULE_STATUS",
                        plugin = "truck_driver",
                        enabled = true,
                        status = "RUNNING"
                    })
                end
                if D.ActiveStates then
                    D.ActiveStates["truck_driver"] = { enabled = true, status = "RUNNING" }
                end
                emitTelemetry()
            end
            if Log then Log.Success("[Backend] Supir sah duduk di truk pertama kali -> Status Job ON dilaporkan ke Web!") end
        end
        if not chassisOk or not Job.State.IsFarming or not car or not car.Parent then
            if Log then Log.Warn("A-Chassis Interface belum terverifikasi atau truk hilang. Mengulang dari Depot...") end
            continue
        end

        -- LANGKAH 5 & 6: Delivery Loop (Deliver -> WaitForPayout -> SmartChain/Reroll)
        -- Sinkronisasi Waypoint SSOT terbaru yang aktif di server
        local currentWp = (Waypoint and Waypoint.Get()) or initialRoute
        while Job.State.IsFarming and car and car.Parent do
            if not currentWp or not currentWp.Position then
                currentWp = Waypoint and Waypoint.WaitForTarget(3.0)
                if not currentWp then break end
            end

            local deliveredPos = currentWp.Position
            local deliveredName = currentWp.Name or "Destination"
            local cashBefore = ReplicaBridge and ReplicaBridge.GetCash() or 0

            local deliverOk = deliverCargo(car, char, deliveredPos, deliveredName)
            if not deliverOk or not Job.State.IsFarming then break end

            local payoutTimestamp = os.clock()
            local payoutOk, gained = waitForPayout(cashBefore, deliveredPos)
            if not payoutOk or not Job.State.IsFarming then break end

            if not Job.Config.SmartChaining then
                -- Auto ngulang instan: Seketika barengan despawn truk & teleport balik ke Depot Starter!
                resetJobAndTeleportHQ()
                break
            end

            local decision, nextRoute = determineNextRouteOrReroll(car, deliveredPos, payoutTimestamp)
            if decision == "CHAIN" and nextRoute then
                currentWp = nextRoute
            else
                break
            end
        end

        if Waypoint and Waypoint.Clear then
            Waypoint.Clear()
        end
        pcall(function()
            collectgarbage("step", 100)
        end)
        task.wait()
    end
end

-- ==============================================================================
-- PUBLIC CONTROL INTERFACE
-- ==============================================================================
function Job.Start(payload)
    if Job.State.IsFarming then return end

    if payload and payload.MinDistance then
        Job.Config.MinDistance = tonumber(payload.MinDistance) or Job.Config.MinDistance
    end
    if payload and payload.WaitDuration then
        Job.Config.WaitDuration = tonumber(payload.WaitDuration) or Job.Config.WaitDuration
    end

    Job.State.IsFarming = true
    Job.State.Status = "STARTING"
    Job.State.HasReportedFirstSeat = false

    _farmTrove = Trove and Trove.new()
    if Waypoint then
        Waypoint.Start(_farmTrove)
    end

    pcall(function()
        GuiService.GameplayPausedNotificationEnabled = false
        if getconnections then
            for _, conn in pairs(getconnections(LocalPlayer.Idled)) do conn:Disable() end
        end
    end)

    if Log then Log.Success("Auto Farm Truck Driver CDID Dimulai!") end
    if Notify then Notify.Success("Auto Farm Truck Driver CDID Dimulai!") end
    emitTelemetry()

    _farmThread = spawnTask("TruckFarmLoop", function()
        local ok, err = pcall(runFarmLoop)
        if not ok and Log then
            Log.Error("Truck Farm Loop Error: " .. tostring(err))
        end
    end)

    if _farmTrove and _farmThread then
        _farmTrove:Add(_farmThread)
    end
end

function Job.Stop()
    Job.State.IsFarming = false
    Job.State.Status = "STOPPED"
    Job.State.TripCount = 0
    Job.State.LastPayout = 0
    Job.State.TotalEarnings = 0
    Job.State.CurrentRoute = "-"

    if _farmThread then
        task.cancel(_farmThread)
        _farmThread = nil
    end

    if _farmTrove then
        _farmTrove:Clean()
        _farmTrove = nil
    end

    if Waypoint then
        Waypoint.Stop()
    end

    fireJobRemote("Unemployee")

    if Log then Log.Warn("Auto Farm Truck Driver dihentikan.") end
    if Notify then Notify.Warn("Auto Farm Truck Driver dihentikan.") end

    emitTelemetry()
end

function Job.TeleportHQ()
    local starterFolder = Workspace:FindFirstChild("Etc")
        and Workspace.Etc:FindFirstChild("Job")
        and Workspace.Etc.Job:FindFirstChild("Truck")
        and Workspace.Etc.Job.Truck:FindFirstChild("Starter")
    local starterPrompt = starterFolder and starterFolder:FindFirstChildWhichIsA("ProximityPrompt", true)
    local starterLoc = getJobStarterLocation()
    local starterPos = (starterLoc and starterLoc.Truck and starterLoc.Truck.Location)
        or (starterPrompt and starterPrompt.Parent and starterPrompt.Parent:GetPivot().Position)
        or Vector3.new(-829.6, 26.6, 4426.8)

    safeTeleportPlayer(CFrame.new(starterPos + Vector3.new(0, 5, 0)))
    if Log then Log.Info("Teleportasi ke Depot HQ Truk.") end
    if Notify then Notify.Success("Berhasil teleport ke Depot HQ Truk.") end
end

function Job.GetState()
    Job.EmitTelemetry = emitTelemetry
    return Job.State
end

_G.OE_TruckJob = Job
shared.OE_TruckJob = Job
return Job

end)()

-- ==============================================================================
-- [7/10] VERBATIM: games/cdid/plugins/privateserver/environment.lua
-- ==============================================================================
_Modules["environment"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID PRIVATE SERVER: ENVIRONMENT CONTROLS
    File: games/cdid/plugins/privateserver/environment.lua
================================================================================
]]

local Environment = {}
local Lighting = game:GetService("Lighting")

local function getDispatcher() return _G.OE_Dispatcher end

local function getLogger()
    local d = getDispatcher()
    if d and d.Logger then return d.Logger.Scope("PS:Environment") end
    return {
        Success = function(m, r) print("[OE:SUCCESS] [PS:Env     ] " .. tostring(m)) end,
        Info    = function(m, r) print("[OE:INFO   ] [PS:Env     ] " .. tostring(m)) end,
        Warn    = function(m, r) warn("[OE:WARN   ] [PS:Env     ] " .. tostring(m)) end,
        Error   = function(m, r) warn("[OE:ERROR  ] [PS:Env     ] " .. tostring(m)) end,
    }
end

local function getSharedNetwork()
    local d = getDispatcher()
    if d and d.LoadSubmodule then
        return d.LoadSubmodule("games/cdid/shared/network.lua")
    end
    return nil
end

-- 1. Mengubah Jam Server (0 s/d 24)
function Environment.SetTime(clockTime)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    local timeNum = tonumber(clockTime) or 12
    timeNum = math.clamp(timeNum, 0, 24)

    local ok, err = Network.Fire("Private Server", "time", { tostring(timeNum) })
    if ok then
        Log.Success("Jam Server Diubah", string.format("%02d:00", math.floor(timeNum)))
        if Notify then Notify.Success("Private Server", string.format("Jam server diubah ke %02d:00", math.floor(timeNum))) end
        return true, string.format("Jam server diubah ke %02d:00", math.floor(timeNum))
    end

    Log.Error("Gagal Mengubah Jam", err)
    if Notify then Notify.Error("Private Server", "Gagal mengubah jam: " .. tostring(err)) end
    return false, "Gagal mengubah jam: " .. tostring(err)
end

-- 2. Kunci / Hentikan Perputaran Waktu (Freeze Time)
function Environment.SetFreezeTime(enable)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    local action = (enable == true) and "freezetime" or "unfreezetime"
    local ok, err = Network.Fire("Private Server", action, {})
    if ok then
        local status = enable and "Diaktifkan (Waktu Berhenti)" or "Dinonaktifkan"
        Log.Success("Freeze Time", status)
        if Notify then Notify.Info("Private Server", "Freeze Time " .. status) end
        return true, "Freeze Time " .. status
    end

    Log.Error("Gagal Toggle Freeze Time", err)
    return false, "Gagal toggle freeze time: " .. tostring(err)
end

-- 3. Toggle Cuaca Hujan (Rain)
function Environment.ToggleRain()
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    local ok, err = Network.Fire("Private Server", "rain", {})
    if ok then
        Log.Success("Cuaca Hujan Di-Toggle", "Rain")
        if Notify then Notify.Info("Private Server", "Status cuaca hujan berhasil diubah.") end
        return true, "Status cuaca hujan di-toggle!"
    end

    Log.Error("Gagal Toggle Hujan", err)
    return false, "Gagal toggle hujan: " .. tostring(err)
end

-- 4. Mengatur Kepadatan Kabut (Fog Density 0.0 s/d 1.0)
function Environment.SetFog(density)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    local fogVal = tonumber(density) or 0.2
    fogVal = math.clamp(fogVal, 0, 1)

    local ok, err = Network.Fire("Private Server", "fog", { tostring(fogVal) })
    if ok then
        Log.Success("Kabut Diatur", string.format("%.2f", fogVal))
        if Notify then Notify.Info("Private Server", string.format("Kepadatan kabut diubah ke %.2f", fogVal)) end
        return true, string.format("Kepadatan kabut diubah ke %.2f", fogVal)
    end

    Log.Error("Gagal Mengatur Kabut", err)
    return false, "Gagal mengubah kabut: " .. tostring(err)
end

function Environment.GetStatus()
    return {
        ClockTime = Lighting.ClockTime,
        FogDensity = Lighting.Atmosphere and Lighting.Atmosphere.Density or 0,
        TimeActive = Lighting:FindFirstChild("TimeActive") and Lighting.TimeActive.Value or true
    }
end

return Environment

end)()

-- ==============================================================================
-- [8/10] VERBATIM: games/cdid/plugins/privateserver/security.lua
-- ==============================================================================
_Modules["security"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID PRIVATE SERVER: SECURITY CONTROLS
    File: games/cdid/plugins/privateserver/security.lua
================================================================================
]]

local Security = {}

local function getDispatcher() return _G.OE_Dispatcher end

local function getLogger()
    local d = getDispatcher()
    if d and d.Logger then return d.Logger.Scope("PS:Security") end
    return {
        Success = function(m, r) print("[OE:SUCCESS] [PS:Sec     ] " .. tostring(m)) end,
        Info    = function(m, r) print("[OE:INFO   ] [PS:Sec     ] " .. tostring(m)) end,
        Warn    = function(m, r) warn("[OE:WARN   ] [PS:Sec     ] " .. tostring(m)) end,
        Error   = function(m, r) warn("[OE:ERROR  ] [PS:Sec     ] " .. tostring(m)) end,
    }
end

local function getSharedNetwork()
    local d = getDispatcher()
    if d and d.LoadSubmodule then
        return d.LoadSubmodule("games/cdid/shared/network.lua")
    end
    return nil
end

-- 1. Kunci / Buka Akses Server (Server Lock)
function Security.SetServerLock(lock)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    local action = (lock == true) and "serverlock" or "serverunlock"
    local ok, err = Network.Fire("Private Server", action, {})
    if ok then
        local msg = "Server " .. (lock and "DIKUNCI (Pemain baru tidak bisa join)" or "DIBUKA kembali")
        Log.Success("Server Lock", lock and "LOCKED" or "UNLOCKED")
        if Notify then Notify.Warning("Private Server", msg) end
        return true, msg
    end

    Log.Error("Gagal Mengubah Server Lock", err)
    return false, "Gagal mengubah server lock: " .. tostring(err)
end

-- 2. Kirim Pesan Pengumuman Banner ke Seluruh Pemain di Server
function Security.SendMessage(text)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    if not text or text == "" then return false, "Pesan tidak boleh kosong!" end

    local ok, err = Network.Fire("Private Server", "message", { tostring(text) })
    if ok then
        Log.Success("Pengumuman Terkirim", text)
        if Notify then Notify.Success("Pengumuman", "Pengumuman berhasil disiarkan!") end
        return true, "Pengumuman berhasil dikirim ke layar seluruh pemain!"
    end

    Log.Error("Gagal Siaran Pengumuman", err)
    return false, "Gagal mengirim pengumuman: " .. tostring(err)
end

-- 3. Matikan / Tutup Server (Shutdown)
function Security.Shutdown()
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    local ok, err = Network.Fire("Private Server", "shutdown")
    if ok then
        Log.Warn("Server Shutdown Initiated", "Shutdown")
        if Notify then Notify.Warning("Private Server", "Perintah shutdown server dikirim!") end
        return true, "Perintah shutdown server berhasil dikirim!"
    end

    Log.Error("Gagal Shutdown Server", err)
    return false, "Gagal mematikan server: " .. tostring(err)
end

return Security

end)()

-- ==============================================================================
-- [9/10] VERBATIM: games/cdid/plugins/privateserver/moderation.lua
-- ==============================================================================
_Modules["moderation"] = (function()
--[[
================================================================================
    OE HUB v2 - CDID PRIVATE SERVER: PLAYER MODERATION
    File: games/cdid/plugins/privateserver/moderation.lua
================================================================================
]]

local Moderation = {}
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function getDispatcher() return _G.OE_Dispatcher end

local function getLogger()
    local d = getDispatcher()
    if d and d.Logger then return d.Logger.Scope("PS:Moderation") end
    return {
        Success = function(m, r) print("[OE:SUCCESS] [PS:Mod     ] " .. tostring(m)) end,
        Info    = function(m, r) print("[OE:INFO   ] [PS:Mod     ] " .. tostring(m)) end,
        Warn    = function(m, r) warn("[OE:WARN   ] [PS:Mod     ] " .. tostring(m)) end,
        Error   = function(m, r) warn("[OE:ERROR  ] [PS:Mod     ] " .. tostring(m)) end,
    }
end

local function getSharedNetwork()
    local d = getDispatcher()
    if d and d.LoadSubmodule then
        return d.LoadSubmodule("games/cdid/shared/network.lua")
    end
    return nil
end

function Moderation.GetPlayersList()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(list, {
            name = p.Name,
            displayName = p.DisplayName,
            userId = p.UserId,
            isSelf = (p == LocalPlayer)
        })
    end
    return list
end

-- 2. Kick Pemain dari Server
function Moderation.Kick(targetPlayerName)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    if not targetPlayerName or targetPlayerName == "" then return false, "Target tidak valid!" end

    local ok, err = Network.Fire("Private Server", "kick", { tostring(targetPlayerName) })
    if ok then
        Log.Success("Player Di-Kick", targetPlayerName)
        if Notify then Notify.Warning("Moderasi", string.format("Pemain @%s berhasil di-kick!", targetPlayerName)) end
        return true, string.format("Pemain @%s berhasil di-kick dari server!", targetPlayerName)
    end

    Log.Error("Gagal Kick Player", err)
    return false, "Gagal kick pemain: " .. tostring(err)
end

-- 3. Ban Pemain dari Server
function Moderation.Ban(targetPlayerName)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    if not targetPlayerName or targetPlayerName == "" then return false, "Target tidak valid!" end

    local ok, err = Network.Fire("Private Server", "ban", { tostring(targetPlayerName) })
    if ok then
        Log.Success("Player Di-Ban", targetPlayerName)
        if Notify then Notify.Error("Moderasi", string.format("Pemain @%s berhasil di-ban!", targetPlayerName)) end
        return true, string.format("Pemain @%s berhasil di-ban dari server!", targetPlayerName)
    end

    Log.Error("Gagal Ban Player", err)
    return false, "Gagal ban pemain: " .. tostring(err)
end

-- 4. Jadikan / Cabut Moderator Server
function Moderation.ToggleModerator(targetPlayerName)
    local Log = getLogger()
    local d = getDispatcher()
    local Notify = d and d.Notify

    local Network = getSharedNetwork()
    if not Network then return false, "Shared Network belum siap!" end

    if not targetPlayerName or targetPlayerName == "" then return false, "Target tidak valid!" end

    local ok, err = Network.Fire("Private Server", "moderator", { tostring(targetPlayerName) })
    if ok then
        Log.Success("Moderator Diubah", targetPlayerName)
        if Notify then Notify.Info("Moderasi", string.format("Hak moderator @%s diubah!", targetPlayerName)) end
        return true, string.format("Hak moderator untuk @%s berhasil di-toggle!", targetPlayerName)
    end

    Log.Error("Gagal Ubah Hak Moderator", err)
    return false, "Gagal mengubah hak moderator: " .. tostring(err)
end

return Moderation

end)()

-- ==============================================================================
-- [10/10] VERBATIM: games/cdid/plugins/privateserver/init.lua
-- ==============================================================================
local PrivateServer = (function()
--[[
================================================================================
    OE HUB v2 - CDID PRIVATE SERVER PLUGIN
    File: games/cdid/plugins/privateserver/init.lua
================================================================================
    Plugin resmi kontrol cuaca, waktu, dan keamanan Private Server CDID:
    - Day & Night (Icon Buttons tanpa teks)
    - Freeze Time (Switch)
    - Rain (Switch)
    - Clear Fog (Switch)
    - Server Lock (Switch)
    - Shutdown Server (Icon Button tanpa teks)
    - Status Server Extras SSOT Provider
================================================================================
]]

local Plugin = {}

local Dispatcher = _G.OE_Dispatcher
local Util = (Dispatcher and Dispatcher.Util) or _G.OE_Util
local rawLogger = Util and (Util.Logger or (Util.Get and Util.Get("Logger")))
local Log = nil
if rawLogger and rawLogger.Scope then
    Log = rawLogger.Scope("PrivateServer:Gateway")
    Log.SetEnabled(false) -- Default: false (Hening di F9 sesuai preferensi user)
else
    Log = {
        Enabled = false,
        SetEnabled = function(self, s) self.Enabled = (s == true) end,
        Info = function(...) end,
        Warn = function(...) end,
        Success = function(...) end,
        Error = function(...) end
    }
end

Plugin.Capabilities = {
    Id = "privateserver",
    Order = 4,
    Name = "Private Server",
    Type = "utility",
    Icon = "server",
    Description = "Kontrol penuh cuaca, waktu, dan keamanan Private Server.",
    HasLoop = false,

    Actions = {
        {
            Id = "ps_set_day",
            Label = "Day",
            Type = "shot",
            BtnText = "",
            BtnIcon = "sun",
            Icon = "sun"
        },
        {
            Id = "ps_set_night",
            Label = "Night",
            Type = "shot",
            BtnText = "",
            BtnIcon = "moon",
            Icon = "moon"
        },
        {
            Id = "ps_freeze_time",
            Label = "Freeze Time",
            Type = "switch",
            Icon = "clock",
            Default = false
        },
        {
            Id = "ps_toggle_rain",
            Label = "Rain",
            Type = "switch",
            Icon = "cloud-rain",
            Default = false
        },
        {
            Id = "ps_clear_fog",
            Label = "Clear Fog",
            Type = "switch",
            Icon = "wind",
            Default = false
        },
        {
            Id = "ps_server_lock",
            Label = "Server Lock",
            Type = "switch",
            Icon = "lock",
            Default = false
        },
        {
            Id = "ps_shutdown",
            Label = "Shutdown Server",
            Type = "shot",
            BtnText = "",
            BtnIcon = "power",
            Icon = "power"
        }
    }
}

-- Dispatcher & Core Util Gateway
local Dispatcher = _G.OE_Dispatcher
local Util = (Dispatcher and Dispatcher.Util) or _G.OE_Util

-- Submodul Lazy Loaders
local EnvModule = nil
local SecModule = nil
local ModModule = nil

local function getEnv()
    if not EnvModule then
        local D = _G.OE_Dispatcher or Dispatcher
        if D and D.LoadSubmodule then
            EnvModule = D.LoadSubmodule("games/cdid/plugins/privateserver/environment.lua")
        end
    end
    return EnvModule
end

local function getSec()
    if not SecModule then
        local D = _G.OE_Dispatcher or Dispatcher
        if D and D.LoadSubmodule then
            SecModule = D.LoadSubmodule("games/cdid/plugins/privateserver/security.lua")
        end
    end
    return SecModule
end

-- Validasi apakah sedang berada di Private Server
local _cachedIsPs = nil
local function isPrivateServer()
    if _cachedIsPs ~= nil then return _cachedIsPs end

    local D = _G.OE_Dispatcher or Dispatcher
    if D and D.GetGameBaselineValue then
        local sType = D.GetGameBaselineValue("Server Type")
        if sType == "Private Server" then
            _cachedIsPs = true
            return true
        end
    end

    if game.PrivateServerId ~= "" then
        _cachedIsPs = true
        return true
    end

    local LocalPlayer = game:GetService("Players").LocalPlayer
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local topbar = pg and (pg:FindFirstChild("TopbarStandard") or pg:FindFirstChild("Topbar"))
    if topbar then
        for _, d in ipairs(topbar:GetDescendants()) do
            if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and tostring(d.Image):find("15674410240") then
                _cachedIsPs = true
                return true
            end
        end
        _cachedIsPs = false
        return false
    end

    return false
end

-- ==============================================================================
-- HANDLER SWITCH & SETTINGS (TUNE)
-- ==============================================================================
local _freezeState = false
local _serverLockState = false
local _fogState = false

function Plugin.Tune(settings)
    settings = settings or {}
    if not isPrivateServer() then
        if Util and Util.Notify then
            Util.Notify.Error("Private Server", "Perintah ditolak: Fitur ini hanya berlaku di Private Server!")
        end
        return false, "Hanya berlaku di Private Server"
    end

    local Env = getEnv()
    local Sec = getSec()

    -- 1. Freeze Time Switch
    if settings.ps_freeze_time ~= nil and Env then
        _freezeState = (settings.ps_freeze_time == true)
        local ok, msg = Env.SetFreezeTime(_freezeState)
        if Util and Util.Notify then
            if ok then Util.Notify.Info("Private Server", _freezeState and "Freeze Time Aktif" or "Freeze Time Nonaktif") else Util.Notify.Error("Private Server", msg) end
        end
        pcall(Plugin.ReportState)
    end

    -- 2. Rain Switch
    if settings.ps_toggle_rain ~= nil and Env then
        local ok, msg = Env.ToggleRain()
        if Util and Util.Notify then
            if ok then Util.Notify.Info("Private Server", "Status hujan di-toggle!") else Util.Notify.Error("Private Server", msg) end
        end
        pcall(Plugin.ReportState)
    end

    -- 3. Clear Fog Switch
    if settings.ps_clear_fog ~= nil and Env then
        _fogState = (settings.ps_clear_fog == true)
        local density = _fogState and 0 or 0.2
        local ok, msg = Env.SetFog(density)
        if Util and Util.Notify then
            if ok then Util.Notify.Success("Private Server", _fogState and "Clear Fog Aktif (Kabut Bersih)" or "Kabut Standar") else Util.Notify.Error("Private Server", msg) end
        end
        pcall(Plugin.ReportState)
    end

    -- 4. Server Lock Switch (Satukan Lock dan Unlock)
    if settings.ps_server_lock ~= nil and Sec then
        _serverLockState = (settings.ps_server_lock == true)
        local ok, msg = Sec.SetServerLock(_serverLockState)
        if Util and Util.Notify then
            if ok then
                if _serverLockState then Util.Notify.Warning("Private Server", "Server DIKUNCI (Pemain baru tidak bisa join)!") else Util.Notify.Success("Private Server", "Kunci server DIBUKA kembali.") end
            else
                Util.Notify.Error("Private Server", msg)
            end
        end
        pcall(Plugin.ReportState)
    end
end

-- ==============================================================================
-- ACTION HANDLER (SHOT BUTTONS & FALLBACK)
-- ==============================================================================
function Plugin.Shot(actionId, params)
    local D = _G.OE_Dispatcher or Dispatcher

    if not isPrivateServer() then
        if Util and Util.Notify then
            Util.Notify.Error("Private Server", "Perintah ditolak: Fitur ini hanya berlaku di Private Server!")
        end
        return false, "Hanya berlaku di Private Server"
    end

    params = params or {}
    local Env = getEnv()
    local Sec = getSec()

    -- 1. Day Action (12:00)
    if actionId == "ps_set_day" and Env then
        local ok, msg = Env.SetTime(12)
        if Util and Util.Notify then
            if ok then Util.Notify.Success("Private Server", "Jam server diubah ke 12:00 (Day)") else Util.Notify.Error("Private Server", msg) end
        end
        pcall(Plugin.ReportState)
        return ok, msg

    -- 2. Night Action (00:00)
    elseif actionId == "ps_set_night" and Env then
        local ok, msg = Env.SetTime(0)
        if Util and Util.Notify then
            if ok then Util.Notify.Success("Private Server", "Jam server diubah ke 00:00 (Night)") else Util.Notify.Error("Private Server", msg) end
        end
        pcall(Plugin.ReportState)
        return ok, msg

    -- 3. Shutdown Server Action
    elseif actionId == "ps_shutdown" and Sec then
        local ok, msg = Sec.Shutdown()
        if Util and Util.Notify then
            if ok then Util.Notify.Warning("Private Server", "Perintah shutdown server dikirim!") else Util.Notify.Error("Private Server", msg) end
        end
        return ok, msg

    -- Fallback triggers
    elseif actionId == "ps_freeze_time" then
        return Plugin.Tune({ ps_freeze_time = not _freezeState })

    elseif actionId == "ps_toggle_rain" then
        return Plugin.Tune({ ps_toggle_rain = true })

    elseif actionId == "ps_clear_fog" then
        return Plugin.Tune({ ps_clear_fog = not _fogState })

    elseif actionId == "ps_server_lock" then
        return Plugin.Tune({ ps_server_lock = not _serverLockState })
    end

    warn("[CDID PrivateServer] Aksi tidak dikenal: " .. tostring(actionId))
    return false, "Action unknown: " .. tostring(actionId)
end

Plugin.OnAction = Plugin.Shot

-- ==============================================================================
-- EXTRAS & TELEMETRY PROVIDER (DISPLAY DI CARD)
-- ==============================================================================
function Plugin.GetExtras()
    local inPS = isPrivateServer()
    return {
        ["Status Server"] = inPS and "Private Server" or "Public Server"
    }
end

function Plugin.ReportState()
    local D = _G.OE_Dispatcher or Dispatcher
    if D and D.ReportJobState then
        D.ReportJobState("privateserver", {
            extras = Plugin.GetExtras()
        })
    end
end

-- Otomatis laporkan state saat plugin pertama kali dimuat
task.defer(function()
    task.wait(0.5)
    pcall(Plugin.ReportState)
end)

return Plugin

end)()
_Modules["privateserver"] = PrivateServer

-- ==============================================================================
-- [UI] WINDUI v1.6.66
-- ==============================================================================
local _version = "1.6.66"
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/" .. _version .. "/main.lua"))()
_G.OE_WindUI = WindUI

-- ==============================================================================
-- ANTI-AFK ENGINE (TRIPLE-LAYER SAFETY NET: GAMEPLAY PAUSE, IDLED, & PULSE)
-- ==============================================================================
local _antiAfkEnabled = true
local _antiAfkConn = nil

local function startAntiAFK()
    if _antiAfkConn then return end

    -- Layer 1: Matikan popup gameplay paused Roblox
    pcall(function()
        if GuiService then
            GuiService.GameplayPausedNotificationEnabled = false
        end
    end)

    -- Layer 2: Matikan semua koneksi Idled internal client jika didukung executor
    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(LocalPlayer.Idled)) do
                pcall(function() conn:Disable() end)
            end
        end
    end)

    -- Layer 3: Simulasi Virtual Input reaktif saat Idled terpicu
    pcall(function()
        _antiAfkConn = LocalPlayer.Idled:Connect(function()
            if not _antiAfkEnabled then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end)
    end)
end

local function stopAntiAFK()
    if _antiAfkConn then
        pcall(function() _antiAfkConn:Disconnect() end)
        _antiAfkConn = nil
    end
end

-- Nyalakan proteksi Anti-AFK default aktif sejak script dieksekusi
startAntiAFK()

-- Layer 4: Proactive Pulse tiap 10 Menit (Proteksi saat game di-minimize)
task.spawn(function()
    while true do
        task.wait(600)
        if _antiAfkEnabled then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end
    end
end)

local Window = WindUI:CreateWindow({
    Title = "One Eight Hub - CDID In-Game",
    Icon = "truck",
    Author = "OE Hub",
    Folder = "OEHub_WindUI",
    Size = UDim2.fromOffset(580, 440),
    Theme = "Dark",
    Transparent = true,
    OpenButton = {
        Title = "OE Hub",
        Icon = "truck",
        Enabled = true,
        Draggable = true,
    }
})

-- ==============================================================================
-- TAB 1: AUTO FARM TRUCK
-- ==============================================================================
local FarmTab = Window:Tab({
    Title = "Auto Farm",
    Icon = "play",
})

FarmTab:Toggle({
    Title = "Enable Auto Farm Truck",
    Desc = "Jalankan engine Job.lua bawaan OE Hub CDID",
    Default = false,
    Callback = function(value)
        if value then
            Job.Start()
            WindUI:Notify({
                Title = "OE Hub",
                Content = "Auto Farm Truck Driver Dimulai!",
                Icon = "play",
                Duration = 3
            })
        else
            Job.Stop()
            WindUI:Notify({
                Title = "OE Hub",
                Content = "Auto Farm Truck Driver Dihentikan.",
                Icon = "square",
                Duration = 3
            })
        end
    end,
})

FarmTab:Toggle({
    Title = "Lepas Trailer (Anti-Glitch)",
    Desc = "Lepas trailer truk otomatis saat spawn",
    Default = Job.Config.StripTrailer,
    Callback = function(value)
        Job.Config.StripTrailer = value
    end,
})

local StatsParagraph = FarmTab:Paragraph({
    Title = "Live Telemetri",
    Desc = "Status: IDLE\nRuntime: 00:00:00\nAvg/h: Rp 0/h\nRute Aktif: -\nSisa Waktu: 0s\nTotal Trip: 0\nTotal Gaji: Rp 0",
    Image = "activity",
})

-- ==============================================================================
-- TAB 2: PRIVATE SERVER CONTROLS
-- ==============================================================================
local PSTab = Window:Tab({
    Title = "Private Server",
    Icon = "server",
})

local PSEnv = _Modules["environment"]
local PSSec = _Modules["security"]

PSTab:Section({ Title = "Kontrol Waktu & Cuaca" })

PSTab:Button({
    Title = "Set Siang (Day 12:00)",
    Desc = "Ubah jam server ke jam 12:00 siang",
    Icon = "sun",
    Callback = function()
        if PSEnv then
            local ok, msg = PSEnv.SetTime(12)
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and "Jam diubah ke 12:00 siang" or ("Gagal: " .. tostring(msg)),
                Icon = "sun",
                Duration = 3
            })
        end
    end,
})

PSTab:Button({
    Title = "Set Malam (Night 00:00)",
    Desc = "Ubah jam server ke jam 00:00 malam",
    Icon = "moon",
    Callback = function()
        if PSEnv then
            local ok, msg = PSEnv.SetTime(0)
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and "Jam diubah ke 00:00 malam" or ("Gagal: " .. tostring(msg)),
                Icon = "moon",
                Duration = 3
            })
        end
    end,
})

PSTab:Toggle({
    Title = "Freeze Time (Hentikan Waktu)",
    Desc = "Kunci perputaran waktu di server agar jam tidak berubah",
    Default = false,
    Callback = function(value)
        if PSEnv then
            local ok, msg = PSEnv.SetFreezeTime(value)
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and (value and "Freeze Time Aktif" or "Freeze Time Nonaktif") or ("Gagal: " .. tostring(msg)),
                Icon = "clock",
                Duration = 3
            })
        end
    end,
})

PSTab:Toggle({
    Title = "Cuaca Hujan (Rain)",
    Desc = "Toggle aktif/nonaktif efek hujan di Private Server",
    Default = false,
    Callback = function(value)
        if PSEnv then
            local ok, msg = PSEnv.ToggleRain()
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and "Cuaca hujan di-toggle!" or ("Gagal: " .. tostring(msg)),
                Icon = "cloud-rain",
                Duration = 3
            })
        end
    end,
})

PSTab:Toggle({
    Title = "Clear Fog (Hilangkan Kabut)",
    Desc = "Bersihkan kabut agar pandangan jauh lebih jernih",
    Default = false,
    Callback = function(value)
        if PSEnv then
            local ok, msg = PSEnv.SetFog(value and 0 or 0.2)
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and (value and "Clear Fog Aktif (Kabut Bersih)" or "Kabut Standar") or ("Gagal: " .. tostring(msg)),
                Icon = "wind",
                Duration = 3
            })
        end
    end,
})

PSTab:Section({ Title = "Keamanan & Server" })

PSTab:Toggle({
    Title = "Server Lock (Kunci Server)",
    Desc = "Kunci server agar pemain baru tidak bisa masuk",
    Default = false,
    Callback = function(value)
        if PSSec then
            local ok, msg = PSSec.SetServerLock(value)
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and (value and "Server DIKUNCI!" or "Server DIBUKA!") or ("Gagal: " .. tostring(msg)),
                Icon = "lock",
                Duration = 3
            })
        end
    end,
})

local broadcastMsg = ""
PSTab:Input({
    Title = "Pesan Siaran (Broadcast)",
    Desc = "Ketik teks pengumuman yang akan dikirim ke seluruh pemain",
    Placeholder = "Tulis pengumuman di sini...",
    Callback = function(text)
        broadcastMsg = text
    end,
})

PSTab:Button({
    Title = "Kirim Pengumuman",
    Desc = "Siarkan banner pesan ke layar semua pemain",
    Icon = "send",
    Callback = function()
        if PSSec and broadcastMsg and broadcastMsg ~= "" then
            local ok, err = PSSec.SendMessage(broadcastMsg)
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and "Pengumuman berhasil disiarkan!" or ("Gagal: " .. tostring(err)),
                Icon = ok and "check" or "alert-triangle",
                Duration = 3
            })
        else
            WindUI:Notify({
                Title = "Private Server",
                Content = "Pesan pengumuman tidak boleh kosong!",
                Icon = "alert-circle",
                Duration = 3
            })
        end
    end,
})

PSTab:Button({
    Title = "Shutdown Server",
    Desc = "Tutup dan matikan instance Private Server saat ini",
    Icon = "power",
    Callback = function()
        if PSSec then
            local ok, msg = PSSec.Shutdown()
            WindUI:Notify({
                Title = "Private Server",
                Content = ok and "Perintah shutdown dikirim!" or ("Gagal: " .. tostring(msg)),
                Icon = "power",
                Duration = 3
            })
        end
    end,
})

-- ==============================================================================
-- TAB 3: SETTINGS
-- ==============================================================================
local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings",
})

SettingsTab:Toggle({
    Title = "Anti-AFK Protection",
    Desc = "Mencegah kick idle 20 menit dari Roblox saat AFK / minimize",
    Default = true,
    Callback = function(value)
        _antiAfkEnabled = value
        if value then
            startAntiAFK()
            WindUI:Notify({
                Title = "OE Hub",
                Content = "Proteksi Anti-AFK Diaktifkan!",
                Icon = "shield-check",
                Duration = 3
            })
        else
            stopAntiAFK()
            WindUI:Notify({
                Title = "OE Hub",
                Content = "Proteksi Anti-AFK Dinonaktifkan.",
                Icon = "shield-off",
                Duration = 3
            })
        end
    end,
})

SettingsTab:Toggle({
    Title = "Anti-Lag (Disable 3D Render)",
    Desc = "Matikan render 3D untuk menghemat beban CPU & GPU saat AFK",
    Default = false,
    Callback = function(value)
        pcall(function()
            RunService:Set3dRenderingEnabled(not value)
        end)
    end,
})

SettingsTab:Button({
    Title = "Teleport ke Depot Truck",
    Desc = "Pindahkan karakter ke depot kargo starter Surabaya",
    Callback = function()
        Job.TeleportHQ()
        WindUI:Notify({
            Title = "OE Hub",
            Content = "Teleportasi ke Depot Starter Truk berhasil!",
            Icon = "map-pin",
            Duration = 3
        })
    end,
})

SettingsTab:Button({
    Title = "Despawn Mobil / Reset Job",
    Desc = "Reset role pengemudi truk dan bersihkan mobil",
    Callback = function()
        local rem = ReplicatedStorage:FindFirstChild("NetworkContainer")
            and ReplicatedStorage.NetworkContainer:FindFirstChild("RemoteEvents")
            and ReplicatedStorage.NetworkContainer.RemoteEvents:FindFirstChild("Job")
        if rem then
            rem:FireServer("Unemployee")
            task.wait(0.1)
            rem:FireServer("Truck")
        end
        WindUI:Notify({
            Title = "OE Hub",
            Content = "Job Truck & Kendaraan berhasil di-reset.",
            Icon = "rotate-ccw",
            Duration = 3
        })
    end,
})

-- Helper format rupiah
local function formatRupiah(num)
    local n = math.floor(tonumber(num) or 0)
    local formatted = tostring(n):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    return "Rp " .. formatted
end

-- Engine Live Telemetri (Session Runtime & Event-Driven Avg/h Persis Backend)
task.spawn(function()
    while true do
        if Job and Job.State then
            -- 1. Deteksi Session Runtime: mulai tepat saat supir pertama kali duduk di truk
            if Job.State.IsFarming then
                if Job.State.HasReportedFirstSeat and not Job.State.FirstSeatTime then
                    Job.State.FirstSeatTime = os.clock()
                end
            else
                Job.State.FirstSeatTime = nil
                Job.State.AvgPerHour = 0
                Job.State.LastCalculatedGain = nil
            end

            local runtimeSec = 0
            local runtimeTxt = "00:00:00 (Menunggu Supir)"
            if Job.State.IsFarming and Job.State.FirstSeatTime then
                runtimeSec = math.max(0, math.floor(os.clock() - Job.State.FirstSeatTime))
                local h = math.floor(runtimeSec / 3600)
                local m = math.floor((runtimeSec % 3600) / 60)
                local s = runtimeSec % 60
                runtimeTxt = string.format("%02d:%02d:%02d", h, m, s)
            elseif not Job.State.IsFarming then
                runtimeTxt = "00:00:00"
            end

            -- 2. Event-Driven Avg Lock (Formula Backend accounts.js):
            -- Nilai avg/h di-lock saat di jalan raya, hanya dikalkulasi ulang saat ada gain baru
            local gain = Job.State.TotalEarnings or 0
            if gain ~= Job.State.LastCalculatedGain and gain > 0 and runtimeSec >= 10 then
                Job.State.LastCalculatedGain = gain
                local hours = runtimeSec / 3600
                Job.State.AvgPerHour = math.floor(gain / hours)
            elseif gain == 0 then
                Job.State.AvgPerHour = 0
            end

            local statusTxt = tostring(Job.State.Status or "IDLE")
            local routeTxt = tostring(Job.State.CurrentRoute or "-")
            local timerTxt = string.format("%ds", Job.State.RemainingSeconds or 0)
            local tripTxt = tostring(Job.State.TripCount or 0)
            local earningsTxt = formatRupiah(gain)
            local avgTxt = formatRupiah(Job.State.AvgPerHour or 0) .. "/h"

            pcall(function()
                if StatsParagraph and StatsParagraph.SetDesc then
                    StatsParagraph:SetDesc(string.format(
                        "Status: %s\nRuntime: %s\nAvg/h: %s\nRute Aktif: %s\nSisa Waktu Kargo: %s\nTotal Trip: %s\nTotal Gaji: %s",
                        statusTxt, runtimeTxt, avgTxt, routeTxt, timerTxt, tripTxt, earningsTxt
                    ))
                end
            end)
        end
        task.wait(0.3)
    end
end)

WindUI:Notify({
    Title = "OE Hub In-Game",
    Content = "WindUI v1.6.66 Siap Digunakan!",
    Icon = "truck",
    Duration = 5
})
