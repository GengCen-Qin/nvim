return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  -- 不写 cmd 时 LazyVim 默认 lazy=false，codecompanion 会在启动时就 require，
  -- 而它的 providers 探测会 pcall(require, "blink.cmp")（见
  -- codecompanion/providers/init.lua 的 find_provider），于是连带把本该
  -- InsertEnter 才加载的 blink.cmp 也拽到启动期，两边合计 ~100ms+。
  -- 列上 cmd 后 lazy.nvim 建命令桩，首次用 :CodeCompanion* 时才加载。
  cmd = {
    "CodeCompanion",
    "CodeCompanionChat",
    "CodeCompanionActions",
    "CodeCompanionCmd",
    "CodeCompanionCLI",
    "CodeCompanionCodeReview",
  },
  opts = {
    -- NOTE: The log_level is in `opts.opts`
    opts = {
      -- 插件默认即 ERROR。DEBUG 会把每次请求/上下文/文件监听都同步写进
      -- ~/.local/state/nvim/codecompanion.log，聊天期间持续产生磁盘写。
      log_level = "ERROR",
    },
    -- 让 Claude Code 作为默认聊天适配器（ACP 模式，需已装 claude-agent-acp）；
    -- inline 改用 DeepSeek（更快、更省，适合解释/重构小段代码）。
    -- 插件默认 chat/inline 都是 "copilot"，不设的话会用 Copilot 适配器，
    -- 本机没配 Copilot token 会报 "No token found" 红字。
    -- DeepSeek 的 key 不写在这里，由环境变量 DEEPSEEK_API_KEY 提供
    -- （见 ~/.config/fish/config.fish：set -gx DEEPSEEK_API_KEY $DEEPSEEK_KEY）。
    interactions = {
      chat = {
        adapter = "claude_code",
      },
      inline = {
        adapter = "deepseek",
      },
    },
  },
}
