--!nonstrict
-- Udiskie service: monitors `udisksctl monitor` in real time, publishes device.
-- state to shared state (`udiskie_devices`), handles notifications, and processes IPC.
--
-- External commands: udiskie-info, udiskie-mount, udiskie-umount, udisksctl, xdg-open.

local prevMountedDevices = {}
local prevAllDevices = {}
local isInitialFetch = true

local function isTrue(val)
    return type(val) == "string" and val:lower() == "true"
end

local function parseUdiskieOutput(stdout)
    local rawDevices = {}
    local currentMounted = {}

    if not stdout then
        return rawDevices, currentMounted
    end

    for line in stdout:gmatch("[^\r\n]+") do
        local dev, label, mounted, mountPath, isLuks, isDrive, isPartition, isFilesystem, isDetachable, isEjectable, inUse, deviceSize = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if dev ~= nil and dev ~= "" then
            local cleanLabel = (label ~= nil and label ~= "") and label or dev
            cleanLabel = cleanLabel:gsub("^[^:]+:%s*", "")

            local isM = isTrue(mounted)
            local devObj = {
                device = dev,
                label = cleanLabel,
                mounted = isM,
                mountPath = mountPath or "",
                isLuks = isTrue(isLuks),
                isDrive = isTrue(isDrive),
                isPartition = isTrue(isPartition),
                isFilesystem = isTrue(isFilesystem),
                isDetachable = isTrue(isDetachable),
                isEjectable = isTrue(isEjectable),
                inUse = isTrue(inUse),
                size = tonumber(deviceSize) or 0,
            }
            table.insert(rawDevices, devObj)
            if isM then
                currentMounted[dev] = devObj.label
            end
        end
    end

    return rawDevices, currentMounted
end

local function buildHierarchy(rawDevices)
    local drives = {}
    local standalonePartitions = {}

    for _, d in ipairs(rawDevices) do
        if not d.isPartition and not d.isFilesystem then
            table.insert(drives, { drive = d, partitions = {} })
        end
    end

    for _, d in ipairs(rawDevices) do
        if d.isPartition or d.isFilesystem or d.isLuks then
            local parentFound = false
            for _, drvItem in ipairs(drives) do
                if d.device:find("^" .. drvItem.drive.device) then
                    table.insert(drvItem.partitions, d)
                    parentFound = true
                    break
                end
            end
            if not parentFound then
                table.insert(standalonePartitions, d)
            end
        end
    end

    return {
        drives = drives,
        standalone = standalonePartitions,
        raw = rawDevices,
    }
end

local function processNotifications(rawDevices, currentMounted)
    local enableNotifs = noctalia.getConfig("enable_notifications")
    if enableNotifs == false then
        return
    end

    local currentAllDevs = {}
    for _, d in ipairs(rawDevices) do
        if d.isDrive or (not d.isPartition and not d.isFilesystem) then
            currentAllDevs[d.device] = d.label
        end
    end

    -- 1. Device Insertion (Physical USB plugged in)
    if not isInitialFetch then
        for dev, label in pairs(currentAllDevs) do
            if not prevAllDevices[dev] then
                noctalia.notify("Drive Connected", label .. " connected")
            end
        end
        -- 2. Device Removal (Physical USB unplugged / powered off)
        for dev, label in pairs(prevAllDevices) do
            if not currentAllDevs[dev] then
                noctalia.notify("Drive Removed", label .. " disconnected")
            end
        end
    end

    -- 3. Device Mounted
    for dev, label in pairs(currentMounted) do
        if not prevMountedDevices[dev] then
            noctalia.notify("Drive Mounted", label .. " is ready to use")
            if noctalia.getConfig("auto_open_filemanager") == true then
                local cmd = noctalia.getConfig("file_manager_cmd") or "xdg-open"
                for _, d in ipairs(rawDevices) do
                    if d.device == dev and d.mountPath ~= "" then
                        noctalia.runAsync(cmd .. " " .. d.mountPath)
                        break
                    end
                end
            end
        end
    end

    -- 4. Device Unmounted
    for dev, label in pairs(prevMountedDevices) do
        if not currentMounted[dev] and currentAllDevs[dev] then
            noctalia.notify("Drive Unmounted", label .. " was safely unmounted")
        end
    end

    prevAllDevices = currentAllDevs
    prevMountedDevices = currentMounted
    isInitialFetch = false
