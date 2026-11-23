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

--- Inverse of byte_col: which byte (1-based) a 0-indexed screen column falls
--- on. Columns left of the hex area clamp to 1; columns in the ASCII bar map
--- to the character's byte; anything past the end clamps to the last byte.
function M.col_to_byte(col, bytes_per_line)
  bytes_per_line = bytes_per_line or 16
  local pipe_col = M.byte_col(bytes_per_line, bytes_per_line) + 2 + 2 -- the '|' before the ASCII chars
  if col >= pipe_col then
    return math.max(1, math.min(col - pipe_col, bytes_per_line))
  end
  local j = 1
  for k = 1, bytes_per_line do
    if col >= M.byte_col(k, bytes_per_line) then
      j = k
    end
  end
  return j
end

--- The 8 bytes at 1-based index i, read as a little-endian pointer and
--- returned as a `0x...` string (lowercase, no leading zeros; null is `0x0`).
--- Returns nil when fewer than 8 bytes remain. Built digit-by-digit rather
--- than through a Lua number, so tagged and high-half pointers above 2^53
--- survive intact.
function M.read_ptr_le(bytes, i)
  if i < 1 or i + 7 > #bytes then
    return nil
  end
  local digits = {}
  for k = 7, 0, -1 do
    digits[#digits + 1] = ('%02x'):format(bytes:byte(i + k))
  end
  local hex = table.concat(digits):gsub('^0+', '')
  return '0x' .. (hex == '' and '0' or hex)
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
