local render = require 'dap-memview.render'

describe('render.format', function()
  it('formats a full 16-byte line with address, hex, and ascii', function()
    local bytes = 'Hello, world!\0\1\255'
    local lines = render.format(bytes, 0x1000, 16)
    assert.are.equal(1, #lines)
    assert.are.equal('000000001000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 00 01 ff  |Hello, world!...|', lines[1])
  end)

  it('splits into multiple lines with advancing addresses', function()
    local lines = render.format(string.rep('\0', 40), 0x2000, 16)
    assert.are.equal(3, #lines)
    assert.truthy(lines[1]:match '^000000002000')
    assert.truthy(lines[2]:match '^000000002010')
    assert.truthy(lines[3]:match '^000000002020')
  end)

  it('pads a short final line without trailing garbage', function()
    local lines = render.format('AB', 0, 16)
    assert.are.equal(1, #lines)
    assert.truthy(lines[1]:match '|AB|$')
    -- hex area keeps fixed width: ascii bar starts at the same column as a full line
    local full = render.format(string.rep('A', 16), 0, 16)[1]
    assert.are.equal(full:find '|', lines[1]:find '|')
  end)

  it('renders non-printable bytes as dots', function()
    local lines = render.format('\0\31\127\255', 0, 16)
    assert.truthy(lines[1]:match '|%.%.%.%.|')
  end)
end)

describe('render.byte_col', function()
  it('maps byte indices to the columns where format() put them', function()
    local bytes = string.rep('\170', 16) -- 0xaa
    local line = render.format(bytes, 0, 16)[1]
    for j = 1, 16 do
      local col = render.byte_col(j, 16)
      assert.are.equal('aa', line:sub(col + 1, col + 2), 'byte ' .. j)
    end
  end)
end)

describe('render.col_to_byte', function()
  it('is the inverse of byte_col for every byte', function()
    for j = 1, 16 do
      local col = render.byte_col(j, 16)
      assert.are.equal(j, render.col_to_byte(col, 16), 'first hex digit of byte ' .. j)
      assert.are.equal(j, render.col_to_byte(col + 1, 16), 'second hex digit of byte ' .. j)
    end
  end)

  it('clamps columns left of the hex area to byte 1', function()
    assert.are.equal(1, render.col_to_byte(0, 16))
    assert.are.equal(1, render.col_to_byte(render.HEX_START - 1, 16))
  end)

  it('maps ASCII-bar columns to their bytes', function()
    local pipe_col = render.byte_col(16, 16) + 2 + 2
    assert.are.equal(1, render.col_to_byte(pipe_col + 1, 16))
    assert.are.equal(5, render.col_to_byte(pipe_col + 5, 16))
    assert.are.equal(16, render.col_to_byte(pipe_col + 99, 16)) -- clamp past the end
  end)
end)

describe('render.read_ptr_le', function()
  it('decodes little-endian into a 0x string', function()
    assert.are.equal('0x807060504030201', render.read_ptr_le('\1\2\3\4\5\6\7\8', 1))
  end)

  it('reads at an offset and strips leading zeros', function()
    assert.are.equal('0x1', render.read_ptr_le('\255\255\1\0\0\0\0\0\0\0', 3))
  end)

  it('renders a null pointer as 0x0', function()
    assert.are.equal('0x0', render.read_ptr_le(string.rep('\0', 8), 1))
  end)

  it('keeps every bit of pointers above 2^53', function()
    assert.are.equal('0xffffff8000123457', render.read_ptr_le('\87\52\18\0\128\255\255\255', 1))
  end)

  it('returns nil when fewer than 8 bytes remain', function()
    assert.is_nil(render.read_ptr_le('\1\2\3\4\5\6\7', 1))
    assert.is_nil(render.read_ptr_le('\1\2\3\4\5\6\7\8', 2))
    assert.is_nil(render.read_ptr_le('\1\2\3\4\5\6\7\8', 0))
  end)
end)

describe('render.diff', function()
  it('returns empty when there is no previous snapshot', function()
    assert.are.same({}, render.diff(nil, 'abc'))
  end)

  it('finds changed byte indices', function()
    assert.are.same({ 2, 4 }, render.diff('abcd', 'aXcY'))
  end)

  it('ignores length differences beyond the shorter snapshot', function()
    assert.are.same({}, render.diff('ab', 'abcd'))
  end)
end)
