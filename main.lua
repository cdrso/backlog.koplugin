local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ArticlesView = require("ui/articles_view")
local ReflinksOverlay = require("ui/reflinks_overlay")
local Model = require("lib/model")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AUTOMARK_MIN_FRACTION = 0.5

-- lightenRect factors for the "Faded links" setting; "off" is absent -> nil.
local FADE_LEVELS = { subtle = 0.25, medium = 0.4, strong = 0.6 }

local Backlog = WidgetContainer:extend{
    name = "backlog",
    is_doc_only = true,
}

function Backlog:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.chapters = {}
    self.state = Model.new()
    self.cur_page = nil
    self.prev_index = nil
    self.prev_page = nil
    self.max_seen_page = nil
end

function Backlog:getAutoMarkMode()
    return G_reader_settings:readSetting("backlog_automark_mode", "end")
end

function Backlog:_rebuildChapters()
    if self.ui.toc then
        self.ui.toc:fillToc() -- force the document TOC to be built before we read it
    end
    local toc = self.ui.toc and self.ui.toc.toc or {}
    local page_count = self.document:getPageCount()
    self.chapters = Model.build_articles(toc, page_count)
    logger.dbg("Backlog: built", #self.chapters, "chapters")
end

-- Opt this book in to tracking. Called the first time the user opens the Backlog
-- flow for the book. Tracking is per-book and persisted; nothing happens (and
-- nothing is written to the sidecar) for books that are never opted in.
function Backlog:_ensureTracked()
    if not self.state.tracked then
        self.state.tracked = true
        logger.dbg("Backlog: now tracking this book")
    end
    if #self.chapters == 0 then
        self:_rebuildChapters()
    end
end

function Backlog:onReaderReady()
    local stored = self.ui.doc_settings:readSetting("backlog")
    self.state = (stored and stored.read) and stored or Model.new()
    if self.state.tracked then
        self:_rebuildChapters() -- so auto-marking can run from the start
    end
    self:_registerReflinksOverlay()
end

function Backlog:_registerReflinksOverlay()
    if self._reflinks_registered then return end
    local view = self.ui and self.ui.view
    if not (view and view.registerViewModule) then return end
    self.reflinks_overlay = ReflinksOverlay:new{ backlog = self }
    view:registerViewModule("backlog_reflinks", self.reflinks_overlay)
    self._reflinks_registered = true
end

function Backlog:getReflinksFadeMode()
    return G_reader_settings:readSetting("backlog_reflinks_fade", "medium")
end

-- lightenRect factor for the current mode, or nil when "off".
function Backlog:getReflinksFade()
    return FADE_LEVELS[self:getReflinksFadeMode()]
end

function Backlog:_repaintPage()
    local view = self.ui and self.ui.view
    if view and view.dialog then UIManager:setDirty(view.dialog, "ui") end
end

function Backlog:onDocumentRerendered()
    -- Page numbers changed; rebuild ranges (state is keyed by xpointer, so it survives).
    if self.state.tracked then
        self:_rebuildChapters()
    end
    self.prev_index, self.prev_page, self.max_seen_page = nil, nil, nil
end

function Backlog:onSaveSettings()
    if self.state.tracked then
        self.ui.doc_settings:saveSetting("backlog", self.state)
    end
end

-- Current chapter index from the live reading position.
function Backlog:currentIndex()
    if not self.cur_page or #self.chapters == 0 then return nil end
    return Model.index_for_page(self.chapters, self.cur_page)
end

-- Reflowable docs emit PosUpdate; paged docs emit PageUpdate.
function Backlog:onPosUpdate(_pos, pageno)
    self:_onPosition(pageno)
end

function Backlog:onPageUpdate(pageno)
    self:_onPosition(pageno)
end

function Backlog:_onPosition(page)
    if not page then return end
    self.cur_page = page
    if not self.state.tracked then return end

    local cur = Model.index_for_page(self.chapters, page)
    local contiguous = self.prev_page ~= nil and math.abs(page - self.prev_page) <= 1

    if cur and contiguous then
        if cur == self.prev_index then
            self.max_seen_page = math.max(self.max_seen_page or page, page)
        else
            self.max_seen_page = page -- entered a (new) chapter by reading
        end
        local prev_frac = 0
        if self.prev_index and self.chapters[self.prev_index] then
            local p = self.chapters[self.prev_index]
            local len = p.end_page - p.start_page + 1
            prev_frac = ((self.max_seen_page or p.start_page) - p.start_page + 1) / len
        end
        local target = Model.should_automark{
            mode = self:getAutoMarkMode(),
            prev_index = self.prev_index,
            cur_index = cur,
            is_chapter_end = self.chapters[cur] and page >= self.chapters[cur].end_page or false,
            prev_read_fraction = prev_frac,
            min_fraction = AUTOMARK_MIN_FRACTION,
        }
        if target and not Model.is_read(self.state, self.chapters[target].key) then
            self:_markRead(target)
        end
    end

    self.prev_page = page
    self.prev_index = cur
end

function Backlog:_markRead(index)
    local ch = self.chapters[index]
    if not ch then return end
    Model.set_read(self.state, ch.key, os.time())
    logger.dbg("Backlog: marked read:", ch.title)
    UIManager:show(Notification:new{ text = T(_("Backlog: \"%1\" read"), ch.title) })
    self:_repaintPage() -- refresh faded cross-reference links to this article
end

function Backlog:gotoChapter(index)
    local ch = self.chapters[index]
    if not ch or not ch.key then return end
    self.ui.link:addCurrentLocationToStack()
    self.ui:handleEvent(Event:new("GotoXPointer", ch.key, ch.key))
end

function Backlog:toggleRead(index)
    local ch = self.chapters[index]
    if not ch then return end
    return Model.toggle(self.state, ch.key, os.time())
end

-- Mark every article in a section read, or all unread if they already all are.
function Backlog:toggleSectionRead(section)
    local all_read = true
    for _, a in ipairs(self.chapters) do
        if a.section == section and not Model.is_read(self.state, a.key) then
            all_read = false
            break
        end
    end
    local ts = os.time()
    for _, a in ipairs(self.chapters) do
        if a.section == section then
            if all_read then Model.set_unread(self.state, a.key)
            else Model.set_read(self.state, a.key, ts) end
        end
    end
end

function Backlog:onShowBacklog()
    self:_ensureTracked()
    if #self.chapters == 0 then
        UIManager:show(Notification:new{ text = _("Backlog: this book has no chapters to track") })
        return true
    end
    ArticlesView.show(self)
    return true
end

function Backlog:onBacklogNextUnread()
    self:_ensureTracked()
    if #self.chapters == 0 then return true end
    local idx = Model.next_unread(self.chapters, self.state, self:currentIndex())
    if idx then
        self:gotoChapter(idx)
    else
        UIManager:show(Notification:new{ text = _("Backlog: all read") })
    end
    return true
end

function Backlog:onBacklogToggleRead()
    self:_ensureTracked()
    local cur = self:currentIndex()
    if not cur then return true end
    local now = self:toggleRead(cur)
    UIManager:show(Notification:new{ text = now and _("Marked read") or _("Marked unread") })
    self:_repaintPage()
    return true
end

function Backlog:onDispatcherRegisterActions()
    Dispatcher:registerAction("backlog_show",
        { category = "none", event = "ShowBacklog", title = _("Backlog: articles"), reader = true })
    Dispatcher:registerAction("backlog_next_unread",
        { category = "none", event = "BacklogNextUnread", title = _("Backlog: next unread"), reader = true })
    Dispatcher:registerAction("backlog_toggle_read",
        { category = "none", event = "BacklogToggleRead", title = _("Backlog: mark current read/unread"), reader = true })
end

function Backlog:addToMainMenu(menu_items)
    menu_items.backlog = {
        text = _("Backlog (articles read)"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show articles"),
                callback = function() self:onShowBacklog() end,
            },
            {
                text = _("Jump to next unread"),
                callback = function() self:onBacklogNextUnread() end,
            },
            {
                text = _("Auto-mark read when…"),
                sub_item_table = {
                    self:_modeRadio(_("Reaching the article's end"), "end"),
                    self:_modeRadio(_("Leaving the article"), "leaving"),
                    self:_modeRadio(_("Either"), "either"),
                    self:_modeRadio(_("Off (manual only)"), "off"),
                },
            },
            {
                text = _("Fade links to read articles"),
                sub_item_table = {
                    self:_fadeRadio(_("Off"), "off"),
                    self:_fadeRadio(_("Subtle"), "subtle"),
                    self:_fadeRadio(_("Medium"), "medium"),
                    self:_fadeRadio(_("Strong"), "strong"),
                },
            },
        },
    }
end

function Backlog:_modeRadio(text, value)
    return {
        text = text,
        checked_func = function() return self:getAutoMarkMode() == value end,
        radio = true,
        callback = function() G_reader_settings:saveSetting("backlog_automark_mode", value) end,
    }
end

function Backlog:_fadeRadio(text, value)
    return {
        text = text,
        checked_func = function() return self:getReflinksFadeMode() == value end,
        radio = true,
        callback = function()
            G_reader_settings:saveSetting("backlog_reflinks_fade", value)
            self:_repaintPage()
        end,
    }
end

return Backlog
