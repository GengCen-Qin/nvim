-- gitsigns：在 LazyVim 默认键位基础上补充 <C-S-z>（重置当前 hunk，等价 <leader>ghr）
-- 说明：<C-S-z> 只有在终端/多路复用器支持增强键盘协议（kitty protocol / CSI u）时才会与 <C-z> 区分。
-- Windows Terminal / zellij 多数情况下两者发送同一字节，所以同时把 <C-z> 也指到同一动作做兜底。
-- 这里整体重写 on_attach（内容与 LazyVim 一致 + 新增两行），避免依赖 LazyVim 内部私有函数。
return {
  {
    "lewis6991/gitsigns.nvim",
    event = "LazyFile",
    opts = function(_, opts)
      opts.on_attach = function(buffer)
        local gs = package.loaded.gitsigns

        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc, silent = true, nowait = true })
        end

        map("n", "]h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next Hunk")
        map("n", "[h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Prev Hunk")
        map("n", "]H", function() gs.nav_hunk("last") end, "Last Hunk")
        map("n", "[H", function() gs.nav_hunk("first") end, "First Hunk")
        map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
        map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
        map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
        map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo Stage Hunk")
        map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
        map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
        map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame Line")
        map("n", "<leader>ghB", function() gs.blame() end, "Blame Buffer")
        map("n", "<leader>ghd", gs.diffthis, "Diff This")
        map("n", "<leader>ghD", function() gs.diffthis("~") end, "Diff This ~")
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "GitSigns Select Hunk")

        -- 重置当前 hunk：<C-S-z> 为主，<C-z> 兜底（终端区分不出 Shift 时）
        map("n", "<C-S-z>", gs.reset_hunk, "Reset Hunk")
        map("n", "<C-z>", gs.reset_hunk, "Reset Hunk")
      end
      return opts
    end,
  },
}
