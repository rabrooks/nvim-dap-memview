# nvim-dap-memview

A memory viewer (live hex dump) for [nvim-dap](https://github.com/mfussenegger/nvim-dap).

Inspect raw memory of the process you're debugging, refreshed on every stop, with
bytes that changed since the last stop highlighted — the memory panel that
LLDB/GDB users miss in the nvim-dap ecosystem
([mfussenegger/nvim-dap#701](https://github.com/mfussenegger/nvim-dap/discussions/701)).

Adapter-agnostic by construction: it speaks only DAP (`evaluate` +
`readMemory`), so it works with any adapter that advertises
`supportsReadMemoryRequest` — codelldb, lldb-dap, cppdbg, `gdb -i dap` — and
therefore with C, C++, Rust, Zig, or anything else those adapters debug.

## Requirements

- Neovim >= 0.10 (uses `vim.base64`)
- [nvim-dap](https://github.com/mfussenegger/nvim-dap)
- A debug adapter with `readMemory` support (codelldb recommended)

## Install (lazy.nvim)

```lua
{
  'rabrooks/nvim-dap-memview',
  dependencies = { 'mfussenegger/nvim-dap' },
  opts = {},
}
```

## Usage

With a debug session stopped at a breakpoint:

| Command | Action |
|---|---|
| `:DapMemView <expr>` | View memory at an expression (`&buf`, `argv`, `0x7ffe...`) |
| `:DapMemView` | View memory of the expression under the cursor |
| `:DapMemViewClose` | Close the view |

Inside the view: `r` refresh, `]`/`[` page forward/back, `g` jump to a new
expression, `q` close. The view auto-refreshes on every stop; changed bytes are
highlighted (`DapMemviewChanged`, links to `DiffText`).

For a non-pointer variable, view its storage with `&var` — pointers and arrays
resolve directly.

## Configuration (defaults)

```lua
require('dap-memview').setup {
  bytes_per_line = 16,
  count = 256,          -- bytes per page
  auto_refresh = true,  -- re-read + diff on every stop
  window = { position = 'botright', height = 18 },
  keymaps = { refresh = 'r', close = 'q', page_next = ']', page_prev = '[', goto_expr = 'g' },
}
```

## Try it

```sh
cd examples && clang -g -O0 -o demo demo.c
```

Open `demo.c` in nvim, set a breakpoint in the loop, launch a codelldb session,
then `:DapMemView buf` and step — watch the highlighted bytes march across the
buffer.

## Status / roadmap

Proof of concept — read-only. Planned:

- [ ] Byte editing via `writeMemory`
- [ ] Typed views (u8/u32/f64, endianness toggle)
- [ ] Follow-pointer navigation
- [ ] Multiple simultaneous views / multi-session support
- [ ] Optional [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) section integration
- [ ] Virtual scrolling for large regions

Known limitation: addresses above 2^53 lose precision in Lua doubles (not an
issue for typical userspace debugging).

## Tests

```sh
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

## License

MIT
