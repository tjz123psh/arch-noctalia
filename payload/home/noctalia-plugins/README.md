# noctalia-plugins

Noctalia 的个人插件仓库，在宿主中注册为 path 源 `pang-dev`。宿主直接读取本目录，不需要另建运行副本。

## 从哪里看

| 目录／说明 | 用途 |
| --- | --- |
| [潮汐侧栏](<tide-sidebar/README.md>) | 原生窄标签侧栏：便签、计算器、自由倒计时、热点和窗口管理。 |
| [放大镜](<magnifier/>) | 放大镜面板与清单。 |
| [光标工具构建说明](<magnifier/tools/cursor-track/README.md>) | 本地工具源码、协议与构建产物的分工。 |

## 目录约定

- 每个插件各自保留入口和清单；不为整理目录拆改已经工作的运行逻辑。
- 测试只放可重复运行的检查，不放真实便签或一次性复现文件。
- [协议源码目录](<magnifier/tools/cursor-track/protocols/>) 随仓库保留；光标工具的 `build/` 只放可重建产物，可以清空。
- 既有便签仍在原先指定的目录（`~/Documents/notes`），不自动迁移。潮汐侧栏使用 Noctalia 管理的独立私有目录，见[侧栏保存位置说明](<tide-sidebar/README.md>)（“数据没有迁移”一节）；运行数据不混进源码目录。
- 修复前快照统一归到本地备份目录；不使用 Git 清理命令删除未提交的功能文件。

## 常用命令

```sh
# 打开潮汐侧栏；指定 timer / notes 等可直达页面
bash tide-sidebar/open.sh

# 侧栏的完整离线检查，不切热点、不操作真实窗口
python3 -B tide-sidebar/tests/run_all.py

# 只编译光标工具，不安装、不启动
bash magnifier/tools/cursor-track/build.sh
```

需要更新已安装光标工具时，再按其构建说明使用 install 参数。正在运行的放大镜使用[已安装副本](</home/pang/bin/cursor-track>)；普通源码整理不替换该文件。

## 修改如何生效

面板入口改变会触发相应插件热重载。仅在更新未生效时手动重新启用：

```sh
noctalia msg plugins disable pang/magnifier && noctalia msg plugins enable pang/magnifier
```

外部部署工程维护的是独立快照，本目录的整理不会自动同步其副本。导出光标工具时请同时带上协议源码，不能只复制 C 文件和构建脚本。
