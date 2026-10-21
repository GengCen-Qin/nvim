-- 选中一段代码后查看这段代码的 git line history（提交历史）
--
-- 在 visual 模式下选中几行，按 <leader>gl 弹出 Snacks picker，
-- 列出影响该行区间的全部提交；预览只展示该提交对这几行的改动（而不是整个提交），
-- 回车 checkout 到该提交。
--
-- 原理：`git log -p -L <start>,<end>:<file>` 一次拿到该行区间的全部提交，
-- 每个提交后面跟着的 patch 就是 git 从当前版本追踪出来的、恰好覆盖这几行的改动。
local M = {}

-- git --pretty 里用它标记每个提交的开头，避免与 patch 内容混淆
local SEP = "\1"

---解析一行 `git log --pretty` 输出（与 snacks picker source/git.lua 一致）
---@param line string
---@return snacks.picker.finder.Item|nil
local function parse_line(line)
  local commit, msg, date, author = line:match("^(%S+) (.*) %((.*)%) <(.*)>$")
  if not commit then
    return nil
  end
  return {
    text = line,
    commit = commit,
    msg = msg,
    date = date,
    author = author,
  }
end

---@class git-line-history.Opts
---@field range integer[] 起止行
---@field file string 相对 git 根目录的路径
---@field cwd string git 根目录

---跑一次 `git log -p -L`，按提交切成 item，每个 item 带该提交对所选行范围的 patch
---@param opts git-line-history.Opts
---@return snacks.picker.finder.Item[]
local function collect(opts)
  local args = {
    "-c", "core.quotepath=false",
    "log",
    "--pretty=format:" .. SEP .. "%h %s (%ad) <%an>",
    "--abbrev-commit",
    "--decorate",
    "--date=short",
    "--color=never",
    "--no-show-signature",
    "-p",
    "-L",
    ("%d,%d:%s"):format(opts.range[1], opts.range[2], opts.file),
  }

  local out = vim.system(vim.list_extend({ "git" }, args), { cwd = opts.cwd, text = true }):wait(5000)
  if out.code ~= 0 then
    Snacks.notify.warn(vim.trim(out.stderr or "git log -L 执行失败"), { title = "Git Line History" })
    return {}
  end

  local items, patch = {}, nil
  for _, line in ipairs(vim.split(out.stdout or "", "\n", { plain = true })) do
    if line:sub(1, 1) == SEP then
      patch = nil
      local parsed = parse_line(line:sub(2))
      if parsed then
        patch = {}
        parsed.patch = patch
        parsed.cwd = opts.cwd
        parsed.file = opts.file
        items[#items + 1] = parsed
      end
    elseif patch then
      patch[#patch + 1] = line
    end
  end
  return items
end

---预览：只展示该提交对所选行范围的改动，而不是整个提交
---@param ctx snacks.picker.preview.ctx
function M.preview(ctx)
  local patch = ctx.item.patch or {}
  -- 丢掉 diff --git / index / --- / +++ 这些头部，直接从 hunk 开始看
  local start
  for i, line in ipairs(patch) do
    if line:sub(1, 2) == "@@" then
      start = i
      break
    end
  end
  if not start then
    -- 该提交没有针对这段行的 hunk，回退到 snacks 自带的整个提交预览
    return require("snacks.picker.preview").git_show(ctx)
  end
  ctx.preview:set_lines(vim.list_slice(patch, start))
  ctx.preview:highlight({ ft = "git" })
end

---取当前选区起止行
---注意：visual 模式下用 Lua 回调触发映射时，'< '> 标记尚未更新（恒为 0），
---此时必须用 line("v")（选区锚点）与 line(".")（光标）取范围。
---@return integer, integer
local function visual_range()
  local s, e
  if vim.fn.mode():find("[vV\22]") then
    s, e = vim.fn.line("v"), vim.fn.line(".")
  else
    s, e = vim.fn.line("'<"), vim.fn.line("'>")
  end
  if s == 0 or e == 0 then
    s, e = vim.fn.line("."), vim.fn.line(".")
  end
  if s > e then
    s, e = e, s
  end
  return s, e
end

---入口：visual 选中若干行后调用，打开该区间的 line history
function M.open()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    Snacks.notify.warn("当前 buffer 无文件名", { title = "Git Line History" })
    return
  end

  local s, e = visual_range()
  -- 退出 visual，避免 picker 打开时仍处于选区状态
  if vim.fn.mode():find("[vV\22]") then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  end

  local cwd = Snacks.git.get_root(vim.fs.dirname(file)) or vim.fn.getcwd()
  local rel = vim.fs.relpath(cwd, vim.fs.normalize(file)) or file
  local title = ("Git Line History: %s [%d,%d]"):format(rel, s, e)

  local items = collect({ range = { s, e }, file = rel, cwd = cwd })
  if #items == 0 then
    Snacks.notify.info(("没有提交改过 %s 的 %d-%d 行"):format(rel, s, e), { title = "Git Line History" })
    return
  end

  Snacks.picker.pick({
    cwd = cwd,
    items = items,
    format = "git_log",
    preview = M.preview,
    confirm = "git_checkout",
    title = title,
    matcher = { sort_empty = false },
  })
end

return M
