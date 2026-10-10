# 光标追踪工具

此目录是放大镜的开发源码，不是运行数据目录。当前插件调用的是[已安装副本](</home/pang/bin/cursor-track>)。

## 目录分工

- [cursor-track.c](<cursor-track.c>)：工具源码。
- [build.sh](<build.sh>)：稳定的构建／安装入口。
- [protocols](<protocols/>)：随仓库提供的 Wayland 协议源码，必须保留。
- `build/`：自动生成的 C 文件、头文件和可执行文件，可重新构建，已从 Git 排除。

构建不联网下载协议。导出或复制本工具时，必须一并保留 protocols 目录。

## 输入层释放

心跳/输出文件检查位于每轮事件循环，而非仅在鼠标空闲时执行。正常轮询上限100ms；调用方心跳消失或超时即退出。点击记录仍保留给插件读取，不在进程退出前删除记录文件。

## 构建

需要 gcc、wayland-scanner、wayland-protocols 和 pkg-config（Arch 对应 base-devel、wayland、wayland-protocols、pkgconf）。

从仓库根只编译，不安装、不启动：

```sh
bash magnifier/tools/cursor-track/build.sh
```

确认需要更新安装副本时才运行：

```sh
bash magnifier/tools/cursor-track/build.sh install
```

清理构建产物不会删除协议源码，也不会替换或停止已安装的工具。不要把 protocols 目录当缓存删除。
