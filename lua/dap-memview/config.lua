local M = {}

M.defaults = {
  bytes_per_line = 16,
  count = 256, -- bytes fetched per view/page
  auto_refresh = true, -- re-read + diff-highlight on every stop (step/breakpoint)
  window = {
    position = 'botright', -- any :split modifier
    height = 18,
  },
  keymaps = {
    refresh = 'r',
    close = 'q',
    page_next = ']',
    page_prev = '[',
    goto_expr = 'g', -- prompt for a new expression
    follow = '<CR>', -- treat the 8 bytes at the cursor as a pointer and jump to it
    back = '<BS>', -- return to the location before the last follow/goto
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
