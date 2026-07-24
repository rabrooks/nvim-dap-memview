local M = {}

function M.check()
  local health = vim.health

  health.start 'dap-memview'

  if vim.fn.has 'nvim-0.10' == 1 then
    health.ok('Neovim ' .. tostring(vim.version()) .. ' (vim.base64 available)')
  else
    health.error 'Neovim >= 0.10 required (uses vim.base64)'
  end

  local ok, dap = pcall(require, 'dap')
  if not ok then
    health.error('nvim-dap not found', { 'Install mfussenegger/nvim-dap' })
    return
  end
  health.ok 'nvim-dap found'

  local s = dap.session()
  if not s then
    health.info 'no active debug session (start one to check adapter capabilities)'
  elseif s.capabilities and s.capabilities.supportsReadMemoryRequest then
    health.ok('active adapter supports readMemory' .. (s.capabilities.supportsWriteMemoryRequest and ' and writeMemory' or ''))
  else
    health.warn 'active adapter does NOT advertise supportsReadMemoryRequest'
  end
end

return M
