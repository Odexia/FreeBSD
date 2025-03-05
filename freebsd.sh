#!/bin/sh

# Vérification des privilèges root
if [ "$(id -u)" != "0" ]; then
    echo "Erreur : Ce script doit être exécuté en tant que root" 1>&2
    exit 1
fi

# Demande du nom d'utilisateur principal
echo "Entrez le nom de l'utilisateur principal :"
read USERNAME

# Détection automatique du type d'installation
echo "Tentative de détection automatique du type de machine..."
if sysctl hw.model | grep -qi "VirtualBox"; then
    DETECTED_TYPE="3"  # VirtualBox
    DETECTED_NAME="VirtualBox"
elif sysctl hw.model | grep -qi "VMware"; then
    DETECTED_TYPE="4"  # VMware
    DETECTED_NAME="VMware"
elif sysctl hw.acpi.battery.info >/dev/null 2>&1; then
    DETECTED_TYPE="2"  # Laptop
    DETECTED_NAME="Laptop"
else
    DETECTED_TYPE="1"  # PC
    DETECTED_NAME="PC"
fi

echo "Machine détectée : $DETECTED_NAME (Type $DETECTED_TYPE)"
echo "Confirmez-vous ce choix ? (y/n)"
read CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Choisissez manuellement le type d'installation :"
    echo "1) PC"
    echo "2) Laptop"
    echo "3) VirtualBox"
    echo "4) VMware"
    echo "Entrez le numéro correspondant (1-4) :"
    read INSTALL_TYPE
else
    INSTALL_TYPE="$DETECTED_TYPE"
fi

# Validation du choix
case "$INSTALL_TYPE" in
    1|2|3|4) ;;
    *) echo "Choix invalide. Sortie du script." ; exit 1 ;;
esac

# Détection automatique de l'interface réseau active
echo "Détection de l'interface réseau active..."
NET_IF=$(ifconfig -u | grep -v lo0 | grep -B1 UP | head -n1 | cut -d: -f1)
if [ -z "$NET_IF" ]; then
    echo "Aucune interface réseau active détectée. Utilisation de 'em0' par défaut."
    NET_IF="em0"
else
    echo "Interface réseau détectée : $NET_IF"
fi

# Création de l'utilisateur principal avec privilèges sudo (groupe wheel)
pw user add -n "$USERNAME" -c "Main User" -m -G wheel
echo "Mot de passe pour $USERNAME :"
passwd "$USERNAME"

# Configuration du fuseau horaire
echo "Configuration automatique du fuseau horaire..."
tzsetup

# Configuration de la langue
echo "Entrez la locale souhaitée (ex. fr_FR.UTF-8, en_US.UTF-8) :"
read LOCALE
echo "LANG=$LOCALE" >> /etc/profile
echo "setenv LANG $LOCALE" >> /etc/csh.login