end

local function fetchDevices()
    noctalia.runAsync("udiskie-info -a -o \"{device_file}|{ui_label}|{is_mounted}|{mount_path}|{is_luks}|{is_drive}|{is_partition}|{is_filesystem}|{is_detachable}|{is_ejectable}|{in_use}|{device_size}\"", function(res)
        if not res or res.exitCode ~= 0 then
            noctalia.state.set("udiskie_devices", { drives = {}, standalone = {}, raw = {}, error = "missing_dep" })
            return
        end

        local rawDevices, currentMounted = parseUdiskieOutput(res.stdout)
        local structured = buildHierarchy(rawDevices)
        structured.error = nil

        processNotifications(rawDevices, currentMounted)

        noctalia.state.set("udiskie_devices", structured)
    end, 5000)
end

-- Initial fetch on startup
noctalia.state.set("udiskie_devices", {})
fetchDevices()

-- Event-driven streaming using udisksctl monitor
noctalia.runStream("udisksctl monitor", function(line)
    if line:find("Added") or line:find("PropertiesChanged") or line:find("Removed") then
        fetchDevices()
    end
end)

local function cleanError(stderr, fallback)
    if not stderr or stderr == "" then
        return fallback
    end
    -- Strip DBus path prefixes like "failed to unmount /org/freedesktop/UDisks2/...:" or "failed to mount /dev/sda1:"
    local clean = stderr:gsub("failed to %w+ %S+:%s*", "")
    -- Strip GDBus error identifiers like "GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy:"
    clean = clean:gsub("GDBus%.Error:[%w%.]+:%s*", "")
    -- Clean leading/trailing whitespace
    clean = clean:gsub("^%s*", ""):gsub("%s*$", "")
    return clean ~= "" and clean or fallback
end

-- IPC Handlers for Panel and Shortcuts
function onIpc(event, payload)
    if event == "mount" and payload then
        noctalia.runAsync("udiskie-mount " .. payload, function(res)
            if res and res.exitCode ~= 0 and noctalia.getConfig("enable_notifications") ~= false then
                noctalia.notifyError("Mount Failed", cleanError(res.stderr, "Could not mount " .. payload))
            end
            fetchDevices()
        end)
    elseif event == "mount_all" then
        noctalia.runAsync("udiskie-mount -a", function(res)
            if res and res.exitCode ~= 0 and noctalia.getConfig("enable_notifications") ~= false then
                noctalia.notifyError("Mount All Failed", cleanError(res and res.stderr, "Could not mount all devices"))
            end
            fetchDevices()
        end)
    elseif event == "unmount" and payload then
        noctalia.runAsync("udiskie-umount " .. payload, function(res)
            if res and res.exitCode ~= 0 and noctalia.getConfig("enable_notifications") ~= false then
                noctalia.notifyError("Unmount Failed", cleanError(res.stderr, "Device " .. payload .. " is busy or in use"))
            end
            fetchDevices()
        end)
    elseif event == "unmount_all" then
        noctalia.runAsync("udiskie-umount -a", function(res)
            if res and res.exitCode ~= 0 and noctalia.getConfig("enable_notifications") ~= false then
                noctalia.notifyError("Unmount All Failed", cleanError(res and res.stderr, "One or more devices are busy"))
            end
            fetchDevices()
        end)
    elseif event == "eject" and payload then
        noctalia.runAsync("udiskie-umount -e " .. payload, function(res)
            if res and res.exitCode ~= 0 and noctalia.getConfig("enable_notifications") ~= false then
                noctalia.notifyError("Eject Failed", cleanError(res.stderr, "Could not eject " .. payload))
            end
            fetchDevices()
        end)
    elseif event == "detach" and payload then
        noctalia.runAsync("udiskie-umount -d " .. payload, function(res)
            if res and res.exitCode ~= 0 and noctalia.getConfig("enable_notifications") ~= false then
                noctalia.notifyError("Power Off Failed", cleanError(res.stderr, "Could not power off " .. payload))
            end
            fetchDevices()
        end)
    elseif event == "open" and payload then
        local cmd = noctalia.getConfig("file_manager_cmd") or "xdg-open"
        noctalia.runAsync(cmd .. " " .. payload)
    elseif event == "refresh" then
        fetchDevices()
    end
end
