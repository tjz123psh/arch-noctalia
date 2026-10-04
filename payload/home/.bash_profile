#
# ~/.bash_profile
#
[[ -f ~/.bashrc ]] && . ~/.bashrc

# --- niri autostart on tty1 (DSH rice) ---
# 直接从登录会话启动，让 libseat/logind 拿到 seat0
if [[ -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then
    exec niri >/tmp/niri-tty1.log 2>&1
fi
