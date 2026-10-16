-- 选中几行代码后查看其 git line history（提交历史）
--
--   <leader>gl (visual)   对当前视觉选区覆盖的代码行，弹出该区间的提交历史
--                         （git log -L 起,止:文件），回车可 checkout 到该提交。
--
-- 实现见 lua/git-line-history.lua。
--
-- 注意：
--   * normal 模式的 <leader>gl 仍是 LazyVim 自带的「仓库 Git Log」，不受影响；
--     此映射只在 visual 模式生效，两者不冲突。
--   * 这里**不声明 lazy = true**，理由同 worktree-switch.lua（snacks 已常驻）。
return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>gl",
        function()
          require("git-line-history").open()
        end,
        mode = "v",
        desc = "Git Line History (visual selection)",
      },
    },
  },
}
