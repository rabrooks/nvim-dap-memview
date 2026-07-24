-- Integration check: drive the plugin's resolve → read path against a real
-- codelldb session on examples/demo (build it first: clang -g -O0 -o demo demo.c).
-- Run from the repo root:
--   nvim --headless -u NONE -c "luafile tests/repro_evaluate.lua"
vim.opt.rtp:prepend(vim.fn.stdpath 'data' .. '/lazy/nvim-dap')
vim.opt.rtp:prepend '.'

local dap = require 'dap'
local memory = require 'dap-memview.memory'

dap.adapters.codelldb = {
  type = 'server',
  port = '${port}',
  executable = {
    command = vim.fn.stdpath 'data' .. '/mason/bin/codelldb',
    args = { '--port', '${port}' },
  },
}

vim.cmd.edit 'examples/demo.c'
vim.api.nvim_win_set_cursor(0, { 18, 0 })
dap.set_breakpoint()

local function log(msg)
  io.stdout:write(msg .. '\n')
  io.stdout:flush()
end

local failures = 0

local function check(expr, expect_pattern, next_fn)
  memory.resolve(expr, function(err, memref)
    if err then
      failures = failures + 1
      log(('FAIL resolve(%s): %s'):format(expr, err))
      return next_fn()
    end
    memory.read(memref, 0, 32, function(rerr, data)
      if rerr then
        failures = failures + 1
        log(('FAIL read(%s @ %s): %s'):format(expr, memref, rerr))
      elseif expect_pattern and not data:match(expect_pattern) then
        failures = failures + 1
        log(('FAIL %s @ %s: unexpected data %q'):format(expr, memref, data))
      else
        log(('OK   %s -> %s : %q'):format(expr, memref, (data:gsub('%z', '.'))))
      end
      next_fn()
    end)
  end)
end

local done = false
dap.listeners.after.event_stopped['repro'] = function()
  if done then
    return
  end
  done = true
  vim.defer_fn(function()
    check('buf', '^watch this buffer mutate', function()
      check('&buf', '^watch this buffer mutate', function()
        check('i', nil, function()
          log(failures == 0 and 'ALL CHECKS PASSED' or ('%d CHECK(S) FAILED'):format(failures))
          dap.terminate()
          vim.defer_fn(function()
            vim.cmd 'qa!'
          end, 300)
        end)
      end)
    end)
  end, 800)
end

dap.run {
  name = 'repro',
  type = 'codelldb',
  request = 'launch',
  program = vim.fn.getcwd() .. '/examples/demo',
  cwd = vim.fn.getcwd(),
  stopOnEntry = false,
}

vim.defer_fn(function()
  log 'TIMEOUT'
  vim.cmd 'qa!'
end, 15000)
