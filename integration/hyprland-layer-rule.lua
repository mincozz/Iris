hl.layer_rule({
    name         = "assistant-glass",
    match        = { namespace = "^quickshell-assistant$" },
    no_anim      = true,
    blur         = true,
    ignore_alpha = 0.1,
})
