-- 自定义 <leader>fp（projects picker）的列表来源。
--
-- 只展示两处：
--   1. /home/lucas/RubyProjects 下的 git 仓库（靠 fd 扫 .git 标记自动发现，新增仓库无需改配置）
--   2. /home/lucas/RubyProjects/log（不是 git 仓库，手动加进 projects）
--
-- recent = false 关掉「从历史文件反查 git 根」的自动收录，dev 换掉默认的 ~/dev、~/projects，
-- patterns 只留 .git，避免 package.json / Makefile 这类非 git 目录也被当成项目。
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = opts.picker or {}
      opts.picker.sources = opts.picker.sources or {}
      opts.picker.sources.projects = {
        recent = false,
        dev = { "/home/lucas/RubyProjects" },
        patterns = { ".git" },
        projects = { "/home/lucas/RubyProjects/log" },
      }
      return opts
    end,
  },
}
