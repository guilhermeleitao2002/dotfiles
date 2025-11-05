# Stow installation
echo "\e[1;36mInstalling GNU stow\e[0m"
yay -Sy stow

# Wallpaper configuration
echo "\e[1;36m \n Installing hyprpaper\e[0m"
yay -Sy hyprpaper
stow hyprpaper
echo "\e[1;36m [+] hyprpaper stowed\e[0m"
stow backgrounds
echo "\e[1;36m [+] backgrounds stowed\e[0m"

# Terminal configuration
echo "\e[1;36m \n Configuring kitty terminal\e[0m"
stow kitty
echo "\e[1;36m [+] kitty stowed\e[0m"
./zsh_setup.sh # Run separate script

# Status bar configuration
echo "\e[1;36m \n Configuring waybar status bar\e[0m"
killall waybar
rm ~/.config/waybar/*
stow waybar
echo "\e[1;36m [+] waybar stowed\e[0m"

# GTK apps configuration
echo "\e[1;36m \n Installing GTK Apps\e[0m"
yay -Sy nwg-look
echo "\e[1;36mInstalling catppuccin themes\e[0m"
yay -Sy catppuccin-gtk-theme-mocha
echo "\e[1;36mChoose a theme:\e[0m"
nwg-look

# Application launcher configuration
echo "\e[1;36m \n Configuring wofi app launcher\e[0m"
stow wofi
echo "\e[1;36m [+] wofi stowed\e[0m"

# Hyprlock configuration
echo "\e[1;36m \n Configuring hyprlock lockscreen\e[0m"
sudo rm -rf ~/.config/hypr/hyprlock.conf
stow hyprlock
echo "\e[1;36m [+] hyprlock stowed\e[0m"
stow hyprmocha
echo "\e[1;36m [+] hyprmocha stowed\e[0m"

# Hyprland overall configuration
echo "\e[1;36m \n Configuring Hyprland general config\e[0m"
sudo rm ~/.config/hypr/hyprland.conf && cp hyprland.conf ~/.config/hypr/

# Apply all changes
reboot