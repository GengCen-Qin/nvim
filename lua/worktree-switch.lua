-- 在 git 项目中快速切换 worktree 的实现模块（被插件入口调用）
--
--   <leader>fw   列出当前 git 仓库的所有 worktree，选中一个后：
--                  把全局工作目录（cwd）切到该 worktree，即成为当前项目。
--                  不自动打开任何文件/文件树，之后用 :e、文件树、picker 自行进入。
--
-- 实现要点：
--   * 用 `git worktree list --porcelain` 解析，格式稳定、不怕列对齐漂移。
--   * 用 `git rev-parse --show-toplevel` 找 git 根：git 自己判定，可靠，
--     也完美兼容从某个 worktree 内部运行的情形。
--   * 显式用 Snacks.picker.select 做候选列表（可模糊搜索）；未装则退回 vim.ui.select。
--   * 切目录用 nvim_set_current_dir（等价 :cd，全局生效，不经过 cdpath）。
local M = {}

function M.switch()
  -- 当前 cwd 所属的 git 仓库根（git 自己判定，兼容 worktree 内部）
  local git_root = vim.fn.system({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    vim.notify("当前不在 git 仓库内", vim.log.levels.ERROR, { title = "Worktree" })
    return
  end
  git_root = vim.trim(git_root)

  -- 解析 `git worktree list --porcelain`：
  --   worktree <path>
  --   HEAD <sha>
  --   branch refs/heads/<name>   （detached 时是 detached 行，无 branch）
  local items = {} ---@type {path:string, branch:string?}[]
  local out = vim.fn.system({ "git", "-C", git_root, "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    vim.notify("获取 worktree 失败: " .. out, vim.log.levels.ERROR, { title = "Worktree" })
    return
  end
  local cur_path, cur_branch
  for line in vim.gsplit(out, "\n", { plain = true }) do
    local p = line:match("^worktree (.+)$")
    if p then
      cur_path = p
      cur_branch = nil
    elseif cur_path then
      local b = line:match("^branch refs/heads/(.+)$")
      if b then
        cur_branch = b
      end
    end
    if cur_path and (cur_branch or line:match("^detached$") or line == "") then
      -- 一条 worktree 记录结束（出现 branch/detached 后再下一行为空或下一个 worktree）
      items[#items + 1] = { path = cur_path, branch = cur_branch }
      cur_path = nil
    end
  end

  if #items == 0 then
    vim.notify("该仓库没有额外 worktree", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  local cwd = vim.uv.cwd() or ""
  local choices = vim.tbl_map(function(it)
    -- cwd 在该 worktree 路径下（含其子目录）即视为当前，标记放在行首便于查看
    local mark = (cwd == it.path or cwd:find(it.path, 1, true) == 1) and "● " or "  "
    local name = vim.fn.fnamemodify(it.path, ":t")
    local branch = it.branch and ("[" .. it.branch .. "]") or "[detached]"
    return { label = string.format("%s%-24s %s", mark, name, branch), path = it.path, branch = it.branch }
  end, items)

  -- 优先用 snacks picker 选择（可模糊搜索）；未装则退回 vim.ui.select
  local ok, snacks = pcall(require, "snacks")
  local select = (ok and snacks.picker and snacks.picker.select) or vim.ui.select

  select(choices, {
    prompt = "选择 git worktree",
    format_item = function(it)
      return it.label
    end,
    -- 放大展示框：比默认 select 预设更宽更高（默认宽 50% / 高 40%）
    snacks = {
      layout = {
        width = 0.65,
        min_width = 100,
        max_width = 160,
        height = 0.55,
      },
    },
  }, function(choice)
    if not choice then
      return
    end
    -- 切换全局 cwd 到该 worktree（等价 :cd），之后即以此为当前项目
    vim.api.nvim_set_current_dir(choice.path)
    vim.notify(
      string.format("已切换到 %s%s", choice.path, choice.branch and (" [" .. choice.branch .. "]") or ""),
      vim.log.levels.INFO,
      { title = "Worktree" }
    )
  end)
end

return M
