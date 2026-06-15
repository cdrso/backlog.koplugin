-- Pure logic for the Backlog plugin. No KOReader dependencies, so it is unit
-- testable under bare luajit. An "article" record is { key, title, start_page,
-- end_page, section }; "state" is { version, read = { [key] = timestamp } }.
local Model = {}

function Model.new()
    return { version = 1, read = {} }
end

function Model.is_read(state, key)
    return state.read[key] ~= nil
end

function Model.set_read(state, key, ts)
    state.read[key] = ts or 0
end

function Model.set_unread(state, key)
    state.read[key] = nil
end

function Model.toggle(state, key, ts)
    if Model.is_read(state, key) then
        Model.set_unread(state, key)
        return false
    else
        Model.set_read(state, key, ts)
        return true
    end
end

-- toc_items: array of { title, page, depth, xpointer } (ReaderToc's self.toc).
-- doc_page_count: total pages in the document.
-- Returns the trackable articles -- the LEAF TOC entries (those with no deeper
-- child), in order, as { key, title, start_page, end_page, section }. `section`
-- is the title of the nearest preceding shallower entry (the parent), or nil for
-- a top-level leaf. So "article" = leaf content: a flat anthology tracks its
-- depth-1 entries (each a leaf, section=nil); a section-nested magazine (e.g. The
-- Economist) tracks the depth-2 articles, labelled by their depth-1 section.
function Model.build_articles(toc_items, doc_page_count)
    local arts = {}
    for i, it in ipairs(toc_items) do
        local nxt = toc_items[i + 1]
        local is_leaf = nxt == nil or nxt.depth <= it.depth
        if is_leaf then
            local section
            for j = i - 1, 1, -1 do -- nearest shallower ancestor = the section
                if toc_items[j].depth < it.depth then
                    section = toc_items[j].title
                    break
                end
            end
            if arts[#arts] then arts[#arts].end_page = it.page - 1 end
            arts[#arts + 1] = {
                key = it.xpointer or ("idx" .. i .. ":" .. tostring(it.title)),
                title = it.title,
                start_page = it.page,
                section = section,
            }
        end
    end
    if arts[#arts] then arts[#arts].end_page = doc_page_count end
    return arts
end

function Model.index_for_page(chapters, page)
    for i, ch in ipairs(chapters) do
        if page >= ch.start_page and page <= ch.end_page then
            return i
        end
    end
    return nil
end

function Model.count_read(chapters, state)
    local n = 0
    for _, ch in ipairs(chapters) do
        if Model.is_read(state, ch.key) then
            n = n + 1
        end
    end
    return n
end

-- Returns index, key of the first unread chapter strictly after from_index,
-- wrapping around to the start. from_index may be nil (treated as 0).
-- Returns nil if all chapters are read.
function Model.next_unread(chapters, state, from_index)
    local n = #chapters
    if n == 0 then return nil end
    local start = from_index or 0
    for step = 1, n do
        local i = ((start + step - 1) % n) + 1
        if not Model.is_read(state, chapters[i].key) then
            return i, chapters[i].key
        end
    end
    return nil
end

-- Auto-mark decision for one reading-position step. Returns the article index to
-- mark read, or nil. A contiguous forward step that crosses out of prev_index
-- means the reader turned PAST that article's last page, so it is finished. The
-- final article has no page after it; the caller marks it on the EndOfBook event.
function Model.automark_on_step(prev_index, prev_page, cur_index, page)
    if not (prev_index and cur_index and prev_page) then return nil end
    if cur_index > prev_index and page == prev_page + 1 then
        return prev_index
    end
    return nil
end

return Model
