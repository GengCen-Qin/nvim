# git-review.nvim v7

Git diff review buffer for Neovim.

## LazyVim (lazy.nvim)

Unzip `git-review.nvim` into `~/.config/nvim/local-plugins/`, then add `~/.config/nvim/lua/plugins/git-review.lua`:

```lua
return {
  {
    dir = vim.fn.stdpath('config') .. '/local-plugins/git-review.nvim',
    cmd = 'GitReview',
    keys = {
      { '<leader>bb', '<cmd>GitReview<cr>', desc = 'Git Review' },
    },
  },
}
```

LazyVim normally uses Space as leader, so press `Space b b`.

## Changes from v6

- Highlight actual changed spans with a more vivid background and bold white text.
- Draw intraline extmarks after line highlights, with priority 1000.
- Keep existing change-block actions and navigation.

Use `?` in the review buffer to see mappings. Note that Neovim was not available for end-to-end testing in the packaging environment.
