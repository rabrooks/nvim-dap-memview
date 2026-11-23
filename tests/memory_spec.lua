local fake = require 'tests.fake_dap'
local memory = require 'dap-memview.memory'

--- Run an async (err, ...) callback API to completion and return its results.
local function await(fn)
  local out
  fn(function(...)
    out = { n = select('#', ...), ... }
  end)
  assert(
    vim.wait(1000, function()
      return out ~= nil
    end),
    'callback never fired'
  )
  return unpack(out, 1, out.n)
end

local function resolve(expr)
  return await(function(cb)
    memory.resolve(expr, cb)
  end)
end

describe('memory._extract_ref', function()
  local extract = memory._extract_ref

  it('prefers the memoryReference field', function()
    assert.are.equal('0x1000', extract({ memoryReference = '0x1000', result = '{p: 0x2000}' }, 'ref'))
  end)

  it('accepts a result that is a bare address', function()
    assert.are.equal('0x16fdfe3f8', extract({ result = '0x16fdfe3f8' }, 'ref'))
    assert.are.equal('0x16fdfe3f8', extract({ result = '  0x16fdfe3f8' }, 'ref'))
  end)

  it('accepts an address followed by a value summary', function()
    assert.are.equal('0x16fdfe3f8', extract({ result = '0x16fdfe3f8 "watch this"' }, 'ref'))
  end)

  it('ignores addresses buried in an aggregate summary (issue #1)', function()
    assert.is_nil(extract({ result = '{id: 1759509392, idPtr: 0x7FF6A0D27040}' }, 'ref'))
    assert.is_nil(extract({ result = '{id: 1759509392, idPtr: 0x7FF6A0D27040}' }, 'int'))
  end)

  it('accepts a decimal result only in int mode', function()
    assert.is_nil(extract({ result = '6171911160' }, 'ref'))
    assert.are.equal('0x16fdfe3f8', extract({ result = '6171911160' }, 'int'))
  end)

  it('tolerates a missing response or non-string result', function()
    assert.is_nil(extract(nil, 'ref'))
    assert.is_nil(extract({ result = vim.NIL }, 'int'))
  end)
end)

describe('memory._fallbacks', function()
  local function exprs(expr, pointer)
    return vim.tbl_map(function(c)
      return c.expr
    end, memory._fallbacks(expr, pointer))
  end

  it('takes the address of a non-pointer, then casts it to an integer', function()
    assert.are.same({ '&(buf)', '(unsigned long long)&(buf)', '/nat (unsigned long long)&(buf)' }, exprs('buf', false))
  end)

  it('does not take the address of an address-of expression', function()
    assert.are.same({ '(unsigned long long)(&buf)', '/nat (unsigned long long)(&buf)' }, exprs('&buf', false))
  end)

  it('casts the value of a pointer rather than its address', function()
    assert.are.same({ '(unsigned long long)(msg)', '/nat (unsigned long long)(msg)' }, exprs('msg', true))
  end)
end)

describe('memory._is_pointer', function()
  it('recognises pointer types', function()
    assert.is_true(memory._is_pointer { type = 'int *' })
    assert.is_true(memory._is_pointer { type = 'char **' })
    assert.is_true(memory._is_pointer { type = 'const char *const' })
    assert.is_true(memory._is_pointer { type = 'int*' })
  end)

  it('rejects everything else', function()
    assert.is_false(memory._is_pointer { type = 'char[64]' })
    assert.is_false(memory._is_pointer { type = 'record' })
    assert.is_false(memory._is_pointer { type = 'void (*)(int)' }) -- no data to view behind a function pointer
    assert.is_false(memory._is_pointer { result = '7' })
    assert.is_false(memory._is_pointer(nil))
  end)
end)

