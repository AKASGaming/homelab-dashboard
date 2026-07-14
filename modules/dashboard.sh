#!/usr/bin/env bash
# =============================================================================
# dashboard.sh - Main dashboard loop
# =============================================================================

[[ -n "${_DASHBOARD_SH_LOADED:-}" ]] && return 0
_DASHBOARD_SH_LOADED=1

dashboard_main_loop() {
    local choice items

    read -ra items <<< "$(dashboard_get_menu_items)"
    ui_set_menu_items "${items[@]}"
    ui_main_snapshot_load

    while (( UI_RUNNING )); do
        ui_draw_main_screen

        ui_tty_restore
        printf '\n'
        ui_color "${COLOR_LABEL}" "Choose an option: "
        ui_reset_attrs
        read -r choice
        ui_tty_init

        case "${choice}" in
            1) dashboard_open_module "${UI_MENU_ITEMS[0]}"; ui_main_snapshot_load ;;
            2) dashboard_open_module "${UI_MENU_ITEMS[1]}"; ui_main_snapshot_load ;;
            3) dashboard_open_module "${UI_MENU_ITEMS[2]}"; ui_main_snapshot_load ;;
            4) dashboard_open_module "${UI_MENU_ITEMS[3]}"; ui_main_snapshot_load ;;
            5) dashboard_open_module "${UI_MENU_ITEMS[4]}"; ui_main_snapshot_load ;;
            6) dashboard_open_module "${UI_MENU_ITEMS[5]}"; ui_main_snapshot_load ;;
            7) dashboard_open_module "${UI_MENU_ITEMS[6]}"; ui_main_snapshot_load ;;
            8) dashboard_open_module "${UI_MENU_ITEMS[7]}"; ui_main_snapshot_load ;;
            q|Q) break ;;
            s|S) screensaver_run ;;
            r|R) ui_main_snapshot_load ;;
            "")
                continue
                ;;
            *)
                ui_message "Menu" "Invalid choice: ${choice}"
                ;;
        esac
    done
}
