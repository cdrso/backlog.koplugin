-- Busted spec for the Backlog model (pure logic, no KOReader dependencies).
-- Run with busted (`busted spec/unit/model_spec.lua`) or, with no install, via
-- the LuaJIT runner (`luajit spec/run.lua`).
package.path = "./?.lua;" .. package.path
local Model = require("lib.model")

describe("read-state", function()
    it("new() returns empty versioned state", function()
        local s = Model.new()
        assert.are.equal(1, s.version)
        assert.is_false(Model.is_read(s, "x"))
    end)
    it("set_read / is_read", function()
        local s = Model.new()
        Model.set_read(s, "x", 111)
        assert.is_true(Model.is_read(s, "x"))
        assert.are.equal(111, s.read["x"])
    end)
    it("set_unread clears", function()
        local s = Model.new()
        Model.set_read(s, "x", 111)
        Model.set_unread(s, "x")
        assert.is_false(Model.is_read(s, "x"))
    end)
    it("toggle flips and returns new status", function()
        local s = Model.new()
        assert.is_true(Model.toggle(s, "x", 222))
        assert.is_true(Model.is_read(s, "x"))
        assert.is_false(Model.toggle(s, "x", 222))
        assert.is_false(Model.is_read(s, "x"))
    end)
end)

describe("build_articles", function()
    it("flat TOC: every depth-1 entry is a leaf article (section=nil)", function()
        local toc = {
            { title = "A", page = 1, depth = 1, xpointer = "xpA" },
            { title = "B", page = 5, depth = 1, xpointer = "xpB" },
            { title = "C", page = 9, depth = 1, xpointer = "xpC" },
        }
        local a = Model.build_articles(toc, 12)
        assert.are.equal(3, #a)
        assert.are.equal("xpA", a[1].key)
        assert.is_nil(a[1].section)
        assert.are.equal(1, a[1].start_page); assert.are.equal(4, a[1].end_page)
        assert.are.equal(5, a[2].start_page); assert.are.equal(8, a[2].end_page)
        assert.are.equal(9, a[3].start_page); assert.are.equal(12, a[3].end_page)
    end)
    it("section-nested TOC: tracks the leaf articles, labelled by their section", function()
        local toc = {
            { title = "Leaders",  page = 1, depth = 1, xpointer = "xpL" },
            { title = "Art 1",    page = 2, depth = 2, xpointer = "xp1" },
            { title = "Art 2",    page = 5, depth = 2, xpointer = "xp2" },
            { title = "Briefing", page = 9, depth = 1, xpointer = "xpB" },
            { title = "Art 3",    page = 9, depth = 2, xpointer = "xp3" },
        }
        local a = Model.build_articles(toc, 12)
        assert.are.equal(3, #a) -- the 3 leaf articles, not the 2 sections
        assert.are.equal("Art 1", a[1].title)
        assert.are.equal("Leaders", a[1].section)
        assert.are.equal(2, a[1].start_page); assert.are.equal(4, a[1].end_page)
        assert.are.equal("Art 2", a[2].title)
        assert.are.equal("Leaders", a[2].section)
        assert.are.equal("Art 3", a[3].title)
        assert.are.equal("Briefing", a[3].section)
        assert.are.equal(9, a[3].start_page); assert.are.equal(12, a[3].end_page)
    end)
    it("mixed TOC: standalone depth-1 (section=nil) alongside a nested leaf", function()
        local toc = {
            { title = "Cover", page = 1, depth = 1, xpointer = "xpCov" }, -- standalone
            { title = "Sec",   page = 3, depth = 1, xpointer = "xpSec" }, -- section
            { title = "Inner", page = 4, depth = 2, xpointer = "xpIn" },
        }
        local a = Model.build_articles(toc, 6)
        assert.are.equal(2, #a)
        assert.are.equal("Cover", a[1].title); assert.is_nil(a[1].section)
        assert.are.equal("Inner", a[2].title); assert.are.equal("Sec", a[2].section)
    end)
    it("falls back to a synthetic key when xpointer missing", function()
        local a = Model.build_articles({ { title = "T", page = 1, depth = 1 } }, 3)
        assert.are.equal("idx1:T", a[1].key)
    end)
end)

describe("index_for_page", function()
    local ch = {
        { key = "a", start_page = 1, end_page = 4 },
        { key = "b", start_page = 5, end_page = 8 },
    }
    it("maps a page to its chapter index", function()
        assert.are.equal(1, Model.index_for_page(ch, 3))
        assert.are.equal(2, Model.index_for_page(ch, 5))
        assert.are.equal(2, Model.index_for_page(ch, 8))
    end)
    it("returns nil before the first chapter", function()
        assert.is_nil(Model.index_for_page({ { key = "a", start_page = 2, end_page = 4 } }, 1))
    end)
end)

describe("count_read / next_unread", function()
    local ch = { { key = "a" }, { key = "b" }, { key = "c" }, { key = "d" } }
    it("counts read chapters present in the list", function()
        local s = Model.new()
        Model.set_read(s, "b", 1)
        Model.set_read(s, "d", 1)
        Model.set_read(s, "ghost", 1)
        assert.are.equal(2, Model.count_read(ch, s))
    end)
    it("finds the next unread after from_index, wrapping", function()
        local s = Model.new()
        Model.set_read(s, "b", 1)
        local idx, key = Model.next_unread(ch, s, 1)
        assert.are.equal(3, idx)
        assert.are.equal("c", key)
    end)
    it("wraps around to find earlier unread", function()
        local s = Model.new()
        Model.set_read(s, "c", 1)
        Model.set_read(s, "d", 1)
        local idx = Model.next_unread(ch, s, 3)
        assert.are.equal(1, idx)
    end)
    it("returns nil when everything is read", function()
        local s = Model.new()
        for _, c in ipairs(ch) do Model.set_read(s, c.key, 1) end
        assert.is_nil(Model.next_unread(ch, s, nil))
    end)
end)

describe("should_automark", function()
    it("off -> never", function()
        assert.is_nil(Model.should_automark{ mode = "off", prev_index = 1, cur_index = 1, is_chapter_end = true })
    end)
    it("end -> marks current at chapter end, same chapter", function()
        assert.are.equal(1, Model.should_automark{ mode = "end", prev_index = 1, cur_index = 1, is_chapter_end = true })
        assert.is_nil(Model.should_automark{ mode = "end", prev_index = 1, cur_index = 1, is_chapter_end = false })
    end)
    it("end -> does not mark when crossing into a new chapter", function()
        assert.is_nil(Model.should_automark{ mode = "end", prev_index = 1, cur_index = 2, is_chapter_end = false })
    end)
    it("leaving -> marks previous when crossing, if read enough", function()
        assert.are.equal(1, Model.should_automark{ mode = "leaving", prev_index = 1, cur_index = 2, prev_read_fraction = 0.9, min_fraction = 0.5 })
        assert.is_nil(Model.should_automark{ mode = "leaving", prev_index = 1, cur_index = 2, prev_read_fraction = 0.1, min_fraction = 0.5 })
    end)
    it("either -> end-rule when staying, leaving-rule when crossing", function()
        assert.are.equal(2, Model.should_automark{ mode = "either", prev_index = 2, cur_index = 2, is_chapter_end = true })
        assert.are.equal(1, Model.should_automark{ mode = "either", prev_index = 1, cur_index = 2, prev_read_fraction = 1.0, min_fraction = 0.5 })
    end)
    it("nil context -> nil", function()
        assert.is_nil(Model.should_automark{ mode = "end", prev_index = nil, cur_index = 1, is_chapter_end = true })
    end)
end)
