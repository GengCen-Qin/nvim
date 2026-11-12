local M = {}
local ns = vim.api.nvim_create_namespace('git_review')
local state = {}
local function split(s)
  if not s or s == '' then return {} end
  return vim.split(s:gsub('\n$', ''), '\n', { plain = true })
end
local function git(args, input)
  local cmd = { 'git', '-C', state.root }
  vim.list_extend(cmd, args)
  local out = vim.fn.system(cmd, input)
  if vim.v.shell_error ~= 0 then return nil, out end
  return out
end
local function warn(s) vim.notify(s, vim.log.levels.ERROR) end
local function parse_diff(section, diff, output, meta)
  local file, hunk
  local function add(line, m)
    output[#output + 1] = line
    if m then meta[#output] = m end
    return #output
  end
  for _, line in ipairs(split(diff)) do
    if line:match('^diff %-%-git ') then
      file = { section = section, header_lines = {}, hunks = {} }
      hunk = nil
    end
    if not file then add(line) else
      if line:match('^@@ ') then
        local a, ac, b, bc = line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
        if a then
          hunk = { file = file, old_start = tonumber(a), new_start = tonumber(b), lines = {}, blocks = {} }
          file.hunks[#file.hunks + 1] = hunk
          hunk.old_cursor, hunk.new_cursor = tonumber(a), tonumber(b)
        end
      end
      if not hunk then
        file.header_lines[#file.header_lines + 1] = line
        if line:match('^%+%+%+ ') then
          local p = line:sub(5)
          if p ~= '/dev/null' then file.path = p:gsub('^b/', '') end
        end
        add(line, { section = section, file = file })
      else
        local m = { section = section, file = file, hunk = hunk, old = hunk.old_cursor, new = hunk.new_cursor }
        if line:match('^@@ ') then
          m.old, m.new = hunk.old_start, hunk.new_start
        else
          local c = line:sub(1, 1)
          if c == '-' then hunk.old_cursor = hunk.old_cursor + 1
          elseif c == '+' then hunk.new_cursor = hunk.new_cursor + 1
          elseif c == ' ' then
            hunk.old_cursor = hunk.old_cursor + 1
            hunk.new_cursor = hunk.new_cursor + 1
          end
        end
        local row = add(line, m)
        if not line:match('^@@ ') then
          hunk.lines[#hunk.lines + 1] = { text = line, row = row, old = m.old, new = m.new }
        end
      end
    end
  end
  for _, m in pairs(meta) do
    local h = m.hunk
    if h and not h.parsed then
      h.parsed = true
      local active
      for i, item in ipairs(h.lines) do
        local c = item.text:sub(1, 1)
        if c == '+' or c == '-' then
          if not active then
            active = { first = i, last = i, hunk = h }
            h.blocks[#h.blocks + 1] = active
          else active.last = i end
          item.block = active
        elseif c == ' ' then active = nil end
      end
      for _, block in ipairs(h.blocks) do
        for i = block.first, block.last do
          meta[h.lines[i].row].block = block
        end
      end
    end
  end
end
local function mark(buf, row, start_col, end_col, group)
  if end_col > start_col then
    vim.api.nvim_buf_set_extmark(buf, ns, row - 1, start_col, {
      end_col = end_col, hl_group = group, priority = 1000,
    })
  end
end
local function intraline(buf, h)
  for _, block in ipairs(h.blocks) do
    local dels, adds = {}, {}
    for i = block.first, block.last do
      local item = h.lines[i]
      if item.text:sub(1, 1) == '-' then dels[#dels + 1] = item end
      if item.text:sub(1, 1) == '+' then adds[#adds + 1] = item end
    end
    for i = 1, math.min(#dels, #adds) do
      local a, b = dels[i], adds[i]
      local old, new = a.text:sub(2), b.text:sub(2)
      local prefix = 0
      while prefix < math.min(#old, #new) and old:byte(prefix + 1) == new:byte(prefix + 1) do prefix = prefix + 1 end
      local suffix = 0
      while suffix < math.min(#old, #new) - prefix
        and old:byte(#old - suffix) == new:byte(#new - suffix) do suffix = suffix + 1 end
      mark(buf, a.row, 1 + prefix, 1 + #old - suffix, 'GitReviewDeleteText')
      mark(buf, b.row, 1 + prefix, 1 + #new - suffix, 'GitReviewAddText')
    end
  end
end
local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local staged, e1 = git({ 'diff', '--cached', '--no-ext-diff', '--no-color', '--no-renames' })
  if not staged then return warn(e1) end
  local unstaged, e2 = git({ 'diff', '--no-ext-diff', '--no-color', '--no-renames' })
  if not unstaged then return warn(e2) end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local output, meta = {}, {}
  local function add(s) output[#output + 1] = s end
  add('STAGED CHANGES')
  for _, s in ipairs(split(git({ 'diff', '--cached', '--stat', '--no-renames' }))) do add(s) end
  if staged == '' then add('  (none)') else parse_diff('staged', staged, output, meta) end
  add('')
  state.unstaged_start = #output + 1
  add('UNSTAGED CHANGES')
  for _, s in ipairs(split(git({ 'diff', '--stat', '--no-renames' }))) do add(s) end
  if unstaged == '' then add('  (none)') else parse_diff('unstaged', unstaged, output, meta) end
  state.meta = meta
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, output)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  vim.api.nvim_set_hl(0, 'GitReviewAddText', { bg = '#008f4f', fg = '#ffffff', bold = true })
  vim.api.nvim_set_hl(0, 'GitReviewDeleteText', { bg = '#bf3030', fg = '#ffffff', bold = true })
  for i, line in ipairs(output) do
    local group
    if line == 'STAGED CHANGES' or line == 'UNSTAGED CHANGES' then group = 'Title'
    elseif line:match('^diff %-%-git') then group = 'Directory'
    elseif line:match('^@@') then group = 'DiffChange'
    elseif line:match('^%+') and not line:match('^%+%+%+') then group = 'DiffAdd'
    elseif line:match('^%-') and not line:match('^%-%-%-') then group = 'DiffDelete' end
    if group then vim.api.nvim_buf_add_highlight(state.buf, ns, group, i - 1, 0, -1) end
  end
  -- Apply intra-line extmarks after all full-line highlights.
  local seen = {}
  for _, m in pairs(meta) do
    local h = m.hunk
    if h and not seen[h] then
      seen[h] = true
      intraline(state.buf, h)
    end
  end
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(row, #output)), 0 })
end
local function current()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local m = state.meta[row]
  if not m or not m.hunk or m.block then return m end
  local nearest, distance
  for _, b in ipairs(m.hunk.blocks) do
    local first = m.hunk.lines[b.first].row
    local last = m.hunk.lines[b.last].row
    local d = math.max(first - row, row - last, 0)
    if not distance or d < distance or (d == distance and first > row) then
      nearest, distance = b, d
    end
  end
  m.block = nearest
  return m
end
-- postimage: build context from the '+' side of the diff, i.e. from the
-- content the patch is applied against (index for unstage, worktree for discard).
local function hunk_patch(h, selected, postimage)
  local out = {}
  local old_count, new_count = 0, 0
  local old_start, new_start = h.old_start, h.new_start
  if postimage and selected then old_start = h.new_start end
  local found = false
  for _, item in ipairs(h.lines) do
    local c = item.text:sub(1, 1)
    local use = not selected or item.block == selected
    if c == ' ' then
      out[#out + 1] = item.text
      old_count, new_count = old_count + 1, new_count + 1
    elseif c == '-' then
      if use then
        out[#out + 1] = item.text
        old_count = old_count + 1
        found = true
      elseif not postimage then
        out[#out + 1] = ' ' .. item.text:sub(2)
        old_count, new_count = old_count + 1, new_count + 1
      end
    elseif c == '+' then
      if use then
        out[#out + 1] = item.text
        new_count = new_count + 1
        found = true
      elseif postimage then
        out[#out + 1] = ' ' .. item.text:sub(2)
        old_count, new_count = old_count + 1, new_count + 1
      end
    elseif c == '\\' and use then out[#out + 1] = item.text end
  end
  if not found then return nil end
  local header = string.format('@@ -%d,%d +%d,%d @@', old_start, old_count, new_start, new_count)
  return header .. '\n' .. table.concat(out, '\n') .. '\n'
end
local function patch(m, whole, postimage)
  local out = vim.deepcopy(m.file.header_lines)
  for _, h in ipairs(m.file.hunks) do
    if whole or h == m.hunk then
      local p = hunk_patch(h, whole and nil or m.block, postimage)
      if p then out[#out + 1] = p:gsub('\n$', '') end
    end
  end
  return table.concat(out, '\n') .. '\n'
end
local function action(kind, whole)
  local m = current()
  if not m or not m.file or not m.file.path then return warn('Move cursor to a diff file/hunk') end
  if not whole and not m.block then return warn('Move cursor to a changed line') end
  if kind == 'stage' and m.section ~= 'unstaged' or kind == 'unstage' and m.section ~= 'staged' then
    return warn('Action does not apply to this section')
  end
  if kind == 'discard' then
    if m.section == 'staged' then return warn('Unstage first before discarding staged changes') end
    if vim.fn.confirm('Discard selected changes in ' .. m.file.path .. '?', '&Yes\n&No', 2) ~= 1 then return end
  end
  local args = { 'apply', '--recount', '--unidiff-zero' }
  if kind == 'stage' then args[#args + 1] = '--cached'
  elseif kind == 'unstage' then
    args[#args + 1] = '--cached'; args[#args + 1] = '--reverse'
  else args[#args + 1] = '--reverse' end
  -- stage patches against the index (preimage); unstage/discard patch against
  -- the applied target's current content (postimage), otherwise partial
  -- hunks never match and every unstage/discard fails validation.
  local input = patch(m, whole, kind ~= 'stage')
  local check_args = vim.deepcopy(args)
  table.insert(check_args, 2, '--check')
  local checked, check_err = git(check_args, input)
  if not checked then return warn('Patch validation failed; no changes discarded/applied:\n' .. check_err) end
  local result, err = git(args, input)
  if not result then return warn(err) end
  render()
end
local function open_file()
  local m = current()
  if not m or not m.file or not m.file.path then return end
  local target = math.max(1, m.new or 1)
  vim.cmd('edit ' .. vim.fn.fnameescape(state.root .. '/' .. m.file.path))
  vim.api.nvim_win_set_cursor(0, { math.min(target, vim.api.nvim_buf_line_count(0)), 0 })
end
local function help()
  local lines = {
    'Git Review — Keymaps', '',
    '  ?       Show / hide this help',
    '  o       Open file at cursor',
    '  <Tab>   Switch staged / unstaged',
    '  [ / ]   Previous / next change block',
    '  [f / ]f Previous / next changed file',
    '  3]      Jump three change blocks',
    '  s / u   Stage / unstage change block',
    '  d       Discard change block (confirm)',
    '  S / U   Stage / unstage whole file',
    '  D       Discard whole file (confirm)',
    '  c       Commit staged changes',
    '  r       Refresh diff',
    '  q       Close review (or help)',
    '', '  Press ? or q to close this help.',
  }
  if state.help_win and vim.api.nvim_win_is_valid(state.help_win) then
    vim.api.nvim_win_close(state.help_win, true)
    state.help_win = nil
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = 48
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    title = ' Git Review Help ', title_pos = 'center',
  })
  state.help_win = win
  for _, key in ipairs({ '?', 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if state.help_win == win then state.help_win = nil end
    end, { buffer = buf, silent = true, nowait = true })
  end
end
-- Navigate across change blocks or file sections, wrapping at either end.
local function jump(kind, direction)
  local targets, seen = {}, {}
  for row = 1, vim.api.nvim_buf_line_count(state.buf) do
    local m = state.meta and state.meta[row]
    if m then
      local object = kind == 'block' and m.block or m.file
      if object and not seen[object] then
        seen[object] = true
        -- For files, land on their diff --git header; for blocks, first changed line.
        targets[#targets + 1] = row
      end
    end
  end
  if #targets == 0 then
    return vim.notify('No ' .. (kind == 'block' and 'changes' or 'files') .. ' to navigate', vim.log.levels.INFO)
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local count = vim.v.count1
  local destination
  for _ = 1, count do
    local next_row
    if direction > 0 then
      for _, target in ipairs(targets) do
        if target > row then next_row = target; break end
      end
      row = next_row or targets[1]
    else
      for i = #targets, 1, -1 do
        if targets[i] < row then next_row = targets[i]; break end
      end
      row = next_row or targets[#targets]
    end
    destination = row
  end
  vim.api.nvim_win_set_cursor(0, { destination, 0 })
  vim.cmd('normal! zz')
end

local function commit()
  local staged, err = git({ 'diff', '--cached', '--name-only' })
  if not staged then return warn(err) end
  if staged == '' then return vim.notify('Nothing staged to commit', vim.log.levels.INFO) end
  vim.ui.input({ prompt = 'Commit message: ' }, function(message)
    if message == nil then return end
    if not message:match('%S') then
      return vim.notify('Commit cancelled: empty message', vim.log.levels.WARN)
    end
    local output, failure = git({ 'commit', '-m', message })
    if not output then return warn('Git commit failed: ' .. (failure or 'unknown error')) end
    vim.notify(output:gsub('%s+$', ''), vim.log.levels.INFO)
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      local win = vim.fn.bufwinid(state.buf)
      if win ~= -1 then vim.api.nvim_win_call(win, render) end
    end
  end)
end
-- Path of the file being edited (relative to the repo root) and the cursor line,
-- so opening the review can land on that very change.
local function source_position(root)
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' or vim.bo.buftype ~= '' then return nil end
  local file = vim.fn.fnamemodify(name, ':p')
  if vim.fn.filereadable(file) ~= 1 then return nil end
  local prefix = vim.fn.fnamemodify(root, ':p'):gsub('/+$', '') .. '/'
  if file:sub(1, #prefix) ~= prefix then return nil end
  return { file = file:sub(#prefix + 1), line = vim.fn.line('.') }
end
local function jump_to_source()
  local jump = state.jump
  if not jump or not state.meta then return end
  -- Worktree line numbers match the unstaged diff; fall back to staged when
  -- the file has no unstaged changes (index line numbers == worktree then).
  for _, section in ipairs({ 'unstaged', 'staged' }) do
    for _, m in pairs(state.meta) do
      if m and m.section == section and m.hunk and m.file and m.file.path == jump.file then
        for _, item in ipairs(m.hunk.lines) do
          if item.new == jump.line and item.text:sub(1, 1) == '+' then
            vim.api.nvim_win_set_cursor(0, { item.row, 0 })
            vim.cmd('normal! zz')
            return
          end
        end
      end
    end
  end
end
function M.open()
  local root = vim.fn.systemlist({ 'git', 'rev-parse', '--show-toplevel' })[1]
  if vim.v.shell_error ~= 0 or not root then return warn('Not inside a Git repository') end
  state.root = root
  state.jump = source_position(root)
  vim.cmd('enew')
  state.buf = vim.api.nvim_get_current_buf()
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].bufhidden = 'wipe'
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = 'diff'
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_set_name(state.buf, 'git-review://' .. vim.fn.fnamemodify(root, ':t'))
  local function map(key, fn)
    vim.keymap.set('n', key, fn, { buffer = state.buf, silent = true })
  end
  map('o', open_file)
  map('[', function() jump('block', -1) end)
  map(']', function() jump('block', 1) end)
  map('[f', function() jump('file', -1) end)
  map(']f', function() jump('file', 1) end)
  map('<Tab>', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_win_set_cursor(0, { row < state.unstaged_start and state.unstaged_start or 1, 0 })
  end)
  map('s', function() action('stage', false) end)
  map('u', function() action('unstage', false) end)
  map('d', function() action('discard', false) end)
  map('S', function() action('stage', true) end)
  map('U', function() action('unstage', true) end)
  map('D', function() action('discard', true) end)
  map('?', help)
  map('c', commit)
  map('r', render)
  map('q', function() vim.cmd('bd!') end)
  for _, key in ipairs({ 'i', 'a', 'I', 'A', 'C', 'R' }) do map(key, function() end) end
  render()
  jump_to_source()
end
return M
