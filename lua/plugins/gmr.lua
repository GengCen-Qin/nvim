-- 把当前分支改动提到 GitLab MR（Merge Request）
--
--   <leader>gm   对当前 git 仓库：提取分支里的 Jira key → 判定 target/assignee/
--                reviewer → 输入 MR 描述 → 抓 Jira 标题 → 预览确认 → push +
--                glab mr create。成功后通知里给出 MR 链接。
--
-- 交互顺序（每一步都可以取消）：
--   1. vim.ui.select   选择 MR 目标分支（列出本地 origin/* 远端跟踪分支）
--   2. vim.ui.input    输入 MR 描述
--   3. vim.ui.select   是否以 draft 形式提交 MR（No 在前，回车走正常创建）
--   确认后自动做远端写操作（git push + glab mr create）。
--
-- 依赖：git / glab / jira 必须在 PATH 上，且 glab 已登录 gitlab.yhlsoft.com。
-- 实现见 lua/gmr.lua（逻辑与 ~/.config/fish/functions/gmr.fish 一致，解析 Jira
-- 响应改用 vim.json，不再依赖 jq）。
--
-- 注意：这里**不声明 lazy = true**，理由同 worktree-switch.lua（snacks 已常驻，
-- 声明 lazy 会把 snacks 变懒加载并影响 dashboard / notifier）。只挂 keys 即安全。
return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>gm",
        function()
          require("gmr").create()
        end,
        desc = "GitLab: create MR (gmr)",
      },
    },
  },
}
