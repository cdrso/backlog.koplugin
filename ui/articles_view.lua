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

-- backlog: the plugin instance (provides .chapters [the article list], .state,
-- :currentIndex, :gotoChapter, :toggleRead).
function ArticlesView.show(backlog)
    local arts = backlog.chapters
    local total = #arts

    local function title_text()
        return T(_("Articles — %1/%2 read"),
            Model.count_read(arts, backlog.state), total)
    end

    local function section_counts(sec) -- read,total for one section
        local r, t = 0, 0
        for _, a in ipairs(arts) do
            if a.section == sec then
                t = t + 1
                if Model.is_read(backlog.state, a.key) then r = r + 1 end
            end
        end
        return r, t
    end

    -- Rows: a non-tappable header before each new section, then its articles
    -- (indented). Flat books (section=nil) get no headers/indent — same as before.
    -- Returns the rows + the row index of the current article (to open on it).
    local function build_items()
        local items, cur, cur_pos, prev = {}, backlog:currentIndex(), 1, nil
        for i, a in ipairs(arts) do
            if a.section and a.section ~= prev then
                local r, t = section_counts(a.section)
                items[#items + 1] = { text = a.section .. "  —  " .. r .. "/" .. t, bold = true,
                    section_name = a.section, section_first = i }
            end
            prev = a.section
            local cur_mark = (i == cur) and CUR_MARK or " "
            local read_mark = Model.is_read(backlog.state, a.key) and READ_MARK or " "
            local indent = a.section and "    " or ""
            items[#items + 1] = {
                text = indent .. cur_mark .. " " .. read_mark .. "  " .. a.title,
                mandatory = tostring(a.start_page),
                bold = (i == cur),
                article_index = i,
            }
            if i == cur then cur_pos = #items end
        end
        return items, cur_pos
    end

    local function row_pos_of(items, field, value)
        for p, it in ipairs(items) do
            if it[field] == value then return p end
        end
        return 1
    end

    local menu, container
    menu = Menu:new{
        title = title_text(),
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            local target = item.article_index or item.section_first -- header tap -> its first article
            if not target then return true end
            UIManager:close(container)
            backlog:gotoChapter(target)
        end,
        onMenuHold = function(_self, item)
            -- Rebuild after a change (counts shift), staying on the held row's page.
            if item.article_index then
                backlog:toggleRead(item.article_index)
                local items = build_items()
                menu:switchItemTable(title_text(), items, row_pos_of(items, "article_index", item.article_index))
            elseif item.section_name then -- long-press a section header -> mark the whole section
                backlog:toggleSectionRead(item.section_name)
                local items = build_items()
                menu:switchItemTable(title_text(), items, row_pos_of(items, "section_name", item.section_name))
            end
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
    -- Populate the list and open it on the current article's page.
    local items, cur_pos = build_items()
    menu:switchItemTable(title_text(), items, cur_pos)
    UIManager:show(container)
end

return ArticlesView
