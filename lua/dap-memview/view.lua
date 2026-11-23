-- Buffer/window management and changed-byte highlighting.
local config = require 'dap-memview.config'
local memory = require 'dap-memview.memory'
local render = require 'dap-memview.render'

local M = {}

local ns = vim.api.nvim_create_namespace 'dap-memview'
local hl_range = (vim.hl or vim.highlight).range -- vim.hl is 0.11+; vim.highlight on 0.10
local HEADER_LINES = 2

-- One view for the POC; multi-view is a v2 concern.
local state = {
  buf = nil,
  win = nil,
  expr = nil,
  memref = nil,
  offset = 0,
  last_data = nil, -- previous snapshot for diff highlighting
  history = {}, -- locations to return to after follow/goto (<BS>)
}

vim.api.nvim_set_hl(0, 'DapMemviewChanged', { default = true, link = 'DiffText' })
vim.api.nvim_set_hl(0, 'DapMemviewAddr', { default = true, link = 'LineNr' })
vim.api.nvim_set_hl(0, 'DapMemviewHeader', { default = true, link = 'Title' })

local function notify(msg, level)
  vim.notify('[dap-memview] ' .. msg, level or vim.log.levels.INFO)
end

local function buf_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

--- 1-based index into state.last_data for the byte under the cursor,
--- or nil when the cursor is not on a data row.
local function cursor_byte_index()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = pos[1] - HEADER_LINES
  if line < 1 or not state.last_data then
    return nil
  end
  local bpl = config.options.bytes_per_line
  local idx = (line - 1) * bpl + render.col_to_byte(pos[2], bpl)
  if idx > #state.last_data then
    return nil
  end
  return idx
end

local function push_history()
  table.insert(state.history, { memref = state.memref, offset = state.offset, expr = state.expr })
end

local follow, back -- defined below, once show() exists

local function ensure_buf()
  if buf_valid() then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'dap-memview://memory')
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'dap-memview'

  local km = config.options.keymaps
  local function map(lhs, fn, desc)
    if type(lhs) ~= 'string' or lhs == '' then
      return -- keymap disabled via `false`
    end
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = 'dap-memview: ' .. desc })
  end
  map(km.refresh, function()
    M.refresh(false)
  end, 'refresh')
  map(km.close, M.close, 'close')
  map(km.page_next, function()
    M.page(1)
  end, 'next page')
  map(km.page_prev, function()
    M.page(-1)
  end, 'previous page')
  map(km.goto_expr, function()
    vim.ui.input({ prompt = 'Memory expression: ', default = state.expr }, function(input)
      if input and input ~= '' then
        M.open(input)
      end
    end)
  end, 'view new expression')
  map(km.follow, function()
    follow()
  end, 'follow pointer at cursor')
  map(km.back, function()
    back()
  end, 'back to previous location')

  state.buf = buf
  return buf
end

local function ensure_win()
  ensure_buf()
  if win_valid() then
    vim.api.nvim_win_set_buf(state.win, state.buf)
    return state.win
  end
  local cur = vim.api.nvim_get_current_win()
  vim.cmd(('%s %dsplit'):format(config.options.window.position, config.options.window.height))
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = 'no'
  vim.wo[state.win].wrap = false
  vim.api.nvim_set_current_win(cur)
  return state.win
end

