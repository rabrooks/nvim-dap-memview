-- A stand-in for nvim-dap's session, so the resolver and view can be tested
-- without a debug adapter. Install it with `fake.install { ... }`; requests
-- are answered asynchronously, like a real adapter's.
local M = {}

--- @param spec { evaluate: table<string, table|false>|nil, memory: table<string, string>|nil, capabilities: table|nil }
---   evaluate: expression -> evaluate response body (missing/false = error)
---   memory:   memoryReference .. offset (e.g. '0x1000+0') -> raw bytes
---             (missing = readMemory error)
function M.install(spec)
  local session = {
    capabilities = spec.capabilities or { supportsReadMemoryRequest = true },
    current_frame = { id = 1 },
    requests = {},
  }

  function session:request(command, args, cb)
    table.insert(self.requests, { command = command, args = args })
    local err, resp
    if command == 'evaluate' then
      resp = (spec.evaluate or {})[args.expression]
      if not resp then
        err, resp = { message = 'could not evaluate ' .. args.expression }, nil
      end
    elseif command == 'readMemory' then
      local data = (spec.memory or {})[('%s%+d'):format(args.memoryReference, args.offset)]
      if data then
        resp = {
          address = ('0x%x'):format(tonumber(args.memoryReference) + args.offset),
          data = vim.base64.encode(data:sub(1, args.count)),
        }
      else
        err = { message = 'memory read failed' }
      end
    end
    vim.schedule(function()
      cb(err, resp)
    end)
  end

  package.loaded['dap'] = {
    session = function()
      return session
    end,
  }
  return session
end

function M.uninstall()
  package.loaded['dap'] = nil
end

return M
