/* cursor-track.c — 全屏透明覆盖层，把指针位置写到文件，给 pang/magnifier 插件当光标传感器。
 *
 * 心跳：第 2 个参数给一个"心跳文件"，调用方（插件）每秒更新它一次；
 *       心跳超过 2.5 秒没更新（或文件消失）→ 自己退出。这样即便插件/面板崩溃、
 *       onClose 里的清理没跑到，也不会留下一个把桌面点死的隐形层。
 *
 * 为什么需要它：niri 的 IPC 没有光标查询；xwayland-satellite 的 X 端坐标在指针位于
 * Wayland 原生表面上时是陈旧值（实测卡死在同一个值）。唯一可靠办法 = 自己铺一层
 * 全屏 layer surface，直接从 wl_pointer 事件读坐标。
 *
 * 用法：cursor-track <输出文件> [心跳文件] [--no-exit-on-click] [--verbose]
 * 记录（固定 128 字节，首行为一条完整记录）：
 *   seq=<N> type=<enter|move|leave|click|scroll> x=<X> y=<Y>
 * 代价：surface 在 overlay 层、输入区=全屏 → 打开期间会挡住桌面点击（这是"跟随鼠标"
 *       的必要代价）；点击默认退出（由调用方决定是否 --no-exit-on-click）。
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
/* Independent of pointer activity: a busy event stream must never keep a stale input shield alive. */
static int tracker_should_exit(const char *output, const char *heartbeat,
                               time_t now, time_t started) {
  struct stat st;
  if (difftime(now, started) > 2 * 3600) return 1;
  if (output && *output && (stat(output, &st) != 0 || !S_ISREG(st.st_mode))) return 1;
  if (heartbeat && *heartbeat) {
    if (stat(heartbeat, &st) != 0 || !S_ISREG(st.st_mode)) return 1;
    if (difftime(now, st.st_mtime) > 2.5) return 1;
  }
  return 0;
}

#ifndef CURSOR_TRACK_HEARTBEAT_TEST
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1.h"

static struct wl_display *dpy;
static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct wl_pointer *ptr;
static struct zwlr_layer_shell_v1 *ls;
static struct wl_surface *surf;
static struct zwlr_layer_surface_v1 *lsurf;
static struct wl_buffer *buf;
static void *buf_data;
static size_t buf_size;
static int outfd = -1;
static unsigned long long seqno = 0;
static int exit_on_click = 1;
static int want_exit = 0;
static int last_x = -1, last_y = -1;
static int verbose = 0;
static char out_path[512] = {0};
static char hb_path[512] = {0};

static void rec(const char *type, int x, int y) {
  seqno++;
  if (verbose) fprintf(stderr, "%llu %s %d %d\n", seqno, type, x, y);
  if (outfd < 0) return;
  char line[128];
  int n = snprintf(line, sizeof line, "seq=%llu type=%s x=%d y=%d", seqno, type, x, y);
  if (n < 0) return;
  if (n > (int)sizeof line - 1) n = sizeof line - 1;
  memset(line + n, ' ', sizeof line - n);
  line[sizeof line - 1] = '\n';
  ssize_t w = pwrite(outfd, line, sizeof line, 0);
  (void)w;
}