--- Render a snapshot into the buffer, highlighting bytes changed since the last one.
local function show(data, address_str)
  local opts = config.options
  local base_addr = tonumber(address_str) or 0
  local km = opts.keymaps
  local hints = {}
  local function hint(lhs, label)
    if type(lhs) == 'string' and lhs ~= '' then
      hints[#hints + 1] = ('[%s] %s'):format(lhs, label)
    end
  end
  hint(km.refresh, 'refresh')
  hint(km.page_prev, 'page back')
  hint(km.page_next, 'page fwd')
  hint(km.follow, 'follow ptr')
  hint(km.back, #state.history > 0 and ('back (%d)'):format(#state.history) or 'back')
  hint(km.goto_expr, 'goto expr')
  hint(km.close, 'quit')
  local header = {
    ('%s  @ %s  offset %+d  (%d bytes)'):format(state.expr or '?', address_str or '?', state.offset, #data),
    table.concat(hints, '  '),
  }
  local lines = render.format(data, base_addr, opts.bytes_per_line)

  local buf = ensure_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(vim.list_extend({}, header), lines))
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  hl_range(buf, ns, 'DapMemviewHeader', { 0, 0 }, { 0, -1 })
  for row = HEADER_LINES, HEADER_LINES + #lines - 1 do
    hl_range(buf, ns, 'DapMemviewAddr', { row, 0 }, { row, render.ADDR_WIDTH })
  end
  for _, i in ipairs(render.diff(state.last_data, data)) do
    local row = HEADER_LINES + math.floor((i - 1) / opts.bytes_per_line)
    local j = ((i - 1) % opts.bytes_per_line) + 1
    local col = render.byte_col(j, opts.bytes_per_line)
    hl_range(buf, ns, 'DapMemviewChanged', { row, col }, { row, col + 2 })
  end
  state.last_data = data
end

--- Read `target` ({ memref, offset, expr }) and make it the current view —
--- but only once the read has succeeded. A failed read (garbage pointer,
--- unmapped page) reports the error and leaves the view exactly as it was.
--- `before_commit` runs just before the state changes, for history bookkeeping.
local function navigate(target, before_commit)
  memory.read(target.memref, target.offset, config.options.count, function(err, data, address)
    vim.schedule(function()
      if err then
        return notify(err, vim.log.levels.ERROR)
      end
      if before_commit then
        before_commit()
      end
      state.memref, state.offset, state.expr = target.memref, target.offset, target.expr
      state.last_data = nil -- new region; nothing meaningful to diff against
      show(data, address)
    end)
  end)
end

--- Interpret the 8 bytes at the cursor as a little-endian pointer and jump there.
function follow()
  local idx = cursor_byte_index()
  if not idx then
    return notify('cursor is not on a byte', vim.log.levels.WARN)
  end
  local ptr = render.read_ptr_le(state.last_data, idx)
  if not ptr then
    return notify('need 8 bytes at the cursor to read a pointer', vim.log.levels.WARN)
  end
  if ptr == '0x0' then
    return notify('null pointer', vim.log.levels.WARN)
  end
  navigate({ memref = ptr, offset = 0, expr = ptr }, push_history)
end

--- Return to the location before the last follow/goto.
function back()
  local prev = state.history[#state.history]
  if not prev then
    return notify('already at the first location', vim.log.levels.WARN)
  end
  navigate(prev, function()
    table.remove(state.history)
  end)
end

--- Open (or retarget) the memory view for an expression.
function M.open(expr)
  memory.resolve(expr, function(err, memref)
    if err then
      return vim.schedule(function()
        notify(err, vim.log.levels.ERROR)
      end)
    end
    navigate({ memref = memref, offset = 0, expr = expr }, function()
      if state.memref then
        push_history() -- allow <BS> to return from a goto, not just a follow
      end
      ensure_win()
    end)
  end)
end

--- Re-read the current window of memory. `silent` suppresses errors (auto-refresh path).
function M.refresh(silent)
  if not state.memref then
    if not silent then
      notify('no memory view open — use :DapMemView <expr>', vim.log.levels.WARN)
    end
    return
  end
  if silent and not buf_valid() then
    return
  end
  memory.read(state.memref, state.offset, config.options.count, function(err, data, address)
    vim.schedule(function()
      if err then
        if not silent then
          notify(err, vim.log.levels.ERROR)
        end
        return
      end
      show(data, address)
    end)
  end)
end

--- Page forward/backward by one view worth of bytes.
function M.page(direction)
  if not state.memref then
    return
  end
  navigate { memref = state.memref, offset = state.offset + direction * config.options.count, expr = state.expr }
end

function M.close()
  if win_valid() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

--- Session ended: close the window and forget the target.
function M.reset()
  M.close()
  state.expr, state.memref, state.offset, state.last_data, state.history = nil, nil, 0, nil, {}
  if buf_valid() then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
end

return M
