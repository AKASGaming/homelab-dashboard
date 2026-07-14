#!/usr/bin/env bash
# =============================================================================
# dashboard.sh - Main dashboard loop
# =============================================================================

[[ -n "${_DASHBOARD_SH_LOADED:-}" ]] && return 0
_DASHBOARD_SH_LOADED=1

# =============================================================================
# dashboard_main_loop - main menu input loop
# =============================================================================

dashboard_main_loop() {
    local items action

    read -ra items <<< "$(dashboard_get_menu_items)"
    ui_set_menu_items "${items[@]}"

    ui_main_snapshot_load
    ui_draw_main_screen

    while (( UI_RUNNING )); do
        if ! ui_read_key; then
            continue
        fi

        action="$(ui_main_process_key)"

        case "${action}" in
            nav)
                ui_draw_main_screen
                ;;
            open)
                dashboard_open_module "${UI_MENU_ITEMS[$UI_MENU_INDEX]}"
                ui_main_snapshot_load
                ui_draw_main_screen
                ;;
            quit)
                break
                ;;
            refresh)
                ui_main_snapshot_load
                ui_draw_main_screen
                ;;
            screensaver)
                screensaver_run
                ui_draw_main_screen
                ;;
        esac
    done
}
