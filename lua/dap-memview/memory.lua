-- DAP request orchestration: resolve an expression to a memoryReference, read memory.
-- Talks only to nvim-dap's session API — no adapter-specific code, so anything that
-- implements DAP readMemory (codelldb, lldb-dap, cppdbg, gdb -i dap) works.
local M = {}

local function active_session()
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return nil, 'nvim-dap is not installed'
  end
  local s = dap.session()
  if not s then
    return nil, 'no active debug session'
  end
  return s
end

local function err_msg(e)
  if type(e) == 'table' then
    return e.message or (e.body and e.body.error and e.body.error.format) or vim.inspect(e)
  end
  return tostring(e)
end

--- Pull a usable memory reference out of an evaluate response.
--- mode 'ref':  memoryReference field, or a result that *starts with* a 0x...
---              address (a pointer value, optionally followed by a summary
---              such as `0x16fdfe3f8 "text"`).
--- mode 'int':  additionally accept a plain decimal result (from our
---              integer-cast candidates) and format it as a hex address.
---
--- The hex match is anchored on purpose: adapters render aggregates as
--- summaries like `{id: 1, idPtr: 0x7ff6a0d27040}`, and a 0x... buried in one
--- is a member's value, not the address of the expression (issue #1).
local function extract_ref(resp, mode)
  if not resp then
    return nil
  end
  if resp.memoryReference then
    return resp.memoryReference
  end
  local result = type(resp.result) == 'string' and resp.result or ''
  local hex = result:match '^%s*(0x%x+)'
  if hex then
    return hex
  end
  if mode == 'int' then
    local dec = result:match '(%d+)%s*$'
    if dec then
      return ('0x%x'):format(tonumber(dec))
    end
  end
  return nil
end

local function try_resolve(cand, cb)
  local s, serr = active_session()
  if not s then
    return cb(serr)
  end
  local frame = s.current_frame
  s:request('evaluate', {
    expression = cand.expr,
    context = 'watch',
    frameId = frame and frame.id or nil,
  }, function(e, resp)
    if e then
      return cb(('evaluate(%s): %s'):format(cand.expr, err_msg(e)))
    end
    local ref = extract_ref(resp, cand.mode)
    if not ref then
      return cb(('no memory reference for "%s"'):format(cand.expr), nil, resp)
    end
    cb(nil, ref)
  end)
end

--- Does an evaluate response describe a pointer? (`int *`, `char *const`, ...)
local function is_pointer(resp)
  return type(resp) == 'table' and type(resp.type) == 'string' and resp.type:match '%*[%s%a]*$' ~= nil
end

--- Fallback spellings, tried in order when evaluating the expression as given
--- yields no address (verified against codelldb 1.11, which sets NO
--- memoryReference on evaluate and renders values as summaries):
---   pointers (the response's `type` ends in `*`): the view should show what
---   the pointer points at, so cast its *value* to an integer and build the
---   reference ourselves (readMemory accepts 0x strings).
---   everything else: the view should show the variable itself, so try
---   address-of (adapters that set memoryReference on `&x`), then cast the
---   address to an integer.
--- Each cast is tried twice, the second time behind codelldb's `/nat `
--- native-evaluator prefix — its default "simple" evaluator cannot parse C
--- casts or `&`. Harmless no-op failure on other adapters.
local function fallbacks(expr, pointer)
  local list = {}
  local target
  if pointer then
    target = ('(%s)'):format(expr)
  elseif expr:match '^&' then
    target = ('(%s)'):format(expr)
  else
    target = ('&(%s)'):format(expr)
    list[#list + 1] = { expr = target, mode = 'ref' }
  end
  list[#list + 1] = { expr = ('(unsigned long long)%s'):format(target), mode = 'int' }
  list[#list + 1] = { expr = ('/nat (unsigned long long)%s'):format(target), mode = 'int' }
  return list
end

--- Resolve an expression to a DAP memoryReference: a pointer resolves to what
--- it points at, anything else to its own address.
--- @param expr string e.g. "buf", "&buf", "argv", "0x7ffee4c0"
--- @param cb fun(err: string|nil, memref: string|nil)
function M.resolve(expr, cb)
  -- A literal address needs no evaluation: readMemory takes it directly.
  if expr:match '^0x%x+$' then
    return cb(nil, expr)
  end
  -- As given first: adapters that set memoryReference (lldb-dap, cppdbg,
  -- gdb -i dap) or render pointers as a bare address succeed here.
  try_resolve({ expr = expr, mode = 'ref' }, function(err, ref, resp)
    if ref then
      return cb(nil, ref)
    end
    local list = fallbacks(expr, is_pointer(resp))
    local function attempt(i)
      if i > #list then
        local tried = { expr }
        for _, c in ipairs(list) do
          tried[#tried + 1] = c.expr
        end
        return cb(('%s (tried: %s)'):format(err or 'could not resolve', table.concat(tried, ', ')))
      end
      try_resolve(list[i], function(_, r)
        if r then
          return cb(nil, r)
        end
        attempt(i + 1)
      end)
    end
    attempt(1)
  end)
end

--- Read memory at a memoryReference.
--- @param memref string
--- @param offset number byte offset relative to memref (may be negative)
--- @param count number bytes to read
--- @param cb fun(err: string|nil, data: string|nil, address: string|nil)
function M.read(memref, offset, count, cb)
  local s, serr = active_session()
  if not s then
    return cb(serr)
  end
  if not (s.capabilities and s.capabilities.supportsReadMemoryRequest) then
    return cb 'this debug adapter does not support readMemory'
  end
  s:request('readMemory', {
    memoryReference = memref,
    offset = offset,
    count = count,
  }, function(e, resp)
    if e then
      return cb(('readMemory: %s'):format(err_msg(e)))
    end
    if not (resp and resp.data) or resp.data == '' then
      return cb(('memory unreadable at %s%+d'):format(memref, offset))
    end
    cb(nil, vim.base64.decode(resp.data), resp.address)
  end)
end

-- Exposed for unit tests only.
M._extract_ref = extract_ref
M._fallbacks = fallbacks
M._is_pointer = is_pointer

return M
