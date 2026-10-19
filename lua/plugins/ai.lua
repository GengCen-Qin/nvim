return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    -- NOTE: The log_level is in `opts.opts`
    opts = {
      log_level = "DEBUG", -- or "TRACE"
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
