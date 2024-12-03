#!/bin/bash

# Script Checks system requirements
# - Running Kali
# - Minimum of 4 GB of RAM
# - Minimum of 40 GB disk space available
# - Internet connectivity

USER_HOME_BASE="/home/${SUDO_USER}"
BHB_TOOLS_FOLDER="/home/${SUDO_USER}/tools"

BHB_INSTALL_LOG="/var/log/lab-install.log"

check_prerequisites() {
    # Ensure the script is run as root
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: Please run with sudo permissions."
        exit 1
    fi

    # Ensure log file exists
    if [[ ! -f "${BHB_INSTALL_LOG}" ]]; then
        touch "${BHB_INSTALL_LOG}"
        chown "${SUDO_USER}:${SUDO_USER}" "${BHB_INSTALL_LOG}"
    fi

    # Ensure system is Kali Linux
    if ! grep -q "ID=kali" /etc/os-release; then
        echo "Error: Operating system does not appear to be Kali."
        exit 1
    fi

    # Check internet connectivity
    if ! ping -c 1 -W 5 "8.8.8.8" &>/dev/null; then
        echo "Error: No internet connectivity."
        exit 1
    fi

    # Check RAM requirement
    local total_ram
    total_ram=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    if [[ "${total_ram}" -lt 4194304 ]]; then
        echo "Warning: System has less than 4 GB of RAM."
        read -p "Do you want to continue? [y/n] " -n 1 -r
        echo
        if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
            echo "Exiting..."
            exit
        fi
    fi

    # Check disk space requirement
    local free
    free=$(df -k --output=avail / | tail -n1)
    if [[ "${free}" -lt 41943040 ]]; then
        echo "Warning: System has less than 40 GB free disk space."
        read -p "Do you want to continue? [y/n] " -n 1 -r
        echo
        if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
            echo "Exiting..."
            exit
        fi
    fi

    # Create tools folder
    if [[ ! -d "${BHB_TOOLS_FOLDER}" ]]; then
        mkdir -p "${BHB_TOOLS_FOLDER}"
        chown "${SUDO_USER}:${SUDO_USER}" "${BHB_TOOLS_FOLDER}"
    fi
}

install_docker() {
    # Add Docker's official repository and install Docker
    if ! command -v docker &>/dev/null; then
        echo "Installing Docker..."
        apt update -y
        apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian kali-rolling stable" | sudo tee /etc/apt/sources.list.d/docker.list
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io
        systemctl enable --now docker
        usermod -aG docker "${SUDO_USER}"
    else
        echo "Docker is already installed."
    fi
}

deploy_containers() {
    echo "Deploying containers..."
    sudo make deploy
}

install_tools() {
    echo "Installing tools..."
    install_whatweb
    install_rustscan
    install_nuclei
    install_linux_exploit_suggester_2
    install_gitjacker
    install_linenum
    install_dirsearch
    install_sysutilities
    install_unixprivesccheck
}

install_whatweb() {
    apt install -y whatweb
}

install_rustscan() {
    docker pull rustscan/rustscan:2.1.1
    if ! grep -q "alias rustscan=" "${USER_HOME_BASE}/.bashrc"; then
        echo "alias rustscan='docker run --rm --network host rustscan/rustscan:2.1.1'" >>"${USER_HOME_BASE}/.bashrc"
    fi
}

install_nuclei() {
    apt install -y nuclei
}

install_linux_exploit_suggester_2() {
    git clone https://github.com/jondonas/linux-exploit-suggester-2.git "${BHB_TOOLS_FOLDER}/linux-exploit-suggester-2"
}

install_gitjacker() {
    curl -fsSL https://raw.githubusercontent.com/liamg/gitjacker/master/scripts/install.sh | bash
    mv /usr/local/bin/gitjacker "${BHB_TOOLS_FOLDER}/"
}

install_linenum() {
    wget -q https://raw.githubusercontent.com/rebootuser/LinEnum/master/LinEnum.sh -O "${BHB_TOOLS_FOLDER}/LinEnum.sh"
    chmod +x "${BHB_TOOLS_FOLDER}/LinEnum.sh"
}

install_dirsearch() {
    apt install -y dirsearch
}

install_sysutilities() {
    apt install -y jq ncat sshpass
    pip3 install pwncat-cs
}

install_unixprivesccheck() {
    apt install -y unix-privesc-check
    cp /usr/bin/unix-privesc-check "${BHB_TOOLS_FOLDER}/"
}

echo "Starting installation process..."

check_prerequisites

echo "[1/3] Installing Docker..."
install_docker &>>"${BHB_INSTALL_LOG}"

echo "[2/3] Deploying containers..."
deploy_containers

echo "[3/3] Installing additional tools..."
install_tools &>>"${BHB_INSTALL_LOG}"

chown -R "${SUDO_USER}:${SUDO_USER}" "${BHB_TOOLS_FOLDER}"

echo "Installation complete. Log out and back in for changes to take effect."
