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
        if (( UI_RESIZE_PENDING )); then
            ui_main_snapshot_load
        fi
        ui_draw_main_screen

        ui_tty_restore
        printf '\n'
        ui_color "${COLOR_LABEL}" "Choose an option: "
        ui_reset_attrs
        read -r choice
        ui_tty_init

        case "${choice}" in
            q|Q) break ;;
            s|S) screensaver_run ;;
            r|R) ui_main_snapshot_load ;;
            "")
                continue
                ;;
            *[!0-9]*)
                ui_message "Menu" "Invalid choice: ${choice}"
                ;;
            *)
                if (( choice >= 1 && choice <= ${#UI_MENU_ITEMS[@]} )); then
                    dashboard_open_module "${UI_MENU_ITEMS[choice-1]}"
                    ui_main_snapshot_load
                else
                    ui_message "Menu" "Invalid choice: ${choice}"
                fi
                ;;
        esac
    done
}
