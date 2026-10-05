if status is-interactive
    set -g fish_greeting
    set -gx EDITOR nvim
    set -gx VISUAL nvim
    fish_add_path "$HOME/.local/bin"

    oh-my-posh init fish --config "$HOME/.config/ohmyposh/arch-lab.omp.json" | source

    if set -q KITTY_WINDOW_ID
        fastfetch --config "$HOME/.config/fastfetch/arch-lab.jsonc"
    end
end
