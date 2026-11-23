-- Drives the real view (buffer, window, keymaps) against a fake DAP session.
local fake = require 'tests.fake_dap'
local render = require 'dap-memview.render'

local function le64(n)
  local out = {}
  for _ = 1, 8 do
    out[#out + 1] = string.char(n % 256)
    n = math.floor(n / 256)
  end
  return table.concat(out)
end

-- 0x1000: a valid pointer to 0x2000, a wild pointer, then padding.
local PAGE = le64(0x2000) .. le64(0xdead0000) .. string.rep('\0', 16) .. string.rep('A', 224)
local TARGET = 'pointee!' .. string.rep('\0', 248)

describe('view', function()
  local view, notices, original_notify

  local function header()
    local buf = vim.fn.bufnr 'dap-memview://memory'
    return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  end

  --- Wait until the first header line contains `text`.
  local function wait_header(text)
    local ok = vim.wait(1000, function()
      return vim.fn.bufnr 'dap-memview://memory' ~= -1 and (header() or ''):find(text, 1, true) ~= nil
    end)
    assert(ok, ('header never showed %q; last: %s'):format(text, vim.fn.bufnr 'dap-memview://memory' ~= -1 and header() or '<no buffer>'))
  end

  local function wait_notice(text)
    local ok = vim.wait(1000, function()
      for _, msg in ipairs(notices) do
        if msg:find(text, 1, true) then
          return true
        end
      end
      return false
    end)
    assert(ok, ('never notified %q; got: %s'):format(text, vim.inspect(notices)))
  end

  --- Put the cursor on byte `j` of data row `row` (both 1-based), in the view window.
  local function cursor_on(row, j)
    local win = vim.fn.bufwinid(vim.fn.bufnr 'dap-memview://memory')
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { 2 + row, render.byte_col(j, 16) })
  end

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
  end

  before_each(function()
    fake.install {
      evaluate = { page = { result = '0x1000' } },
      memory = { ['0x1000+0'] = PAGE, ['0x1000+256'] = string.rep('B', 256), ['0x2000+0'] = TARGET },
    }
    require('dap-memview.config').setup {}
    view = require 'dap-memview.view'
    notices = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
  end)

  after_each(function()
    vim.notify = original_notify
    view.reset()
    fake.uninstall()
  end)

  it('opens a view on a resolved expression', function()
    view.open 'page'
    wait_header 'page  @ 0x1000  offset +0  (256 bytes)'
  end)

  it('opens no window when the target cannot be read', function()
    view.open '0xbad000'
    wait_notice 'readMemory'
    assert.are.equal(-1, vim.fn.bufnr 'dap-memview://memory')
    assert.are.equal(1, #vim.api.nvim_list_wins())
  end)

  it('follows the pointer under the cursor and comes back', function()
    view.open 'page'
    wait_header 'page  @ 0x1000'
    cursor_on(1, 1)
    press '<CR>'
    wait_header '0x2000  @ 0x2000  offset +0'
    press '<BS>'
    wait_header 'page  @ 0x1000'
  end)

  it('follows from the second hex digit of a byte and from the ASCII column', function()
    view.open 'page'
    wait_header 'page  @ 0x1000'
    local win = vim.fn.bufwinid(vim.fn.bufnr 'dap-memview://memory')
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { 3, render.byte_col(1, 16) + 1 })
    press '<CR>'
    wait_header '0x2000  @ 0x2000'
    press '<BS>'
    wait_header 'page  @ 0x1000'
    vim.api.nvim_win_set_cursor(win, { 3, render.byte_col(16, 16) + 2 + 2 + 1 }) -- first ASCII char
    press '<CR>'
    wait_header '0x2000  @ 0x2000'
  end)

  it('stays put when the pointer under the cursor is unreadable', function()
    view.open 'page'
    wait_header 'page  @ 0x1000'
    cursor_on(1, 9) -- the wild pointer
    press '<CR>'
    wait_notice 'readMemory'
    assert.is_truthy(header():find('page  @ 0x1000  offset +0', 1, true))
    -- nothing was pushed: the view is still at its first location
    press '<BS>'
    wait_notice 'already at the first location'
    -- and a manual refresh re-reads the original region, not the bad one
    notices = {}
    press 'r'
    vim.wait(100)
    assert.are.same({}, notices)
    assert.is_truthy(header():find('page  @ 0x1000', 1, true))
  end)

  it('refuses a null pointer, a header line, and a pointer that runs off the dump', function()
    view.open 'page'
    wait_header 'page  @ 0x1000'
    cursor_on(2, 1) -- 8 zero bytes
    press '<CR>'
    wait_notice 'null pointer'
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    press '<CR>'
    wait_notice 'cursor is not on a byte'
    cursor_on(16, 10) -- 7 bytes left
    press '<CR>'
    wait_notice 'need 8 bytes'
    assert.is_truthy(header():find('page  @ 0x1000', 1, true))
  end)

  it('pages forward, and stays put when the next page is unmapped', function()
    view.open 'page'
    wait_header 'page  @ 0x1000'
    cursor_on(1, 1)
    press ']'
    wait_header 'page  @ 0x1100  offset +256'
    press ']' -- 0x1000+512 is not mapped
    wait_notice 'readMemory'
    assert.is_truthy(header():find('offset +256', 1, true))
    press '['
    wait_header 'page  @ 0x1000  offset +0'
  end)

  it('highlights only the bytes that changed between refreshes', function()
    local session = fake.install { memory = { ['0x1000+0'] = PAGE } }
    view.open '0x1000'
    wait_header '0x1000  @ 0x1000'
    local buf = vim.fn.bufnr 'dap-memview://memory'
    local ns = vim.api.nvim_get_namespaces()['dap-memview']
    local function changed()
      local cols = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        if m[4].hl_group == 'DapMemviewChanged' then
          cols[#cols + 1] = { m[2], m[3] }
        end
      end
      return cols
    end
    assert.are.same({}, changed())

    -- the debuggee writes byte 18 (row 2, byte 2), then we stop again
    local mutated = PAGE:sub(1, 17) .. 'Z' .. PAGE:sub(19)
    function session:request(_, args, cb)
      vim.schedule(function()
        cb(nil, { address = '0x1000', data = vim.base64.encode(mutated:sub(1, args.count)) })
      end)
    end
    view.refresh(true)
    assert(
      vim.wait(1000, function()
        return #changed() == 1
      end),
      'expected exactly one changed-byte highlight'
    )
    assert.are.same({ { 3, render.byte_col(2, 16) } }, changed())
  end)
end)
