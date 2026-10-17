# 代理环境变量（2026-10-16 恢复；原先由用户自建的 proxy-env.fish，曾被删除）
# 行为：只在 FlClash 的 127.0.0.1:7890 有监听时才设置；没开代理时静默跳过，
#       避免把请求指到一个死端口（离线时 pi/nvim/paru 的下载不应该被代理弄坏）。
# 记录：~/.agents/skills/nvim-troubleshooting/references/local-patterns.md
if not set -q HTTPS_PROXY
    if ss -ltn 2>/dev/null | string match -qr ':7890'
        set -gx HTTP_PROXY  http://127.0.0.1:7890
        set -gx HTTPS_PROXY http://127.0.0.1:7890
        set -gx ALL_PROXY   socks5://127.0.0.1:7890
        set -gx http_proxy  http://127.0.0.1:7890
        set -gx https_proxy http://127.0.0.1:7890
        set -gx no_proxy    localhost,127.0.0.1,::1
    end
end
