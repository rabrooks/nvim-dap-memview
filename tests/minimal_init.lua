-- Minimal init for running plenary tests headless:
--   nvim --headless -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
-- Set PLENARY_DIR to use a plenary checkout outside lazy.nvim's data dir (CI does).
local plenary = vim.env.PLENARY_DIR or (vim.fn.stdpath 'data' .. '/lazy/plenary.nvim')
vim.opt.rtp:prepend(plenary)
vim.opt.rtp:prepend '.'
vim.opt.swapfile = false
-- `require 'tests.fake_dap'` resolves from the repo root
package.path = './?.lua;' .. package.path