static void ptr_enter(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t sx, wl_fixed_t sy) {
  (void)d; (void)p; (void)serial; (void)s;
  last_x = wl_fixed_to_int(sx); last_y = wl_fixed_to_int(sy);
  rec("enter", last_x, last_y);
}
static void ptr_leave(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s) {
  (void)d; (void)p; (void)serial; (void)s;
  rec("leave", last_x, last_y);
}
static void ptr_motion(void *d, struct wl_pointer *p, uint32_t time, wl_fixed_t sx, wl_fixed_t sy) {
  (void)d; (void)p; (void)time;
  last_x = wl_fixed_to_int(sx); last_y = wl_fixed_to_int(sy);
  rec("move", last_x, last_y);
}
static void ptr_button(void *d, struct wl_pointer *p, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
  (void)d; (void)p; (void)serial; (void)time;
  if (state != WL_POINTER_BUTTON_STATE_PRESSED) return;
  rec("click", last_x, last_y);
  if (exit_on_click && (button == BTN_LEFT || button == BTN_RIGHT)) want_exit = 1;
}
static void ptr_axis(void *d, struct wl_pointer *p, uint32_t time, uint32_t axis, wl_fixed_t value) {
  (void)d; (void)p; (void)time; (void)value;
  rec(axis == WL_POINTER_AXIS_VERTICAL_SCROLL ? "scroll" : "scroll-h", last_x, last_y);
}
static void ptr_noop_frame(void *d, struct wl_pointer *p) { (void)d; (void)p; }
static void ptr_noop_axis_source(void *d, struct wl_pointer *p, uint32_t s) { (void)d; (void)p; (void)s; }
static void ptr_noop_axis_stop(void *d, struct wl_pointer *p, uint32_t t, uint32_t a) { (void)d; (void)p; (void)t; (void)a; }
static void ptr_noop_axis_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v) { (void)d; (void)p; (void)a; (void)v; }
static const struct wl_pointer_listener ptr_listener = {
  .enter = ptr_enter, .leave = ptr_leave, .motion = ptr_motion,
  .button = ptr_button, .axis = ptr_axis,
  .frame = ptr_noop_frame,
  .axis_source = ptr_noop_axis_source,
  .axis_stop = ptr_noop_axis_stop,
  .axis_discrete = ptr_noop_axis_discrete,
};

static void seat_caps(void *d, struct wl_seat *s, uint32_t caps) {
  (void)d;
  if ((caps & WL_SEAT_CAPABILITY_POINTER) && !ptr) {
    ptr = wl_seat_get_pointer(s);
    wl_pointer_add_listener(ptr, &ptr_listener, NULL);
  } else if (!(caps & WL_SEAT_CAPABILITY_POINTER) && ptr) {
    wl_pointer_destroy(ptr);
    ptr = NULL;
  }
}
static void seat_name(void *d, struct wl_seat *s, const char *name) { (void)d; (void)s; (void)name; }
static const struct wl_seat_listener seat_listener = { .capabilities = seat_caps, .name = seat_name };

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver) {
  (void)d; (void)ver;
  if (!strcmp(iface, wl_compositor_interface.name)) comp = wl_registry_bind(r, name, &wl_compositor_interface, 4);
  else if (!strcmp(iface, wl_shm_interface.name)) shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
  else if (!strcmp(iface, wl_seat_interface.name)) {
    seat = wl_registry_bind(r, name, &wl_seat_interface, 5);
    wl_seat_add_listener(seat, &seat_listener, NULL);
  } else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name)) {
    ls = wl_registry_bind(r, name, &zwlr_layer_shell_v1_interface, 1);
  }
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) { (void)d; (void)r; (void)name; }
static const struct wl_registry_listener reg_listener = { .global = reg_global, .global_remove = reg_remove };

static int make_buffer(int w, int h) {
  int stride = w * 4;
  size_t size = (size_t)stride * (size_t)h;
  int fd = memfd_create("cursor-track", MFD_CLOEXEC);
  if (fd < 0) return -1;
  if (ftruncate(fd, (off_t)size) < 0) { close(fd); return -1; }
  void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (data == MAP_FAILED) { close(fd); return -1; }
  memset(data, 0, size);
  struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)size);
  buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
  wl_shm_pool_destroy(pool);
  close(fd);
  buf_data = data;
  buf_size = size;
  return 0;
}

static void ls_configure(void *d, struct zwlr_layer_surface_v1 *l, uint32_t serial, uint32_t w, uint32_t h) {
  (void)d;
  if (verbose) fprintf(stderr, "configure serial=%u %ux%u\n", serial, w, h);
  /* ack 必须在带 buffer 的 commit 之前被服务端处理：ack → 冲刷一轮 → 再 attach */
  zwlr_layer_surface_v1_ack_configure(l, serial);
  if (w > 0 && h > 0) {
    if (!buf || (size_t)w * (size_t)h * 4 != buf_size) {
      if (buf) { wl_buffer_destroy(buf); buf = NULL; }
      if (buf_data) { munmap(buf_data, buf_size); buf_data = NULL; }
      if (make_buffer((int)w, (int)h) < 0) { fprintf(stderr, "cursor-track: 缓冲区创建失败\n"); want_exit = 1; }
    }
    if (buf) {
      wl_surface_attach(surf, buf, 0, 0);
      wl_surface_damage_buffer(surf, 0, 0, (int32_t)w, (int32_t)h);
    }
  }
  wl_surface_commit(surf);
}
static void ls_closed(void *d, struct zwlr_layer_surface_v1 *l) { (void)d; (void)l; want_exit = 1; }
static const struct zwlr_layer_surface_v1_listener ls_listener = { .configure = ls_configure, .closed = ls_closed };

