# Package installations
echo "\e[1;36m Installing zsh and other useful packages \e[0m"
sudo apt update && sudo apt upgrade -y
sudo apt install zsh neofetch git -y

# Zsh configuration
echo "\e[1;36m Setting up zsh \e[0m"
zsh
chsh -s `which zsh`
sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
cp .zshrc ~
source ~/.zshrc
