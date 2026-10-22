-- blink.cmp 配置调整：让 buffer 源始终参与补全。
--
-- 本机 Ruby 用 ctags-lsp（不是 ruby-lsp）。ctags 只索引符号/标签，不索引局部
-- 变量，所以局部变量唯一的来源是 blink 的 buffer 源（扫当前文件文本）。
--
-- 但 blink 默认把 buffer 挂在 lsp / path 下面当 fallback
-- （config/sources.lua:58,63 的 fallbacks = { 'buffer' }）。tree.lua 里被
-- fallback 的源会变成依赖节点，只有依赖方返回 0 项时才会跑：只要 ctags 对当前
-- 前缀匹配到任何一个 tag，buffer 就被整个跳过，局部变量一个都不出现。
-- 用 ruby-lsp 时不会有这个问题（局部变量由 LSP 自己给），所以这是 ctags 方案
-- 特有的坑。清空 fallbacks 让 buffer 变成独立顶层源，始终并行参与。
return {
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        providers = {
          lsp = { fallbacks = {} },
          path = { fallbacks = {} },
          buffer = {
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
