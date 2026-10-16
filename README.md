# 💤 My Neovim Setup (LazyVim)

基于 [LazyVim](https://github.com/LazyVim/LazyVim) 的个人 Neovim 配置。

## 安装

```bash
# 1. 安装 Neovim 与 LazyVim 所需依赖（详见 LazyVim 官方文档）
# 2. 克隆本仓库到配置目录
git clone --filter=blob:none https://github.com/GengCen-Qin/nvim.git ~/.config/nvim
# 3. 打开 nvim，首次启动会自动安装 lazy.nvim 与插件
nvim
```

> 若本机已有配置，请先备份 `~/.config/nvim` 再克隆。

## 数据库连接（vim-dadbod）

本仓库**不含任何数据库密码**。连接配置通过本地文件提供：

```bash
cp ~/.config/nvim/db_connections.lua.example ~/.config/nvim/db_connections.lua
# 编辑 db_connections.lua，填入自己的连接（该文件被 .gitignore 忽略，不会提交）
```

`lua/config/options.lua` 会读取该文件并赋值给 `vim.g.dbs`。密码中的特殊字符需百分号编码（`+` → `%2B`，`*` → `%2A`）。

## 主要功能

- **数据库**：`<leader>fc` 选连接、`<leader>fd` 搜表结构、`<leader>fq` 新建 SQL buffer（见 `lua/plugins/dadbod-schema.lua`）
- **工作区切换**：`<leader>fw` 列出并切换 git worktree（见 `lua/worktree-switch.lua`）
- **Ruby 跳转**：基于 ctags-lsp 的定义跳转 / 符号搜索（见 `lua/plugins/ctags-lsp.lua`）
- 自动保存、注释色统一（`#EA999C`）、bufferline 常显等
