vim.api.nvim_create_user_command('GitReview', function() require('git-review').open() end, {})
