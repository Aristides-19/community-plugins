--!nonstrict
-- Udiskie Manager Panel: Hierarchical Declarative UI panel for managing drives & partitions.

local function mountDevice(dev)
    noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all mount " .. dev)
end

local function unmountDevice(dev)
    noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all unmount " .. dev)
end

local function ejectDevice(dev)
    noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all eject " .. dev)
end

local function detachDevice(dev)
    noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all detach " .. dev)
end

local function openPath(path)
    noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all open " .. path)
    panel.close()
end

local function getData()
    local data = noctalia.state.get("udiskie_devices")
    if type(data) ~= "table" then
        return { drives = {}, standalone = {}, raw = {} }
    end
    return data
end

local function renderPartitionRow(part)
    local statusText = part.mounted and noctalia.tr("status_mounted") or (part.isLuks and noctalia.tr("status_locked") or noctalia.tr("status_unmounted"))
    local statusColor = part.mounted and "success" or (part.isLuks and "error" or "on_surface_variant")
    local statusGlyph = part.mounted and "circle-check" or (part.isLuks and "lock" or "circle")

    local actions = {}
    if part.mounted then
        if part.mountPath ~= "" then
            table.insert(actions, ui.button({
                text = noctalia.tr("btn_open"),
                glyph = "folder",
                variant = "outline",
                controlSize = "sm",
                onClick = function() openPath(part.mountPath) end,
            }))
        end
        table.insert(actions, ui.button({
            text = noctalia.tr("btn_unmount"),
            glyph = "player-stop",
            variant = "ghost",
            controlSize = "sm",
            onClick = function() unmountDevice(part.device) end,
        }))
    else
        table.insert(actions, ui.button({
            text = noctalia.tr("btn_mount"),
            glyph = "player-play",
            variant = "primary",
            controlSize = "sm",
            onClick = function() mountDevice(part.device) end,
        }))
    end

    return ui.row({
        align = "center",
        justify = "space_between",
        fill = "surface_variant/0.2",
        radius = 6,
        padding = 8,
    }, {
        ui.column({ gap = 2 }, {
            ui.row({ gap = 6, align = "center" }, {
                ui.glyph({ name = statusGlyph, size = 14, color = statusColor }),
                ui.label({ text = part.label, fontWeight = "bold", fontSize = 13 }),
                ui.label({ text = statusText, color = statusColor, fontSize = 11 }),
            }),
            ui.label({
                text = part.device .. (part.mountPath ~= "" and (" • " .. part.mountPath) or ""),
                color = "on_surface_variant",
                fontSize = 11,
            }),
        }),
        ui.row({ gap = 4, align = "center" }, actions),
    })
end

local function renderDriveCard(drvItem)
    local drv = drvItem.drive
    local parts = drvItem.partitions or {}

    local driveHeaderActions = {}
    if drv.isDetachable or drv.inUse or #parts > 0 then
        table.insert(driveHeaderActions, ui.button({
            text = noctalia.tr("btn_eject"),
            glyph = "player-eject",
            variant = "outline",
            controlSize = "sm",
            onClick = function() ejectDevice(drv.device) end,
        }))
        table.insert(driveHeaderActions, ui.button({
            glyph = "plug-off",
            tooltip = noctalia.tr("btn_poweroff"),
            variant = "destructive",
            controlSize = "sm",
            onClick = function() detachDevice(drv.device) end,
        }))
    end

    local partRows = {}
    if #parts == 0 then
        table.insert(partRows, ui.label({ text = "No partitions found", color = "on_surface_variant", fontSize = 12 }))
    else
        for _, p in ipairs(parts) do
            table.insert(partRows, renderPartitionRow(p))
        end
    end

    return ui.column({
        fill = "surface_variant/0.3",
        radius = 8,
        padding = 12,
        gap = 10,
    }, {
        -- Drive Header
        ui.row({ align = "center", justify = "space_between" }, {
            ui.row({ gap = 8, align = "center" }, {
                ui.glyph({ name = "device-usb", size = 18, color = "primary" }),
                ui.column({ gap = 2 }, {
                    ui.label({ text = drv.label, fontWeight = "bold", fontSize = 14, maxLines = 1 }),
                    ui.label({ text = drv.device, color = "on_surface_variant", fontSize = 11 }),
                }),
            }),
            ui.row({ gap = 4, align = "center" }, driveHeaderActions),
        }),
        ui.separator({ thickness = 1, color = "surface_variant/0.4" }),
        -- Partition List
        ui.column({ gap = 6 }, partRows),
    })
end

local function renderHeaderRow()
    return ui.row({ align = "center", paddingV = 4 }, {
        ui.row({ gap = 8, align = "center" }, {
            ui.glyph({ name = "device-usb", size = 20, color = "primary" }),
            ui.label({ text = noctalia.tr("panel_title"), fontSize = 16, fontWeight = "bold" }),
        }),
        ui.spacer(),
        ui.row({ gap = 6 }, {
            ui.button({
                text = noctalia.tr("btn_mount_all"),
                glyph = "link",
                variant = "secondary",
                controlSize = "sm",
                onClick = function() noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all mount_all") end,
            }),
            ui.button({
                glyph = "unlink",
                tooltip = noctalia.tr("btn_unmount_all"),
                variant = "destructive",
                controlSize = "sm",
                onClick = function() noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all unmount_all") end,
            }),
        }),
    })
end

local function render()
    local data = getData()
    local children = {}

    table.insert(children, renderHeaderRow())
    table.insert(children, ui.separator({ thickness = 1, color = "surface_variant" }))

    local drives = data.drives or {}
    local standalone = data.standalone or {}

    if data.error then
        table.insert(children, ui.column({ align = "center", justify = "center", paddingV = 24, gap = 12 }, {
            ui.glyph({ name = "alert-triangle", size = 36, color = "warning" }),
            ui.label({ text = noctalia.tr("error_missing_dep"), color = "on_surface" }),
            ui.row({ gap = 8, align = "center" }, {
                ui.button({
                    text = noctalia.tr("btn_retry"),
                    glyph = "refresh",
                    variant = "outline",
                    controlSize = "sm",
                    onClick = function()
                        noctalia.runAsync("noctalia msg plugin aristides/udiskie:service all refresh")
                    end,
                }),
                ui.button({
                    text = noctalia.tr("btn_docs"),
                    glyph = "external-link",
                    variant = "ghost",
                    controlSize = "sm",
                    onClick = function()
                        noctalia.runAsync("xdg-open 'https://github.com/coldfix/udiskie/wiki/Installation'")
                    end,
                }),
            }),
        }))
    elseif #drives == 0 and #standalone == 0 then
        table.insert(children, ui.column({ align = "center", justify = "center", paddingV = 24, gap = 8 }, {
            ui.glyph({ name = "device-floppy", size = 32, color = "on_surface_variant/0.5" }),
            ui.label({ text = noctalia.tr("panel_empty"), color = "on_surface_variant" }),
        }))
    else
        local cardItems = {}

        for _, drvItem in ipairs(drives) do
            table.insert(cardItems, renderDriveCard(drvItem))
        end

        for _, p in ipairs(standalone) do
            table.insert(cardItems, renderPartitionRow(p))
        end

        table.insert(children, ui.scroll({ gap = 10, maxLines = 12 }, cardItems))
    end

    panel.render(ui.column({ gap = 12, padding = 16 }, children))
end

function onOpen()
    render()
end

noctalia.state.watch("udiskie_devices", function()
    render()
end)

render()
