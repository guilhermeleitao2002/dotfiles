# Stow installation
GREP_COLORS='mt=1;36' echo "Installing GNU stow"
yay -Sy stow

# Wallpaper configuration
GREP_COLORS='mt=1;36' echo "\n Configuring hyprpaperbackgrounds"
yay -Sy hyprpaper
stow hyprpaper
GREP_COLORS='mt=1;36' echo "hyprpaper stowed"
GREP_COLORS='mt=1;36' echo "backgrounds stowed"

# Terminal configuration
GREP_COLORS='mt=1;36' echo "\n Configuring kitty terminal"