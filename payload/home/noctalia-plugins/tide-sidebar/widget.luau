--!nonstrict
function update()
  local snapshot=noctalia.state.get("timer_snapshot")
  local running=snapshot and snapshot.timer and snapshot.timer.status=="running"
  barWidget.setGlyph(running and "hourglass" or "layout-sidebar-left-expand")
  barWidget.setText("侧栏")
  barWidget.setTooltip("侧边栏 · Super+Shift+W")
end
function onClick() noctalia.state.set("command",{action="frontend-toggle"}) end
noctalia.state.watch("timer_snapshot",function() update() end)
update()