describe('memory.resolve', function()
  after_each(fake.uninstall)

  it('passes a literal address straight through without evaluating', function()
    local session = fake.install {}
    local err, ref = resolve '0x7ffee4c0'
    assert.is_nil(err)
    assert.are.equal('0x7ffee4c0', ref)
    assert.are.equal(0, #session.requests)
  end)

  it('uses memoryReference from the first candidate when the adapter sets it', function()
    local session = fake.install { evaluate = { buf = { result = '"watch"', memoryReference = '0x1000' } } }
    local err, ref = resolve 'buf'
    assert.is_nil(err)
    assert.are.equal('0x1000', ref)
    assert.are.equal(1, #session.requests)
  end)

  -- The evaluate responses below are what codelldb 1.11 really returns for
  -- examples/demo.c: no memoryReference, values rendered as summaries, and
  -- only the /nat evaluator able to parse `&` or a cast.
  it('resolves a struct with pointer fields to its own address, codelldb-style (issue #1)', function()
    fake.install {
      evaluate = {
        ['rec'] = { result = '{id:42, id_ptr:0x000000016fdfe1e4}', type = 'record' },
        ['/nat (unsigned long long)&(rec)'] = { result = '6171910608', type = 'unsigned long long' },
      },
    }
    local err, ref = resolve 'rec'
    assert.is_nil(err)
    assert.are.equal('0x16fdfe1d0', ref)
  end)

  it('resolves a pointer to what it points at, codelldb-style', function()
    fake.install {
      evaluate = {
        ['rec.id_ptr'] = { result = '7', type = 'int *' },
        -- must not be used: this is where the pointer lives, not where it points
        ['&(rec.id_ptr)'] = { result = '{0x000000016fdfe1e4}', type = 'int **' },
        ['/nat (unsigned long long)&(rec.id_ptr)'] = { result = '6171910616', type = 'unsigned long long' },
        ['/nat (unsigned long long)(rec.id_ptr)'] = { result = '6171910628', type = 'unsigned long long' },
      },
    }
    local err, ref = resolve 'rec.id_ptr'
    assert.is_nil(err)
    assert.are.equal('0x16fdfe1e4', ref)
  end)

  it('resolves a pointer rendered as a bare address without falling back', function()
    local session = fake.install { evaluate = { ['rec.id_ptr'] = { result = '0x7ff6a0d27040', type = 'int *' } } }
    local err, ref = resolve 'rec.id_ptr'
    assert.is_nil(err)
    assert.are.equal('0x7ff6a0d27040', ref)
    assert.are.equal(1, #session.requests)
  end)

  it('reports the first error and every spelling it tried', function()
    fake.install {}
    local err, ref = resolve 'nope'
    assert.is_nil(ref)
    assert.is_truthy(err:find('could not evaluate nope', 1, true))
    assert.is_truthy(err:find('tried: nope, &(nope), (unsigned long long)&(nope), /nat (unsigned long long)&(nope)', 1, true))
  end)

  it('fails cleanly with no session', function()
    package.loaded['dap'] = {
      session = function()
        return nil
      end,
    }
    local err = resolve 'buf'
    assert.is_truthy(err:find('no active debug session', 1, true))
  end)
end)

describe('memory.read', function()
  after_each(fake.uninstall)

  local function read(memref, offset, count)
    return await(function(cb)
      memory.read(memref, offset, count, cb)
    end)
  end

  it('decodes the base64 payload and returns the address', function()
    fake.install { memory = { ['0x1000+16'] = 'hello\0world' } }
    local err, data, address = read('0x1000', 16, 64)
    assert.is_nil(err)
    assert.are.equal('hello\0world', data)
    assert.are.equal('0x1010', address)
  end)

  it('refuses when the adapter does not advertise readMemory', function()
    local session = fake.install { capabilities = {} }
    local err = read('0x1000', 0, 16)
    assert.is_truthy(err:find('does not support readMemory', 1, true))
    assert.are.equal(0, #session.requests)
  end)

  it('surfaces adapter errors', function()
    fake.install {}
    local err, data = read('0xdead', 0, 16)
    assert.is_nil(data)
    assert.is_truthy(err:find('readMemory: memory read failed', 1, true))
  end)

  it('treats an empty payload as unreadable', function()
    fake.install { memory = { ['0x1000+0'] = '' } }
    local err, data = read('0x1000', 0, 16)
    assert.is_nil(data)
    assert.is_truthy(err:find('memory unreadable at 0x1000+0', 1, true))
  end)
end)
