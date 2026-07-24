-- nvim-dap-memview: a DAP memory viewer (hex dump) for nvim-dap.
local M = {}

local did_setup = false

--- Optional; called automatically on first use with defaults.
function M.setup(opts)
  require('dap-memview.config').setup(opts)

  local ok, dap = pcall(require, 'dap')
  if not ok then
    vim.notify('[dap-memview] nvim-dap is required (mfussenegger/nvim-dap)', vim.log.levels.ERROR)
    return
  end

  -- Refresh (and diff-highlight) on every stop; tear down when the session ends.
  dap.listeners.after.event_stopped['dap-memview'] = function()
    if require('dap-memview.config').options.auto_refresh then
      require('dap-memview.view').refresh(true)
    end
  end
  dap.listeners.before.event_terminated['dap-memview'] = function()
    require('dap-memview.view').reset()
  end
  dap.listeners.before.event_exited['dap-memview'] = function()
    require('dap-memview.view').reset()
  end

  did_setup = true
end

local function ensure_setup()
  if not did_setup then
    M.setup()
  end
end

--- Open the memory viewer for an expression (e.g. "&buf", "argv", "0x7ffe...").
function M.open(expr)
  ensure_setup()
  require('dap-memview.view').open(expr)
end

function M.close()
  require('dap-memview.view').close()
end

return M
