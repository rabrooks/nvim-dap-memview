# nvim-dap-memview

[![CI](https://github.com/rabrooks/nvim-dap-memview/actions/workflows/ci.yml/badge.svg)](https://github.com/rabrooks/nvim-dap-memview/actions/workflows/ci.yml)

A memory viewer for [nvim-dap](https://github.com/mfussenegger/nvim-dap) — the
missing "memory panel" from full debugger UIs, as a live hex dump inside Neovim.

<!-- TODO: record a short GIF of stepping through examples/demo.c with the
     changed-byte highlights, and embed it here. -->

```
buf  @ 0x16FDFE3F8  offset +0  (256 bytes)
[r] refresh  [[] page back  []] page fwd  [g] goto expr  [q] quit
00016fdfe3f8  77 61 74 63 68 20 74 68  69 73 20 62 75 66 66 65  |watch this buffe|
00016fdfe408  72 20 6d 75 74 61 74 65  00 00 00 00 00 00 00 00  |r mutate........|
00016fdfe418  61 62 63 64 65 66 00 00  00 00 00 00 00 00 00 00  |abcdef..........|
```

Stopped at a breakpoint, run `:DapMemView buf` — then step, and watch the bytes
your program writes light up.

## Features

- **Live hex dump** of any address the debuggee can see: local variables,
  arrays, pointers, arbitrary expressions, or raw `0x...` addresses
- **Auto-refresh on every stop** (step, breakpoint) with **changed-byte
  highlighting** — see exactly what the last step mutated
- **Follow-pointer navigation**: `<CR>` on 8 bytes jumps through them as a
  pointer — chase linked lists, vtables, and heap structures; `<BS>` walks
  back up the trail
- **Paging** forward/backward through memory from the anchor address
- **Adapter-agnostic**: speaks only DAP (`evaluate` + `readMemory`), with a
  resolver that handles adapters that don't populate `memoryReference`
  (looking at you, codelldb)
- Small, dependency-free (nvim-dap only), unit + integration tested

## Requirements

- Neovim **>= 0.10**
- [nvim-dap](https://github.com/mfussenegger/nvim-dap)
- A debug adapter that supports the DAP `readMemory` request:

| Adapter | Languages | readMemory |
|---|---|---|
| [codelldb](https://github.com/vadimcn/codelldb) | C, C++, Rust, Zig | ✅ |
| [lldb-dap](https://lldb.llvm.org/resources/lldbdap.html) (LLVM ≥ 19) | C, C++, Rust | ✅ |
| [cpptools / cppdbg](https://github.com/microsoft/vscode-cpptools) | C, C++ | ✅ |
| `gdb -i dap` (GDB ≥ 14) | C, C++, Rust, Go | ✅ |

Run `:checkhealth dap-memview` with a session active to confirm your adapter
advertises `supportsReadMemoryRequest`.

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'rabrooks/nvim-dap-memview',
  dependencies = { 'mfussenegger/nvim-dap' },
  cmd = { 'DapMemView', 'DapMemViewClose' },
  keys = {
    {
      '<leader>dm',
      function()
        require('dap-memview').open(vim.fn.expand '<cexpr>')
      end,
      desc = 'Debug: Memory view (expression under cursor)',
    },
    {
      '<leader>dM',
      function()
        vim.ui.input({ prompt = 'Memory expression: ' }, function(input)
          if input and input ~= '' then
            require('dap-memview').open(input)
          end
        end)
      end,
      desc = 'Debug: Memory view (prompt)',
    },
  },
  opts = {},
}
```

### [mini.deps](https://github.com/echasnovski/mini.deps)

```lua
MiniDeps.add {
  source = 'rabrooks/nvim-dap-memview',
  depends = { 'mfussenegger/nvim-dap' },
}
require('dap-memview').setup {}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'rabrooks/nvim-dap-memview',
  requires = { 'mfussenegger/nvim-dap' },
  config = function()
    require('dap-memview').setup {}
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'mfussenegger/nvim-dap'
Plug 'rabrooks/nvim-dap-memview'
```

```lua
-- after plug#end()
require('dap-memview').setup {}
```

### Native `vim.pack` (Neovim 0.12+)

```lua
vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/rabrooks/nvim-dap-memview',
}
require('dap-memview').setup {}
```

> [!NOTE]
> `setup()` is optional — it runs automatically with defaults on first use.
> Call it only to change configuration.

## Quickstart

1. Start a debug session and stop at a breakpoint (see the
   [nvim-dap docs](https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation)
   for adapter setup).
2. `:DapMemView buf` — or put your cursor on a variable and run `:DapMemView`
   with no argument.
3. Step (`require('dap').step_over()`). The view refreshes and highlights every
   byte that changed.

Want a sandbox? This repo ships one:

```sh
git clone https://github.com/rabrooks/nvim-dap-memview
cd nvim-dap-memview/examples
clang -g -O0 -o demo demo.c   # or gcc
nvim demo.c
```

Set a breakpoint inside the loop, launch a codelldb session on `./demo`, then
`:DapMemView buf` and step — the letters the loop writes march across the
ASCII column with each byte highlighted as it changes. Then try
`:DapMemView rec`: a struct with a pointer in it. Put the cursor on the
pointer's 8 bytes (the second half of the first row) and press `<CR>` to
follow it, `<BS>` to come back.

## Commands

| Command | Action |
|---|---|
| `:DapMemView {expr}` | Open the memory view for an expression: a variable (`buf`, a struct, ...) shows the variable's own bytes, a pointer (`argv`) shows what it points at, and `&ptr` shows the pointer itself. A raw address (`0x7ffee4c0`) works too |
| `:DapMemView` | Same, using the expression under the cursor (`<cexpr>`) |
| `:DapMemViewClose` | Close the memory view window |

## Keybindings

Inside the memory view (buffer-local, configurable):

| Key | Action |
|---|---|
| `r` | Refresh now |
| `]` | Page forward |
| `[` | Page backward |
| `<CR>` | Follow the pointer under the cursor (8 bytes, little-endian) |
| `<BS>` | Back to the location before the last follow/goto |
| `g` | Prompt for a new expression |
| `q` | Close |

Suggested global mappings (already included in the lazy.nvim spec above) fit
alongside typical nvim-dap `<leader>d` mappings:

```lua
vim.keymap.set('n', '<leader>dm', function()
  require('dap-memview').open(vim.fn.expand '<cexpr>')
end, { desc = 'Debug: Memory view (expression under cursor)' })

vim.keymap.set('n', '<leader>dM', function()
  vim.ui.input({ prompt = 'Memory expression: ' }, function(input)
    if input and input ~= '' then
      require('dap-memview').open(input)
    end
  end)
end, { desc = 'Debug: Memory view (prompt)' })
```

## Configuration

Defaults shown — pass any subset to `setup()` (or `opts` with lazy.nvim):

```lua
require('dap-memview').setup {
  bytes_per_line = 16,   -- bytes rendered per row
  count = 256,           -- bytes fetched per view/page
  auto_refresh = true,   -- re-read + diff-highlight on every stop
  window = {
    position = 'botright', -- any :split modifier ('topleft', 'vertical botright', ...)
    height = 18,
  },
  keymaps = {            -- buffer-local, set to false to disable one
    refresh = 'r',
    close = 'q',
    page_next = ']',
    page_prev = '[',
    goto_expr = 'g',
    follow = '<CR>',
    back = '<BS>',
  },
}
```

### Highlight groups

| Group | Default link | Purpose |
|---|---|---|
| `DapMemviewChanged` | `DiffText` | Bytes that changed since the previous stop |
| `DapMemviewAddr` | `LineNr` | Address gutter |
| `DapMemviewHeader` | `Title` | Header line |

## How it works

On open, the expression is resolved to an address with the DAP `evaluate`
request; the view then issues `readMemory` for the visible window and decodes
the result. An `event_stopped` listener re-reads the same window on every stop
and diffs the snapshot against the previous one to produce the changed-byte
highlights. No adapter-specific protocol is used — but the resolver tries a
chain of expression spellings because adapters differ in what `evaluate`
returns:

1. the expression as given — adapters that populate `memoryReference`, or
   render a pointer as a bare `0x...` address, are done here
2. otherwise, for a pointer (the response's `type` ends in `*`): its value,
   `(unsigned long long)(expr)`, so the view shows what it points at
3. for anything else: `&(expr)`, then `(unsigned long long)&(expr)` — the
   variable's own address, built from an integer cast
4. each cast again behind codelldb's `/nat` native-evaluator prefix

An address that merely appears *inside* a value summary — codelldb renders a
struct as `{id:42, id_ptr:0x16fdfe1e4}` — is never used: that is a member's
value, not where the struct lives.

## Troubleshooting

- **"no memory reference for ..."** — the expression may not exist in the
  current frame (check spelling and scope), or the session isn't stopped.
  The error lists every spelling that was tried.
- **codelldb specifics**: codelldb does not return `memoryReference` from
  `evaluate`, and its default *simple* expression evaluator cannot parse C
  casts or `&`. The resolver's `/nat` fallback (step 4 above) handles this
  automatically. If you use expressions in the view, plain variable names and
  C expressions both work; codelldb-native syntax is fine too.
- **"adapter does not support readMemory"** — your adapter doesn't implement
  the request (see the table under Requirements). `:checkhealth dap-memview`
  shows what the active session advertises.
- **A failed follow or page leaves the view where it was** — following a
  garbage pointer or paging into unmapped memory reports the adapter's error
  and keeps the current bytes on screen.
- **Huge addresses** — pointers are followed exactly, but the address gutter
  and expression resolution go through Lua doubles and lose precision above
  2^53. Not an issue for typical userspace debugging.

## Roadmap

- [x] Follow-pointer navigation
- [ ] Byte editing via `writeMemory`
- [ ] Resolve plain variable names through DAP `scopes`/`variables` (drops the
      codelldb `/nat` special case)
- [ ] Typed views (u8/u32/f64, endianness toggle)
- [ ] Multiple simultaneous views / multi-session support
- [ ] Optional [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) section integration
- [ ] Virtual scrolling for large regions

## Development

Unit tests ([plenary.nvim](https://github.com/nvim-lua/plenary.nvim)) — these
run in CI on Neovim 0.10, stable, and nightly, and need no debug adapter (the
resolver and view are driven by a fake DAP session, `tests/fake_dap.lua`):

```sh
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

Integration test (drives a real codelldb session against `examples/demo`):

```sh
cd examples && clang -g -O0 -o demo demo.c && cd ..
nvim --headless -n -u NONE -c "luafile tests/repro_evaluate.lua"
```

Issues and PRs welcome — especially reports of how other adapters
(lldb-dap, cppdbg, gdb, delve...) behave with the resolver chain.

## Related projects

- [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) — multi-panel debug UI (variables, watches, stacks, REPL)
- [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) — single-window debug UI
- [nvim-dap-disasm](https://codeberg.org/Jorenar/nvim-dap-disasm) — disassembly view, the memory view's sibling
- [nvim-dap discussion #701](https://github.com/mfussenegger/nvim-dap/discussions/701) — the memory-view UX thread that motivated this plugin

## License

[MIT](LICENSE)
