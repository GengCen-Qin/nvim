#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 把 Rails 项目的 config/locales/**/*.yml 按 Rails 的 load_path 语义
# （递归 glob + 深合并，后面的文件覆盖前面）压成一份 JSON 缓存，供 nvim
# i18n-preview 插件读取。
#
# 用法:
#   ruby build_cache.rb <rails_root> <output.json>
#   WORKSPACE=<ws> ruby build_cache.rb <rails_root> <output.json>  # 附带 {WS}/config/locales/{home,acct}
#
# 输出结构: { locale => { "s" => {key => 字符串}, "h" => {key => "hash 预览"} } }

require 'yaml'
require 'json'

root = ARGV[0] || Dir.pwd
out_path = ARGV[1] || 'cache.json'
locales_dir = File.join(root, 'config', 'locales')

paths = Dir.glob(File.join(locales_dir, '**', '*.yml')).sort
if (ws = ENV['WORKSPACE']) && !ws.empty?
  paths += Dir.glob(File.join(ws, 'config', 'locales', 'home', '*.yml')).sort
  paths += Dir.glob(File.join(ws, 'config', 'locales', 'acct', '*.yml')).sort
end

def deep_merge(a, b)
  a.merge(b) do |_k, av, bv|
    av.is_a?(Hash) && bv.is_a?(Hash) ? deep_merge(av, bv) : bv
  end
end

data = {}
loaded = 0
skipped = []
paths.each do |p|
  begin
    doc = YAML.load_file(p, aliases: true)
  rescue StandardError => e
    skipped << "#{File.basename(p)}: #{e.message}"
    next
  end
  next unless doc.is_a?(Hash)
  data = deep_merge(data, doc)
  loaded += 1
end

out = {}
data.each do |locale, tree|
  next unless tree.is_a?(Hash)
  strings = {}
  hashes = {}

  walk = lambda do |node, prefix|
    node.each do |k, v|
      key = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
      case v
      when Hash
        preview = v.first(3).map { |ck, cv| "#{ck}=#{cv.is_a?(Hash) ? '{…}' : cv}" }.join(', ')
        preview += ', …' if v.size > 3
        hashes[key] = "#{v.size} 项: #{preview}"
        walk.call(v, key)
      when nil
        strings[key] = ''
      else
        strings[key] = v.is_a?(Array) ? v.join(', ') : v.to_s
      end
    end
  end
  walk.call(tree, '')
  out[locale.to_s] = { 's' => strings, 'h' => hashes }
end

# ---- 定义位置表：locale -> 完整 key -> [yaml 文件绝对路径, 1-based 行号] ----
# key 在 yml 里是嵌套写法（acctslt:\n  invstdisc:），无法 grep 定位；必须走
# Psych AST，取每个 key 标量的 start_line。按与上面相同的加载顺序遍历，
# 后加载文件覆盖先加载（与 deep_merge 语义一致，保证跳到的是生效的那个值）。
defs = Hash.new { |h, k| h[k] = {} }
paths.each do |p|
  begin
    doc = Psych.parse_stream(File.read(p))
  rescue StandardError
    next # 与上面 skipped 一致，跳过坏文件
  end
  collected = {}
  walk_ast = lambda do |node, prefix|
    next unless node.is_a?(Psych::Nodes::Mapping)
    node.children.each_slice(2) do |k, v|
      next unless k.is_a?(Psych::Nodes::Scalar)
      key = prefix.empty? ? k.value : "#{prefix}.#{k.value}"
      collected[key] = k.start_line + 1
      walk_ast.call(v, key) if v.is_a?(Psych::Nodes::Mapping)
    end
  end
  doc.children.each { |c| walk_ast.call(c.root, '') }
  collected.each do |full_key, line|
    locale, dot, rest = full_key.partition('.')
    defs[locale][rest] = [p, line] if !dot.empty? && !rest.empty?
  end
end
out.each_key { |locale| out[locale]['d'] = (defs[locale] || {}) }

File.write(out_path, JSON.generate(out))
warn "i18n-preview: #{paths.size} 个文件, 载入 #{loaded}, 跳过 #{skipped.size}, 写出 #{out_path} (#{File.size(out_path)} bytes)"
