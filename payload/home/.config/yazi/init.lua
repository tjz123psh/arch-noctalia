-- yazi 初始化脚本（本机手工维护）
--
-- 这里只放「必须用 Lua 才能装」的东西：第三方插件的 setup。
-- 目前只有 git 插件：把每个文件的 git 状态算出来，显示在文件列表右侧的 linemode 列。
--   怎么用：在 yazi 里按 m g 切成 git 状态列（m s 切回大小 / m p 权限 / m n 关掉）。
--   插件本体：~/.config/yazi/plugins/git.yazi/（官方 yazi-rs/plugins 仓库）
--   抓取器注册：yazi.toml 的 [plugin] 段（不注册的话这个插件不会被调用）
require("git"):setup{
	-- 状态符号在 linemode 里的排序权重，越大越靠右（插件默认 1500）
	order = 1500,
}
