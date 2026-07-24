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
--- mode 'ref':  memoryReference field, or a 0x... substring in the result.
--- mode 'int':  additionally accept a plain decimal result (from our
---              integer-cast candidates) and format it as a hex address.
local function extract_ref(resp, mode)
  if not resp then
    return nil
  end
  if resp.memoryReference then
    return resp.memoryReference
  end
  local result = type(resp.result) == 'string' and resp.result or ''
  local hex = result:match '0x%x+'
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
      return cb(('no memory reference for "%s"'):format(cand.expr))
    end
    cb(nil, ref)
  end)
end

--- Candidate spellings of an expression, tried in order until one yields an
--- address. Motivation (verified against codelldb 1.11 / lldb-dap):
---   1. as given — adapters that set memoryReference on evaluate (lldb-dap,
---      cppdbg, gdb -i dap) succeed here for pointers.
---   2. address-of — same adapters, for arrays/plain variables.
---   3. integer cast — codelldb sets NO memoryReference on evaluate at all
---      and renders pointers as value summaries, so we cast the address to an
---      integer and build the reference ourselves (readMemory accepts 0x
---      strings).
---   4. same cast via codelldb's `/nat ` native-evaluator prefix — codelldb's
---      default "simple" evaluator cannot parse C casts or `&`. Harmless
---      no-op failure on other adapters.
local function candidates(expr)
  local addr_of = expr:match '^&' and ('(%s)'):format(expr) or ('&(%s)'):format(expr)
  local list = { { expr = expr, mode = 'ref' } }
  if not expr:match '^&' then
    list[#list + 1] = { expr = addr_of, mode = 'ref' }
  end
  list[#list + 1] = { expr = ('(unsigned long long)%s'):format(addr_of), mode = 'int' }
  list[#list + 1] = { expr = ('/nat (unsigned long long)%s'):format(addr_of), mode = 'int' }
  return list
end

--- Resolve an expression to a DAP memoryReference.
--- @param expr string e.g. "buf", "&buf", "argv", "0x7ffee4c0"
--- @param cb fun(err: string|nil, memref: string|nil)
function M.resolve(expr, cb)
  -- A literal address needs no evaluation: readMemory takes it directly.
  if expr:match '^0x%x+$' then
    return cb(nil, expr)
  end
  local list = candidates(expr)
  local first_err
  local function attempt(i)
    if i > #list then
      local tried = {}
      for _, c in ipairs(list) do
        tried[#tried + 1] = c.expr
      end
      return cb(('%s (tried: %s)'):format(first_err or 'could not resolve', table.concat(tried, ', ')))
    end
    try_resolve(list[i], function(err, ref)
      if ref then
        return cb(nil, ref)
      end
      first_err = first_err or err
      attempt(i + 1)
    end)
  end
  attempt(1)
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
    if not (resp and resp.data) then
      return cb 'memory unreadable at this address'
    end
    cb(nil, vim.base64.decode(resp.data), resp.address)
  end)
end

return M
