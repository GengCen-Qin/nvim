-- 通过 glab 查看当前项目的 GitLab MR，选中后在 buffer 里看 diff。
--
--   <leader>sm   当前项目里「我创建的」未合并 MR
--   <leader>sM   当前项目里「我创建的」全部 MR（含已合并 / 已关闭）
--
-- 交互：Snacks picker 列出 MR，右侧预览该 MR 的详情（等价 glab mr view 的字段
-- 排版），回车在新 tab 打开一个 ft=diff 的 buffer 展示 glab mr diff 的内容。
-- 列表里已合并 / 已关闭的会标 [merged] / [closed]，草稿标 [draft]。
--
-- 依赖：glab 必须已登录（本机 gitlab.yhlsoft.com）。实现见 lua/gitlab-mr.lua。
--
-- 同 gmr.lua：不声明 lazy = true（snacks 已常驻，声明 lazy 会把 snacks 变懒加载、
-- 影响 dashboard / notifier），只挂 keys 即安全。
return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>sm",
        function()
          require("gitlab-mr").open({ all = false })
        end,
        desc = "GitLab MR: my open MRs (gitlab-mr)",
      },
      {
        "<leader>sM",
        function()
          require("gitlab-mr").open({ all = true })
        end,
        desc = "GitLab MR: my MRs, incl. merged/closed (gitlab-mr)",
      },
    },
  },
}
