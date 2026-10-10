#define CURSOR_TRACK_HEARTBEAT_TEST
#include "../tools/cursor-track/cursor-track.c"
#include <assert.h>

static void touch_at(const char *path, time_t t) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  assert(fd >= 0); assert(write(fd, "1", 1) == 1); assert(close(fd) == 0);
  struct timespec times[2] = { { .tv_sec = t }, { .tv_sec = t } };
  assert(utimensat(AT_FDCWD, path, times, 0) == 0);
}

int main(void) {
  char dir[] = "/tmp/desktop-polish-lease-XXXXXX";
  assert(mkdtemp(dir) != NULL);
  assert(strncmp(dir, "/tmp/desktop-polish-lease-", 26) == 0);
  char output[256], heartbeat[256];
  assert(snprintf(output, sizeof output, "%s/cursor.pos", dir) > 0);
  assert(snprintf(heartbeat, sizeof heartbeat, "%s/heartbeat.txt", dir) > 0);
  const time_t now = 1700000100;
  touch_at(output, now); touch_at(heartbeat, now);
  assert(tracker_should_exit(output, heartbeat, now, now - 10) == 0);
  assert(tracker_should_exit(output, heartbeat, now + 2, now - 10) == 0);
  assert(tracker_should_exit(output, heartbeat, now + 3, now - 10) == 1);
  assert(tracker_should_exit(output, heartbeat, now, now - 7201) == 1);
  assert(tracker_should_exit(output, NULL, now, now - 10) == 0);
  assert(unlink(heartbeat) == 0);
  /* Even repeated busy-event turns see a removed lease immediately. */
  for (int i = 0; i < 1000; i++)
    assert(tracker_should_exit(output, heartbeat, now, now - 10) == 1);
  assert(tracker_should_exit(NULL, heartbeat, now, now) == 1);
  touch_at(heartbeat, now + 20);
  assert(tracker_should_exit(output, heartbeat, now, now - 10) == 0);
  assert(unlink(output) == 0);
  assert(tracker_should_exit(output, heartbeat, now, now - 10) == 1);
  touch_at(output, now);
  assert(unlink(heartbeat) == 0); assert(mkdir(heartbeat, 0700) == 0);
  assert(tracker_should_exit(output, heartbeat, now, now - 10) == 1);
  assert(rmdir(heartbeat) == 0);
  assert(unlink(output) == 0); assert(rmdir(dir) == 0);
  puts("PASS: tracker lease removal, busy-event checks, startup guard, expiry and lifetime (no Wayland connection)");
  return 0;
}
