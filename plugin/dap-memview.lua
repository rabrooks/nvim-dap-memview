if vim.g.loaded_dap_memview then
  return
end
vim.g.loaded_dap_memview = 1

vim.api.nvim_create_user_command('DapMemView', function(o)
  local expr = o.args ~= '' and o.args or vim.fn.expand '<cexpr>'
  if expr == '' then
    vim.notify('[dap-memview] no expression given and nothing under cursor', vim.log.levels.WARN)
    return
  end
  require('dap-memview').open(expr)
end, { nargs = '?', desc = 'View memory of an expression (default: <cexpr> under cursor)' })

vim.api.nvim_create_user_command('DapMemViewClose', function()
  require('dap-memview').close()
end, { desc = 'Close the memory view window' })
