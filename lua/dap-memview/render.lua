-- Pure hex-dump rendering. No vim API calls in format/diff so these are unit-testable.
local M = {}

-- Layout (0-indexed columns, for extmark placement):
--   0            12  14                                            62  64
--   <addr 12 hex>    <16 bytes as "xx " groups, extra gap after 8>     |ascii|
M.ADDR_WIDTH = 12
M.HEX_START = M.ADDR_WIDTH + 2

--- Column (0-indexed) of the j-th byte (1-based) on its line.
function M.byte_col(j, bytes_per_line)
  bytes_per_line = bytes_per_line or 16
  local half = math.floor(bytes_per_line / 2)
  return M.HEX_START + (j - 1) * 3 + (j > half and 1 or 0)
end

--- Format a byte string as hex-dump lines.
--- @param bytes string raw bytes
--- @param base_addr number address of bytes[1]
--- @param bytes_per_line number|nil defaults to 16
--- @return string[] lines
function M.format(bytes, base_addr, bytes_per_line)
  bytes_per_line = bytes_per_line or 16
  local half = math.floor(bytes_per_line / 2)
  local lines = {}
  for i = 1, #bytes, bytes_per_line do
    local chunk = bytes:sub(i, i + bytes_per_line - 1)
    local hex, ascii = {}, {}
    for j = 1, bytes_per_line do
      if j == half + 1 then
        hex[#hex + 1] = ''
      end
      local b = chunk:byte(j)
      if b then
        hex[#hex + 1] = string.format('%02x', b)
        ascii[#ascii + 1] = (b >= 0x20 and b <= 0x7e) and string.char(b) or '.'
      else
        hex[#hex + 1] = '  '
      end
    end
    lines[#lines + 1] = string.format('%012x  %s  |%s|', base_addr + i - 1, table.concat(hex, ' '), table.concat(ascii))
  end
  return lines
end

--- Byte indices (1-based) that differ between two snapshots.
--- Compares up to #new; a missing/short old snapshot produces no marks.
function M.diff(old, new)
  local changed = {}
  if not old then
    return changed
  end
  for i = 1, math.min(#old, #new) do
    if old:byte(i) ~= new:byte(i) then
      changed[#changed + 1] = i
    end
  end
  return changed
end

return M
