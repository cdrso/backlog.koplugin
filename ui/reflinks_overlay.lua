-- Persistent ReaderView overlay: fades (lowers the contrast of) each in-text
-- cross-reference link whose target article is already marked read, so read
-- references look "visited". Painted over the finished page via
-- registerViewModule, using crengine's own per-line link rects (link.segments)
-- -- so it never touches the text flow (no reflow) and never overlaps neighbours.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Model = require("lib/model")

local ReflinksOverlay = WidgetContainer:extend{ backlog = nil }

function ReflinksOverlay:paintTo(bb, x, y)
    local b = self.backlog
    if not b or not b.state or not b.state.tracked or #b.chapters == 0 then return end
    local fade = b:getReflinksFade() -- nil when the setting is "off"
    if not fade then return end
    local doc = b.document
    if not doc or not doc.getPageLinks then return end
    local ok, links = pcall(doc.getPageLinks, doc, true) -- internal links only
    if not ok or type(links) ~= "table" then return end
    local cur_idx = b.currentIndex and b:currentIndex() or nil

    for _, link in ipairs(links) do
        -- link.section is the href; resolve to the chapter it lands in (shared
        -- with the save-for-later button). Perf: resolved per paint, but pages
        -- carry few links so it stays cheap -- add a cache only if it profiles hot.
        local idx = b:_chapterIndexForXPointer(link.section)
        -- skip intra-article links (e.g. footnotes); only fade cross-references
        if idx and idx ~= cur_idx and Model.is_read(b.state, b.chapters[idx].key) then
            local segs = link.segments
            if type(segs) == "table" then
                for _, s in ipairs(segs) do
                    if s.x0 and s.y0 and s.x1 and s.y1 then
                        bb:lightenRect(x + s.x0, y + s.y0, s.x1 - s.x0, s.y1 - s.y0, fade)
                    end
                end
            end
        end
    end
end

return ReflinksOverlay
