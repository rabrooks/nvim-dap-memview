-- Minimal init for running plenary tests headless:
--   nvim --headless -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
local plenary = vim.fn.stdpath 'data' .. '/lazy/plenary.nvim'
vim.opt.rtp:prepend(plenary)
vim.opt.rtp:prepend '.'
