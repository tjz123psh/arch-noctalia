#
# ~/.bash_profile
#
[[ -f ~/.bashrc ]] && . ~/.bashrc

# 注：旧的 tty1「exec niri」自动启动已移除 —— 它会截胡 greetd→niri-session，
# 使 graphical-session.target 不激活、xdg-desktop-portal-gnome 起不来（录屏/共享失效）。

