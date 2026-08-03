--!nonstrict
-- Udiskie bar widget: renders the mounted-device count and a tooltip listing.
-- the mounted devices. State comes from the udiskie service via shared state.

local function mountedDevices()
    local data = noctalia.state.get("udiskie_devices")
    if type(data) ~= "table" or type(data.raw) ~= "table" then
        return {}
    end
    local out = {}
    for _, d in ipairs(data.raw) do
        if d.mounted then
            table.insert(out, d)
        end
    end
    return out
end

local function render()
    local mounted = mountedDevices()
    local glyph = noctalia.getConfig("glyph") or "device-usb"
    local showCount = noctalia.getConfig("show_count")

    barWidget.setGlyph(glyph)

    if #mounted == 0 then
        barWidget.setText("")
        barWidget.setTooltip(noctalia.tr("tooltip_empty"))
        return
    end

    if showCount == nil or showCount == true then
        barWidget.setText(tostring(#mounted))
    else
        barWidget.setText("")
    end

    local rows = {}
    for _, d in ipairs(mounted) do
        table.insert(rows, d.label .. (d.mountPath ~= "" and (" (" .. d.mountPath .. ")") or ""))
    end
    barWidget.setTooltip(noctalia.tr("tooltip_mounted") .. "\n" .. table.concat(rows, "\n"))
end

noctalia.state.watch("udiskie_devices", function()
    render()
end)

function onClick()
    noctalia.togglePanel("aristides/udiskie:manager")
end

render()

