local CenterContainer = require("ui/widget/container/centercontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Model = require("lib/model")
local _ = require("gettext")
local T = require("ffi/util").template

-- UTF-8 byte escapes (LuaJIT has no \u{} literal):
local READ_MARK = "\226\156\147" -- U+2713 check mark
local CUR_MARK = "\226\150\182"  -- U+25B6 right-pointing triangle

local ArticlesView = {}

-- backlog: the plugin instance (provides .chapters, .state, :currentIndex,
-- :gotoChapter, :toggleRead).
function ArticlesView.show(backlog)
    local total = #backlog.chapters

    local function title_text()
        return T(_("Articles — %1/%2 read"),
            Model.count_read(backlog.chapters, backlog.state), total)
    end

    local function build_items()
        local items = {}
        local cur = backlog:currentIndex()
        for i, ch in ipairs(backlog.chapters) do
            -- Two independent slots so "current" and "read" show together:
            -- column 1 = current marker, column 2 = read marker.
            local cur_mark = (i == cur) and CUR_MARK or " "
            local read_mark = Model.is_read(backlog.state, ch.key) and READ_MARK or " "
            items[i] = {
                text = cur_mark .. " " .. read_mark .. "  " .. ch.title,
                mandatory = tostring(ch.start_page),
                bold = (i == cur),
                chapter_index = i,
            }
        end
        return items
    end

    local menu, container
    menu = Menu:new{
        title = title_text(),
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            UIManager:close(container)
            backlog:gotoChapter(item.chapter_index)
        end,
        onMenuHold = function(_self, item)
            backlog:toggleRead(item.chapter_index)
            -- Rebuild, but stay on the page that holds the toggled item.
            menu:switchItemTable(title_text(), build_items(), item.chapter_index)
            return true
        end,
    }
    container = CenterContainer:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true,
        menu,
    }
    menu.show_parent = container
    -- The title-bar X button calls the menu's close_callback; without it the X is a no-op.
    menu.close_callback = function()
        UIManager:close(container)
    end
    -- Populate the list and open it on the page holding the current article.
    menu:switchItemTable(title_text(), build_items(), backlog:currentIndex())
    UIManager:show(container)
end

return ArticlesView
