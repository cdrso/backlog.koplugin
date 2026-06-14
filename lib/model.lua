-- Pure logic for the Backlog plugin. No KOReader dependencies, so it is unit
-- testable under bare luajit. A "chapter" record is { key, title, start_page,
-- end_page }; "state" is { version, read = { [key] = timestamp } }.
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
-- Returns array of { key, title, start_page, end_page } for depth-1 entries, in order.
function Model.build_chapters(toc_items, doc_page_count)
    local tops = {}
    for i, it in ipairs(toc_items) do
        if it.depth == 1 then
            if tops[#tops] then tops[#tops].end_page = it.page - 1 end
            tops[#tops + 1] = {
                key = it.xpointer or ("idx" .. i .. ":" .. tostring(it.title)),
                title = it.title,
                start_page = it.page,
            }
        end
    end
    if tops[#tops] then tops[#tops].end_page = doc_page_count end
    return tops
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

-- opts = { mode, prev_index, cur_index, is_chapter_end, prev_read_fraction, min_fraction }
-- Returns the chapter index to mark read, or nil. Assumes a contiguous (non-jump) move;
-- the caller filters out jumps before calling.
function Model.should_automark(opts)
    local mode = opts.mode or "end"
    if mode == "off" then return nil end
    local prev, cur = opts.prev_index, opts.cur_index
    if prev == nil or cur == nil then return nil end
    if cur == prev then
        -- stayed in the same chapter
        if (mode == "end" or mode == "either") and opts.is_chapter_end then
            return cur
        end
        return nil
    else
        -- crossed into a different chapter
        if mode == "leaving" or mode == "either" then
            if (opts.prev_read_fraction or 0) >= (opts.min_fraction or 0) then
                return prev
            end
        end
        return nil
    end
end

return Model
