--!nonstrict
shortcut.setLabel("侧边栏")
shortcut.setIcon("layout-sidebar-left-expand")
shortcut.setActive(false)
shortcut.setEnabled(true)
function onClick() noctalia.togglePanel("pang/tide-sidebar:side-panel") end
