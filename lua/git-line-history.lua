-- 选中一段代码后查看这段代码的 git line history（提交历史）
--
-- 在 visual 模式下选中几行，按 <leader>gl 弹出 Snacks picker，
-- 列出影响该行区间的全部提交；预览是 git show，回车 checkout 到该提交。
--
-- 原理：把视觉选区的起止行转成 `git log -L <start>,<end>:<file>`，
-- 复用 Snacks 自带的 git_log 格式与 git_show 预览。
local M = {}

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

---Snacks finder：异步执行 git log -L 并逐个产出 item
---@param opts git-line-history.Opts
---@param ctx snacks.picker.finder.ctx
---@return snacks.picker.finder.async
function M.history(opts, ctx)
  local args = {
    "-c", "core.quotepath=false",
    "log",
    "--pretty=format:%h %s (%ad) <%an>",
    "--abbrev-commit",
    "--decorate",
    "--date=short",
    "--color=never",
    "--no-show-signature",
    "--no-patch",
    "-L",
    ("%d,%d:%s"):format(opts.range[1], opts.range[2], opts.file),
  }

  return function(cb)
    require("snacks.picker.source.proc").proc(
      ctx:opts({
        cwd = opts.cwd,
        cmd = "git",
        args = args,
        ---@param item snacks.picker.finder.Item
        transform = function(item)
          local parsed = parse_line(item.text)
          if not parsed then
            return false -- 跳过 git 的告警/空行
          end
          item.commit = parsed.commit
          item.msg = parsed.msg
          item.date = parsed.date
          item.author = parsed.author
          item.cwd = opts.cwd
          item.file = opts.file
        end,
      }),
      ctx
    )(cb)
  end
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

  Snacks.picker.pick({
    cwd = cwd,
    format = "git_log",
    preview = "git_show",
    confirm = "git_checkout",
    finder = M.history,
    range = { s, e },
    file = rel,
    title = ("Git Line History: %s [%d,%d]"):format(rel, s, e),
    matcher = { sort_empty = false },
  })
end

return M