# Configuration des mises à jour pour utiliser la branche "quarterly"
echo "Configuration des mises à jour pour utiliser la branche quarterly..."
mkdir -p /usr/local/etc/pkg/repos
cat << EOF > /usr/local/etc/pkg/repos/FreeBSD.conf
FreeBSD: {
  url: "pkg+http://pkg.FreeBSD.org/\${ABI}/quarterly",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
EOF

# Mise à jour complète du système
echo "Mise à jour complète du système..."
pkg update
pkg upgrade -y
freebsd-update fetch
freebsd-update install

# Installation de l'environnement de bureau XFCE et SDDM
echo "Installation de XFCE et SDDM..."
pkg install -y xfce sddm nitrogen

# Configuration de SDDM pour connexion automatique
echo "Configuration de SDDM pour connexion automatique..."
mkdir -p /usr/local/etc/sddm.conf.d
cat << EOF > /usr/local/etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USERNAME
Session=xfce
EOF

# Configuration automatique de la résolution (PC ou Laptop)
if [ "$INSTALL_TYPE" = "1" ] || [ "$INSTALL_TYPE" = "2" ]; then
    echo "Génération d'une configuration Xorg initiale..."
    X -configure
    mv ~/xorg.conf.new /etc/X11/xorg.conf
fi

# Installation de Firefox
echo "Installation de Firefox..."
pkg install -y firefox

# Installation des outils de développement
echo "Installation des outils de développement..."
pkg install -y rust python3 gcc clang git neovim gmake

# Installation de VirtualBox (uniquement si non installé dans VirtualBox)
if [ "$INSTALL_TYPE" != "3" ]; then
    echo "Installation et configuration de VirtualBox..."
    pkg install -y virtualbox-ose
    kldload vboxdrv
    sysrc vboxnet_enable="YES"
fi

# Installation de Steam pour le gaming
echo "Installation de Steam..."
pkg install -y steam-utils

# Installation d'OpenVPN pour le VPN
echo "Installation d'OpenVPN..."
pkg install -y openvpn

# Installation et configuration de Bluetooth
echo "Installation et configuration de Bluetooth..."
pkg install -y bluez-firmware bluez-utils
sysrc bluetooth_enable="YES"
sysrc hcsecd_enable="YES"
sysrc sdpd_enable="YES"

# Installation de VSCode
echo "Installation de VSCode..."
pkg install -y code

# Installation des outils Rust supplémentaires
echo "Installation des outils Rust supplémentaires..."
pkg install -y rust-analyzer
cargo install clippy rustfmt

# Installation de sudo et configuration pour le groupe wheel
echo "Installation et configuration de sudo..."
pkg install -y sudo
echo "%wheel ALL=(ALL) ALL" > /usr/local/etc/sudoers.d/wheel

# Installation de vulkan-tools pour Vulkan
echo "Installation de vulkan-tools..."
pkg install -y vulkan-tools

# Installation d'outils de surveillance
echo "Installation de htop et sysstat pour la surveillance..."
pkg install -y htop sysstat

# Installation de maldet pour la sécurité
echo "Installation de maldet pour la détection de malwares..."
pkg install -y maldet

# Installation de docker pour le développement
echo "Installation de Docker..."
pkg install -y docker-freebsd
sysrc docker_enable="YES"

# Installation de iperf3 pour tester le réseau
echo "Installation de iperf3..."
pkg install -y iperf3

# Installation de pulseaudio pour l’audio
echo "Installation de PulseAudio..."
pkg install -y pulseaudio
sysrc pulseaudio_enable="YES"

# Installation de fish comme shell alternatif
echo "Installation de Fish..."
pkg install -y fish
chsh -s /usr/local/bin/fish "$USERNAME"

# Préconfiguration de Fish pour l'utilisateur
echo "Configuration de Fish pour $USERNAME..."
mkdir -p /home/"$USERNAME"/.config/fish
cat << EOF > /home/"$USERNAME"/.config/fish/config.fish
# Alias utiles
alias ls 'ls -lh'
alias update 'sudo pkg upgrade -y'
alias zfs-snap 'zfs snapshot tank/home@manual-$(date +%Y%m%d-%H%M%S)'

# Variables d'environnement
set -x PATH \$PATH /usr/local/bin
EOF
chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.config/fish/config.fish

# Préconfiguration de Nitrogen pour XFCE
echo "Configuration de Nitrogen pour XFCE..."
mkdir -p /home/"$USERNAME"/.config/nitrogen
cat << EOF > /home/"$USERNAME"/.config/nitrogen/nitrogen.cfg
[geometry]
posx=0
posy=0
sizex=640
sizey=480

[nitrogen]
view=icon
dirs=/usr/local/share/backgrounds/xfce;
EOF
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.config/nitrogen

# Installation de auditd pour l’audit
echo "Installation de auditd..."
pkg install -y auditd
sysrc auditd_enable="YES"

# Configuration des services dans rc.conf (base commune)
echo "Configuration des services dans rc.conf..."
sysrc sshd_enable="YES"           # SSH activé mais bloqué depuis l'extérieur
sysrc ntpd_enable="YES"           # Synchronisation de l'heure
sysrc dbus_enable="YES"           # Bus système pour XFCE
sysrc hald_enable="YES"           # Détection matériel pour XFCE
sysrc sddm_enable="YES"           # Gestionnaire de connexion
sysrc powerd_enable="YES"         # Gestion dynamique CPU

# Optimisation du système pour performances et sécurité
echo "Optimisation du système pour performances et sécurité..."
kldload cpufreq
TOTAL_RAM=$(sysctl -n hw.physmem)
ZFS_ARC_MAX=$((TOTAL_RAM / 2 / 1024 / 1024 / 1024))G  # 50% en Go
cat << EOF >> /etc/sysctl.conf
# Réseau
net.inet.tcp.sendspace=65536      # Buffer TCP envoi
net.inet.tcp.recvspace=65536      # Buffer TCP réception
net.inet.tcp.rfc1323=1            # Extensions TCP
net.inet.tcp.delayed_ack=0        # Désactivation ACK retardés

# Système
kern.maxfiles=65536               # Limite fichiers système
kern.maxfilesperproc=32768        # Limite fichiers par processus
vfs.zfs.arc_max=$ZFS_ARC_MAX      # Cache ZFS ajusté automatiquement
vfs.zfs.trim.enabled=1            # TRIM pour SSD

# Sécurité
security.bsd.see_other_uids=0     # Isolation utilisateurs
security.bsd.see_other_gids=0     # Isolation groupes
hw.intel_microcode_update=1       # Mise à jour microcode Intel
EOF
sysctl -f /etc/sysctl.conf

# Installation du pilote Nvidia
echo "Installation du pilote Nvidia..."
pkg install -y nvidia-driver
sysrc kld_list+="nvidia nvidia-modeset"

# Configuration du pare-feu PF avec l'interface détectée
echo "Configuration du pare-feu PF avec l'interface $NET_IF..."
cat << EOF > /etc/pf.conf
# Interface réseau détectée automatiquement
ext_if="$NET_IF"

# Options
set block-policy drop
set skip on lo0

# Règles : bloquer tout entrant, autoriser tout sortant
block in all
pass out all keep state
EOF
sysrc pf_enable="YES"
service pf start

# Mise à jour automatique des paquets (chaque semaine)
echo "Configuration des mises à jour automatiques..."
echo "0 0 * * 0 root pkg upgrade -y" >> /etc/crontab

# Configuration Wi-Fi pour laptops
if [ "$INSTALL_TYPE" = "2" ]; then
    echo "Détection des interfaces Wi-Fi..."
    WIFI_IF=$(ifconfig | grep -B1 "IEEE 802.11" | head -n1 | cut -d: -f1)
    if [ -n "$WIFI_IF" ]; then
        echo "Interface Wi-Fi détectée : $WIFI_IF"
        echo "Entrez le SSID du réseau Wi-Fi :"
        read SSID
        echo "Entrez la clé WPA (mot de passe) :"
        read -s WPA_KEY
        cat << EOF > /etc/wpa_supplicant.conf
network={
    ssid="$SSID"
    psk="$WPA_KEY"
}
EOF
        sysrc "wlans_$WIFI_IF=wlan0"
        sysrc "ifconfig_wlan0=inet WPA dhcp"
        service netif restart
        echo "Wi-Fi configuré pour $WIFI_IF."
    else
        echo "Aucune interface Wi-Fi détectée."
    fi
fi

# Configuration spécifique selon le type d'installation
case "$INSTALL_TYPE" in
    2) # Laptop
        echo "Configuration spécifique pour laptop (trackpad, caméra, gestion énergie)..."
        pkg install -y xf86-input-synaptics webcamd xfce4-power-manager
        sysrc webcamd_enable="YES"
        echo "synaptics_enable=\"YES\"" >> /etc/rc.conf
        ;;
    3) # VirtualBox
        echo "Configuration spécifique pour VirtualBox (guest additions)..."
        pkg install -y virtualbox-ose-additions
        sysrc vboxguest_enable="YES"
        sysrc vboxservice_enable="YES"
        ;;
    4) # VMware
        echo "Configuration spécifique pour VMware (VMware Tools)..."
        pkg install -y open-vm-tools
        sysrc vmware_guest_vmblock_enable="YES"
        sysrc vmware_guest_vmmemctl_enable="YES"
        sysrc vmware_guest_vmxnet_enable="YES"
        ;;
    1) # PC
        echo "Aucune configuration supplémentaire pour PC."
        ;;
esac

# Ajout de snapshots ZFS (si ZFS est utilisé)
if zpool list >/dev/null 2>&1; then
    echo "Configuration des snapshots ZFS..."
    pkg install -y zfstools
    echo "0 0 * * * root zfs snapshot tank/home@daily-$(date +%Y%m%d)" >> /etc/crontab
fi

# Fin de l'installation
echo "Installation et configuration terminées avec succès !"
echo "Redémarrez le système avec 'reboot' pour appliquer tous les changements."
