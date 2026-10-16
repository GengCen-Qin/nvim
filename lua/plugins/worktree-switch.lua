-- 在 git 项目中快速切换到某个 worktree（Git Worktree Switcher）
--
--   <leader>fw   列出当前 git 仓库的所有 worktree，选中一个后把全局 cwd
--                 切到该 worktree（等价 :cd），即成为当前项目。
--                 不自动打开文件/文件树，之后自行用 :e、文件树、picker 进入。
--
-- 用法示例：在主仓库里 <leader>fw，选中某个 feature worktree，即可
-- 直接在其中建文件 / 改代码，无需手动 :cd 或重开 nvim。
-- 从任意 worktree 内部按 <leader>fw 同样有效（会列出整个仓库的全部 worktree）。
--
-- 实现见 lua/worktree-switch.lua。
--
-- 注意：这里**不声明 lazy = true**。LazyVim 以 lazy = false 常驻加载 snacks.nvim，
-- 若在此重复声明 lazy 会覆盖掉它，导致 snacks 变成懒加载并影响 dashboard /
-- notifier 等依赖 snacks 的功能。只挂 keys 即安全。
return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>fw",
        function()
          require("worktree-switch").switch()
        end,
        desc = "Switch git worktree",
      },
    },
  },
}
