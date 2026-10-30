-- blink.cmp 配置调整：让 buffer 源参与补全、局部变量优先、确认键改到 Tab。
--
-- 本机 Ruby 用 ctags-lsp（不是 ruby-lsp）。ctags 只索引符号/标签，不索引局部
-- 变量，所以局部变量唯一的来源是 blink 的 buffer 源（扫当前文件文本）。
--
-- 1) buffer 必须独立参与
-- blink 默认把 buffer 挂在 lsp / path 下面当 fallback
-- （config/sources.lua 的 fallbacks = { 'buffer' }）。被 fallback 的源只有在
-- 依赖方返回 0 项时才跑：只要 ctags 对当前前缀匹配到任何一个 tag，buffer 就被
-- 整个跳过，局部变量一个都不出现。清空 fallbacks 让 buffer 变成独立顶层源。
-- 用 ruby-lsp 时不会有这个问题（局部变量由 LSP 自己给），所以这是 ctags 方案
-- 特有的坑。
--
-- 2) 局部变量优先
-- buffer 源默认 score_offset = -3（比 LSP 的 0 低）。前缀匹配的基分往往完全
-- 相同：输入 on 时 one / one_err / one_two / one_two_three 的模糊匹配分一样，
-- 于是 -3 让 ctags 的方法名整齐排在局部变量 one 前面。把 buffer 提到正分，
-- 保证「变量也匹配时优先变量」；更精确的方法名（精确匹配、frecency 高的）
-- 基分更高，仍然排在前面。
--
-- 3) 键位：Tab 确认、Up/Down 选择，回车只换行
-- LazyVim 用 preset = "enter"（回车接受第一个补全）。改成 preset = "none" 后
-- 不再映射 <CR>，回车恢复为普通换行；接受补全交给 <Tab>。
return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        preset = "none",
        -- 有菜单时接受选中的补全，否则先走 snippet 跳转，最后回落到原生 Tab
        ["<Tab>"] = { "accept", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
        -- 上下键选择补全项；没有菜单时回落到原生光标移动
        ["<Down>"] = { "select_next", "fallback" },
        ["<Up>"] = { "select_prev", "fallback" },
        ["<C-n>"] = { "select_next", "fallback_to_mappings" },
        ["<C-p>"] = { "select_prev", "fallback_to_mappings" },
        ["<C-y>"] = { "select_and_accept", "fallback" },
        ["<C-e>"] = { "cancel", "fallback" },
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
      },
      sources = {
        providers = {
          lsp = { fallbacks = {} },
          path = { fallbacks = {} },
          buffer = {
            -- 默认 -3，比 LSP 低；提到正分让局部变量压过同名/同前缀的 ctags 方法名
            score_offset = 3,
            opts = {
              -- 超过这个大小的文件走异步解析（Rust）
              max_sync_buffer_size = 20000,
              -- 单文件超过此大小会被整个跳过；默认 200KB，而 PAS 有 16+ 个
              -- 核心 .rb 超过它（最大 ~450KB），放宽到 1MB 覆盖全部项目文件
              max_async_buffer_size = 1000000,
              -- 所有参与补全的缓冲合计大小上限
              max_total_buffer_size = 2000000,
            },
          },
        },
      },
    },
  },
}
