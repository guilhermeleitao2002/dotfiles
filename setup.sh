# Stow installation
GREP_COLORS='mt=1;36' echo "Installing GNU stow"
yay -Sy stow

# Wallpaper configuration
GREP_COLORS='mt=1;36' echo "\n Installing hyprpaper"
yay -Sy hyprpaper
stow hyprpaper
GREP_COLORS='mt=1;36' echo "[+] hyprpaper stowed"
stow backgrounds
GREP_COLORS='mt=1;36' echo "[+] backgrounds stowed"

# Terminal configuration
GREP_COLORS='mt=1;36' echo "\n Configuring kitty terminal"
stow kitty
GREP_COLORS='mt=1;36' echo "[+] kitty stowed"
GREP_COLORS='mt=1;36' echo "Installing zsh"
sudo pacman -Sy zsh
zsh
chsh -s `which zsh`
sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Status bar configuration
GREP_COLORS='mt=1;36' echo "\n Configuring waybar status bar"
killall waybar
rm ~/.config/waybar/*
stow waybar
GREP_COLORS='mt=1;36' echo "[+] waybar stowed"

# GTK apps configuration
GREP_COLORS='mt=1;36' echo "\n Installing GTK Apps"
yay -Sy nwg-look
GREP_COLORS='mt=1;36' echo "Installing catppuccin themes"
yay -Sy catppuccin-gtk-theme-mocha
GREP_COLORS='mt=1;36' echo "Choose a theme:"
nwg-look

# Application launcher configuration
GREP_COLORS='mt=1;36' echo "\n Configuring wofi app launcher"
stow wofi
GREP_COLORS='mt=1;36' echo "[+] wofi stowed"

# Hyprlock configuration
GREP_COLORS='mt=1;36' echo "\n Configuring hyprlock lockscreen"
sudo rm -rf ~/.config/hypr/hyprlock.conf
stow hyprlock
GREP_COLORS='mt=1;36' echo "[+] hyprlock stowed"
stow hyprmocha
GREP_COLORS='mt=1;36' echo "[+] hyprmocha stowed"
