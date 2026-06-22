local ButtonDialog = require("ui/widget/buttondialog")
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
local SAVED_MARK = "\226\152\134" -- U+2606 white (outline) star

local ArticlesView = {}

-- backlog: the plugin instance (provides .chapters [the article list], .state,
-- :currentIndex, :gotoChapter, :toggleRead).
function ArticlesView.show(backlog)
    local arts = backlog.chapters
    local total = #arts

    local function title_text()
        local read = Model.count_read(arts, backlog.state)
        local nsaved = Model.count_saved(arts, backlog.state)
        if nsaved > 0 then
            return T(_("Articles — %1/%2 read · %3 saved"), read, total, nsaved)
        end
        return T(_("Articles — %1/%2 read"), read, total)
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

    -- Status glyph: saved (☆) takes priority over read (✓), else blank. ▶ is a
    -- separate leading marker for the current article.
    local function status_mark(a)
        if Model.is_saved(backlog.state, a.key) then return SAVED_MARK end
        if Model.is_read(backlog.state, a.key) then return READ_MARK end
        return " "
    end

    local function article_row(i, a, indent, cur)
        local cur_mark = (i == cur) and CUR_MARK or " "
        return {
            text = indent .. cur_mark .. " " .. status_mark(a) .. "  " .. a.title,
            mandatory = tostring(a.start_page),
            bold = (i == cur),
            article_index = i,
        }
    end

    -- Rows: a pinned "Saved" group first (when any), then the normal list — a
    -- non-tappable header before each new section, then its articles (indented).
    -- Flat books (section=nil) get no section headers/indent. Returns the rows +
    -- the row index of the current article (to open on it; its in-context row).
    local function build_items()
        local items, cur, cur_pos, prev = {}, backlog:currentIndex(), 1, nil
        local nsaved = Model.count_saved(arts, backlog.state)
        if nsaved > 0 then
            items[#items + 1] = { text = SAVED_MARK .. " " .. _("Saved") .. " — " .. nsaved,
                bold = true, saved_group = true }
            for i, a in ipairs(arts) do
                if Model.is_saved(backlog.state, a.key) then
                    items[#items + 1] = article_row(i, a, "    ", cur)
                end
            end
        end
        for i, a in ipairs(arts) do
            if a.section and a.section ~= prev then
                local r, t = section_counts(a.section)
                items[#items + 1] = { text = a.section .. "  —  " .. r .. "/" .. t, bold = true,
                    section_name = a.section, section_first = i }
            end
            prev = a.section
            local indent = a.section and "    " or ""
            items[#items + 1] = article_row(i, a, indent, cur)
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
    -- Rebuild after a change (counts shift), staying on the affected row's page.
    local function refresh(field, value)
        local items = build_items()
        menu:switchItemTable(title_text(), items, row_pos_of(items, field, value))
    end
    -- Long-press an article -> a small dialog offering its two manual marks.
    local function open_article_actions(i)
        local a = arts[i]
        local is_read = Model.is_read(backlog.state, a.key)
        local is_saved = Model.is_saved(backlog.state, a.key)
        local dlg
        dlg = ButtonDialog:new{
            title = a.title,
            title_align = "center",
            buttons = {
                {{
                    text = is_read and _("Mark unread") or _("Mark read"),
                    callback = function()
                        UIManager:close(dlg)
                        backlog:toggleRead(i)
                        refresh("article_index", i)
                    end,
                }},
                {{
                    text = is_saved and _("Unsave") or _("Save for later"),
                    callback = function()
                        UIManager:close(dlg)
                        backlog:toggleSaved(i)
                        refresh("article_index", i)
                    end,
                }},
            },
        }
        UIManager:show(dlg)
    end
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
            if item.article_index then
                open_article_actions(item.article_index)
            elseif item.section_name then -- long-press a section header -> mark the whole section
                backlog:toggleSectionRead(item.section_name)
                refresh("section_name", item.section_name)
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