int main(int argc, char **argv) {
  const char *path = NULL;
  const char *hb = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--no-exit-on-click")) exit_on_click = 0;
    else if (!strcmp(argv[i], "--verbose")) verbose = 1;
    else if (!path) path = argv[i];
    else hb = argv[i];
  }
  time_t t0 = time(NULL);
  if (!path) { fprintf(stderr, "usage: cursor-track <output> [heartbeat]\n"); return 64; }
  if (hb) snprintf(hb_path, sizeof hb_path, "%s", hb);
  /* The panel may have closed while the detached startup command was queued. */
  if (tracker_should_exit(NULL, hb_path, t0, t0)) return 0;
  if (path) {
    snprintf(out_path, sizeof out_path, "%s", path);
    outfd = open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (outfd < 0) { perror("cursor-track: output"); return 2; }
    if (outfd >= 0) {
      char init[128];
      memset(init, ' ', sizeof init);
      init[127] = '\n';
      ssize_t w = pwrite(outfd, init, sizeof init, 0);
      (void)w;
    }
  }
  dpy = wl_display_connect(NULL);
  if (!dpy) { fprintf(stderr, "cursor-track: 无法连接 Wayland（检查 WAYLAND_DISPLAY）\n"); return 2; }
  struct wl_registry *reg = wl_display_get_registry(dpy);
  wl_registry_add_listener(reg, &reg_listener, NULL);
  wl_display_roundtrip(dpy);
  if (!comp || !shm || !ls) { fprintf(stderr, "cursor-track: 缺少 wl_compositor / wl_shm / wlr_layer_shell\n"); return 3; }
  if (!seat) fprintf(stderr, "cursor-track: 没有 seat（收不到指针事件）\n");
  surf = wl_compositor_create_surface(comp);
  lsurf = zwlr_layer_shell_v1_get_layer_surface(ls, surf, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "cursor-track");
  zwlr_layer_surface_v1_add_listener(lsurf, &ls_listener, NULL);
  zwlr_layer_surface_v1_set_anchor(lsurf,
      ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
      ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
  zwlr_layer_surface_v1_set_exclusive_zone(lsurf, 0);
  zwlr_layer_surface_v1_set_keyboard_interactivity(lsurf, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
  zwlr_layer_surface_v1_set_size(lsurf, 0, 0);
  /* 首次 commit 不带 buffer：必须先拿到 configure 并 ack 之后才能 attach */
  wl_surface_commit(surf);
  /* Check leases on every event-loop turn, not just when the mouse is idle.
     A 100ms poll bounds normal close latency; click records remain available to the panel. */
  time_t last_alive = t0;
  while (!want_exit) {
    if (tracker_should_exit(out_path, hb_path, time(NULL), t0)) break;
    if (wl_display_dispatch_pending(dpy) < 0 || want_exit) break;
    wl_display_flush(dpy);
    struct pollfd pfd = { .fd = wl_display_get_fd(dpy), .events = POLLIN };
    int pr = poll(&pfd, 1, 100);
    if (pr < 0) { if (errno == EINTR) continue; break; }
    if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) break;
    if (pr > 0 && (pfd.revents & POLLIN)) {
      if (wl_display_dispatch(dpy) < 0) break;
    }
    time_t now = time(NULL);
    if (tracker_should_exit(out_path, hb_path, now, t0)) break;
    if (difftime(now, last_alive) >= 2) {
      rec("alive", last_x, last_y);
      last_alive = now;
    }
  }
  if (outfd >= 0) close(outfd);
  wl_display_disconnect(dpy);
  return 0;
}
#endif /* CURSOR_TRACK_HEARTBEAT_TEST */
