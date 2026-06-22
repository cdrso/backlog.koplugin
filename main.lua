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

-- lightenRect factors for the "Faded links" setting; "off" is absent -> nil.
local FADE_LEVELS = { subtle = 0.25, medium = 0.4, strong = 0.6 }
local SAVED_MARK = "\226\152\134" -- U+2606 white (outline) star -- the "save for later" glyph

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
    -- migrate the old multi-mode auto-mark setting to the on/off toggle
    local mode = G_reader_settings:readSetting("backlog_automark_mode")
    if mode then
        if mode == "off" then G_reader_settings:saveSetting("backlog_automark", false) end
        G_reader_settings:delSetting("backlog_automark_mode")
    end
end

function Backlog:getAutoMark()
    return G_reader_settings:nilOrTrue("backlog_automark")
end

function Backlog:getNotify()
    return G_reader_settings:nilOrTrue("backlog_notify")
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
    self.state.saved = self.state.saved or {} -- migrate sidecars written before "save for later"
    if self.state.tracked then
        self:_rebuildChapters() -- so auto-marking can run from the start
    end
    self:_registerReflinksOverlay()
    self:_registerSaveHighlightButton()
end

function Backlog:_registerReflinksOverlay()
    if self._reflinks_registered then return end
    local view = self.ui and self.ui.view
    if not (view and view.registerViewModule) then return end
    self.reflinks_overlay = ReflinksOverlay:new{ backlog = self }
    view:registerViewModule("backlog_reflinks", self.reflinks_overlay)
    self._reflinks_registered = true
end

-- Which of our articles does this destination xpointer land in? nil if it does
-- not resolve to a tracked article (external/footnote/unknown link). Shared by
-- the reflinks overlay and the "Save for later" highlight button.
function Backlog:_chapterIndexForXPointer(xp)
    if not xp or xp == "" then return nil end
    local doc = self.document
    if not doc or not doc.getPageFromXPointer then return nil end
    local ok, page = pcall(doc.getPageFromXPointer, doc, xp)
    if not ok or not page then return nil end
    return Model.index_for_page(self.chapters, page)
end

-- The destination xpointer of the link currently under a long-press, if any.
local function selected_link_xpointer(highlight)
    local sl = highlight.selected_link
    if not sl then return nil end
    return sl.xpointer or (type(sl.link) == "table" and sl.link.xpointer) or nil
end

-- Add a "Save for later" button to KOReader's long-press selection popup, shown
-- only when the press is on a link that resolves to a tracked article (mirrors
-- KOReader's own "Follow Link", gated on selected_link). addToHighlightDialog is
-- a public extension point, so this is not a monkey-patch.
function Backlog:_registerSaveHighlightButton()
    if self._save_button_registered then return end
    local hl = self.ui and self.ui.highlight
    if not (hl and hl.addToHighlightDialog) then return end
    local backlog = self
    hl:addToHighlightDialog("12_backlog_save", function(this)
        return {
            text = SAVED_MARK .. " " .. _("Save for later"),
            show_in_highlight_dialog_func = function()
                return backlog.state.tracked
                    and backlog:_chapterIndexForXPointer(selected_link_xpointer(this)) ~= nil
            end,
            callback = function()
                local idx = backlog:_chapterIndexForXPointer(selected_link_xpointer(this))
                if idx then backlog:_markSaved(idx) end
                this:onClose()
            end,
        }
    end)
    self._save_button_registered = true
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
    self.prev_index, self.prev_page = nil, nil
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
    if self:getAutoMark() then
        local target = Model.automark_on_step(self.prev_index, self.prev_page, cur, page)
        if target then self:_markRead(target) end
    end

    self.prev_page = page
    self.prev_index = cur
end

function Backlog:_markRead(index)
    local ch = self.chapters[index]
    if not ch then return end
    local was_read = Model.is_read(self.state, ch.key)
    Model.mark_read(self.state, ch.key, os.time()) -- sets read (keeps first-read ts) + clears the ☆
    if was_read then return end -- already read (e.g. a re-read); ☆ dropped, nothing new to announce
    logger.dbg("Backlog: marked read:", ch.title)
    if self:getNotify() then
        UIManager:show(Notification:new{ text = T(_("Backlog: \"%1\" read"), ch.title) })
    end
    self:_repaintPage() -- refresh faded cross-reference links to this article
end

-- Flag an article as "to read later". An explicit user action, so it always
-- confirms with a toast (not gated by the read-notification setting).
function Backlog:_markSaved(index)
    local ch = self.chapters[index]
    if not ch then return end
    Model.mark_saved(self.state, ch.key, os.time()) -- saving clears any read mark (save precedence)
    logger.dbg("Backlog: saved for later:", ch.title)
    UIManager:show(Notification:new{ text = T(_("Saved for later: \"%1\""), ch.title) })
    self:_repaintPage() -- a now-unread article's in-text links should stop being faded
end

-- Paged past the final page: the last article is finished. Broadcast event, so
-- do not consume it (ReaderStatus shows its end-of-book dialog on the same one).
function Backlog:onEndOfBook()
    if self.state.tracked and self:getAutoMark() and #self.chapters > 0 then
        self:_markRead(#self.chapters)
    end
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
    if Model.is_read(self.state, ch.key) then
        Model.set_unread(self.state, ch.key)
        return false
    end
    Model.mark_read(self.state, ch.key, os.time()) -- marking read also clears the ☆
    return true
end

function Backlog:toggleSaved(index)
    local ch = self.chapters[index]
    if not ch then return end
    return Model.toggle_saved(self.state, ch.key, os.time())
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
            else Model.mark_read(self.state, a.key, ts) end
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

function Backlog:onBacklogSaveCurrent()
    self:_ensureTracked()
    local cur = self:currentIndex()
    if not cur then return true end
    self:_markSaved(cur)
    return true
end

function Backlog:onBacklogNextSaved()
    self:_ensureTracked()
    if #self.chapters == 0 then return true end
    local idx = Model.next_saved(self.chapters, self.state, self:currentIndex())
    if idx then
        self:gotoChapter(idx)
    else
        UIManager:show(Notification:new{ text = _("Backlog: no saved articles") })
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
    Dispatcher:registerAction("backlog_save_current",
        { category = "none", event = "BacklogSaveCurrent", title = _("Backlog: save current for later"), reader = true })
    Dispatcher:registerAction("backlog_next_saved",
        { category = "none", event = "BacklogNextSaved", title = _("Backlog: next saved"), reader = true })
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
                text = _("Jump to next saved"),
                callback = function() self:onBacklogNextSaved() end,
            },
            {
                text = _("Auto-mark articles read"),
                checked_func = function() return self:getAutoMark() end,
                callback = function() G_reader_settings:flipNilOrTrue("backlog_automark") end,
            },
            {
                text = _("Show read notifications"),
                checked_func = function() return self:getNotify() end,
                callback = function() G_reader_settings:flipNilOrTrue("backlog_notify") end,
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
