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
