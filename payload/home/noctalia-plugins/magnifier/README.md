# Magnifier 1.1.0 · 本机试样

- 鼠标跟随仍直接更新视口；键盘倍率和方向键平移采用140ms可中断过渡，重复输入以最后目标为准。
- 维持串行抓帧和最新请求合并，失败时保留最近一张好图；仅保留最近三张已完成帧。
- 截图、光标和心跳按打开轮次独立命名。关闭与迟到回调只删除自己创建的精确路径，不使用通配清理或全局 pkill。
- 保存精确的半像素视口中心，避免奇数尺寸下反复开关漂移。关闭时保存最后操作的目标倍率。
- 配套追踪器每轮事件循环检查心跳，正常轮询上限100ms；鼠标持续移动不再延后退出检查。

## 离线检查

从父目录运行：

```sh
lua magnifier/tests/magnifier_spec.lua
gcc -std=c11 -O2 -Wall -Wextra -Werror magnifier/tests/tracker_lease_spec.c -o magnifier/tests/tracker-lease-test
magnifier/tests/tracker-lease-test
bash magnifier/tools/cursor-track/build.sh
```

Lua测试只使用内存文件与命令队列；C测试不连接Wayland。它们不等于实际帧率或视觉验收。请在便签已保存且面板关闭时更新本地插件，不自动关闭用户窗口。
