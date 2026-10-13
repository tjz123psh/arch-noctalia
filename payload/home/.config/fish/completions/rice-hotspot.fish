# rice-hotspot：Wi-Fi 热点开关（~/bin/rice-hotspot）
# 子命令与用法见 rice-hotspot --help；改 SSID/密码/频段用 ~/.config/rice-hotspot.conf
# 或环境变量 RICE_HOTSPOT_SSID / RICE_HOTSPOT_PASSWORD / RICE_HOTSPOT_BAND / RICE_HOTSPOT_IFACE。
complete -c rice-hotspot -f
complete -c rice-hotspot -n '__fish_use_subcommand' -a on       -d '打开热点'
complete -c rice-hotspot -n '__fish_use_subcommand' -a off      -d '关闭热点'
complete -c rice-hotspot -n '__fish_use_subcommand' -a toggle   -d '切换（开着就关，关着就开）'
complete -c rice-hotspot -n '__fish_use_subcommand' -a status   -d '查看状态（SSID / 密码 / 网关）'
complete -c rice-hotspot -n '__fish_use_subcommand' -a state    -d '单行机器可读状态'
complete -c rice-hotspot -n '__fish_use_subcommand' -a password -d '只打印当前密码'
# 脚本也接受这些简写
complete -c rice-hotspot -n '__fish_use_subcommand' -a up -d '同 on'
complete -c rice-hotspot -n '__fish_use_subcommand' -a down -d '同 off'
complete -c rice-hotspot -n '__fish_use_subcommand' -a st -d '同 status'
complete -c rice-hotspot -n '__fish_use_subcommand' -a pw -d '同 password'
complete -c rice-hotspot -s h -l help -d '显示用法'
