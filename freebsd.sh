#!/bin/sh

if [ "$(id -u)" != "0" ]; then
    echo "Erreur : Ce script doit être exécuté en tant que root" 1>&2
    exit 1
fi

# --- Détection du type de machine ---
echo "Tentative de détection automatique du type de machine..."
if sysctl hw.model | grep -qi "VirtualBox"; then
    DETECTED_TYPE="3"
    DETECTED_NAME="VirtualBox"
elif sysctl hw.acpi.battery.info >/dev/null 2>&1; then
    DETECTED_TYPE="2"
    DETECTED_NAME="Laptop"
else
    DETECTED_TYPE="1"
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
    echo "Entrez le numéro correspondant (1-3) :"
    read INSTALL_TYPE
else
    INSTALL_TYPE="$DETECTED_TYPE"
fi

case "$INSTALL_TYPE" in
    1|2|3) ;;
    *) echo "Choix invalide. Sortie du script." ; exit 1 ;;
esac

echo "Détection de l'interface réseau active..."
NET_IF=$(ifconfig -u | grep -v lo0 | grep -B1 UP | head -n1 | cut -d: -f1)
if [ -z "$NET_IF" ]; then
    echo "Aucune interface réseau active détectée. Utilisation de 'em0' par défaut."
    NET_IF="em0"
else
    echo "Interface réseau détectée : $NET_IF"
fi



# --- Configuration de l'utilisateur ---
echo "Entrez le nom de l'utilisateur principal :"
read USERNAME
pw user add -n "$USERNAME" -c "$USERNAME" -m -G wheel
echo "Mot de passe pour $USERNAME :"
passwd "$USERNAME"

# Vérification que l'utilisateur existe
if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "Erreur : L'utilisateur $USERNAME n'a pas été créé correctement. Sortie du script."
    exit 1
fi

# --- Configuration de base du système ---
echo "Configuration automatique du fuseau horaire..."
tzsetup

echo "Entrez la locale souhaitée (ex. fr_FR.UTF-8, en_US.UTF-8) :"
read LOCALE
echo "LANG=$LOCALE" >> /etc/profile
echo "setenv LANG $LOCALE" >> /etc/csh.login

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

echo "Mise à jour complète du système..."
pkg update
pkg upgrade -y
freebsd-update fetch
freebsd-update install

# --- Installation des autres paquets ---
echo "Installation de Xorg, MATE et SDDM..."
pkg install -y xorg mate sddm

# Vérification que la session MATE est installée
if [ ! -f "/usr/local/share/xsessions/mate.desktop" ]; then
    echo "Erreur : Session MATE non détectée. Réinstallation..."
    pkg install -y mate
fi


echo "Installation et configuration de sudo..."
pkg install -y sudo

echo "Installation du pilote Nvidia..."
pkg install -y nvidia-driver nvidia-settings
sysrc kld_list+="nvidia nvidia-modeset"
echo 'nvidia_load="YES"' >> /boot/loader.conf

echo "Installation de Firefox..."
pkg install -y firefox-esr

echo "Installation de PulseAudio..."
pkg install -y pulseaudio

echo "Installation d'OpenVPN..."
pkg install -y openvpn

echo "Installation des outils de développement..."
pkg install -y code rust python3 gcc clang git gmake
echo "set path = (/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin /home/'$USERNAME'/.cargo/bin)" >> /home/$USERNAME/.shrc

echo "Installation des outils Rust supplémentaires..."
pkg install -y rust-analyzer
cargo install clippy rustfmt

echo "Installation et configuration de Bluetooth..."
pkg install -y bluez-firmware bluez-utils

echo "Installation de vulkan-tools..."
pkg install -y vulkan-tools

echo "Installation de htop et sysstat..."
pkg install -y htop sysstat

echo "Installation de maldet..."
pkg install -y maldet

echo "Installation de Docker..."
pkg install -y docker-freebsd

echo "Installation de iperf3..."
pkg install -y iperf3

echo "Installation de auditd..."
pkg install -y auditd

echo "Installation des composants pour imprimante/scanner HP Deskjet F2420..."
pkg install -y cups hplip sane-backends

echo "Installation de d'autres outils..."
pkg install -y webfonts qjackctl artwiz-fonts nerd-fonts sctd


# --- Configuration du système ---
echo "Configuration de PAM pour SDDM..."
cat << EOF > /etc/pam.d/sddm
auth        sufficient    pam_unix.so
auth        required      pam_deny.so
account     required      pam_unix.so
session     required      pam_permit.so
EOF

echo "Configuration des groupes pour $USERNAME..."
pw groupmod video -m $USERNAME
pw groupmod realtime -m $USERNAME
pw groupmod operator -m $USERNAME
pw groupmod wheel -m $USERNAME
pw groupmod network -m $USERNAME
pw groupmod cups -m $USERNAME

echo "Configuration de SDDM pour connexion automatique et clavier français..."
mkdir -p /usr/local/etc/sddm.conf.d
cat << EOF > /usr/local/etc/sddm.conf.d/sddm.conf
[Autologin]
User=$USERNAME
Session=mate.desktop

[General]
Numlock=on
X11Keyboard=fr
EOF

if [ "$INSTALL_TYPE" = "1" ] || [ "$INSTALL_TYPE" = "2" ]; then
    echo "Génération d'une configuration Xorg initiale..."
    X -configure
    mv ~/xorg.conf.new /etc/X11/xorg.conf
fi

echo "Forçage de la disposition du clavier en français pour Xorg..."
mkdir -p /etc/X11/xorg.conf.d
cat << EOF > /etc/X11/xorg.conf.d/10-keyboard.conf
Section "InputClass"
    Identifier "Keyboard0"
    MatchIsKeyboard "on"
    Option "XkbLayout" "fr"
EndSection
EOF

echo "%wheel ALL=(ALL) ALL" > /usr/local/etc/sudoers.d/wheel

echo "Configuration des services dans rc.conf..."
sysrc zfs_enable="YES" #Raid
sysrc kld_list+=linux linux64 #Module Linux
sysrc linux_enable="YES" #Kernel linux load
sysrc sshd_enable="YES"
sysrc ntpd_enable="YES"
sysrc dbus_enable="YES"
sysrc hald_enable="YES"
sysrc sddm_enable="YES"
sysrc powerd_enable="YES"
sysrc bluetooth_enable="YES"
sysrc hcsecd_enable="YES"
sysrc sdpd_enable="YES"
sysrc docker_enable="YES"
sysrc pulseaudio_enable="YES"
sysrc auditd_enable="YES"
sysrc cupsd_enable="YES"
sysrc saned_enable="YES"
sysrc update_motd="NO"
sysrc rc_startmsgs="NO"
sysrc ntpd_enable="YES"
sysrc ntpdate_enable="YES"
sysrc syslogd_flags="-ss"
sysrc dumpdev="NO"
sysrc clear_tmp_enable="YES"
sysrc sendmail_enable="NONE"
sysrc sendmail_msp_queue_enable="NO"
sysrc sendmail_outbound_enable="NO"
sysrc sendmail_submit_enable="NO"
sysrc microcode_update_enable="YES"

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

case "$INSTALL_TYPE" in
    2)
        echo "Configuration spécifique pour laptop..."
        pkg install -y xf86-input-synaptics webcamd
        sysrc webcamd_enable="YES"
        echo "synaptics_enable=\"YES\"" >> /etc/rc.conf
        ;;
    3)
        echo "Configuration spécifique pour VirtualBox guest..."
        pkg install -y virtualbox-ose-additions
        sysrc vboxguest_enable="YES"
        sysrc vboxservice_enable="YES"
        ;;
    1)
        echo "Aucune configuration supplémentaire pour PC."
        ;;
esac

if zpool list >/dev/null 2>&1; then
    echo "Configuration des snapshots ZFS..."
    pkg install -y zfstools
    echo "0 0 * * * root zfs snapshot tank/home@daily-$(date +%Y%m%d)" >> /etc/crontab
fi

# --- Optimisations et sécurité ---
echo "Optimisation du système pour performances et sécurité..."
kldload cpufreq
TOTAL_RAM=$(sysctl -n hw.physmem)
ZFS_ARC_MAX=$((TOTAL_RAM / 2 / 1024 / 1024 / 1024))G
cat << EOF >> /etc/sysctl.conf
net.inet.tcp.sendspace=65536
net.inet.tcp.recvspace=65536
net.inet.tcp.rfc1323=1
net.inet.tcp.delayed_ack=0
kern.maxfiles=65536
kern.maxfilesperproc=32768
kern.ipc.shmmax=536870912
vfs.zfs.arc_max=$ZFS_ARC_MAX
vfs.zfs.trim.enabled=1
security.bsd.see_other_uids=0
security.bsd.see_other_gids=0
hw.intel_microcode_update=1
EOF
sysctl -f /etc/sysctl.conf
echo 'sem_load="YES"' >> /boot/loader.conf

echo "Configuration du pare-feu PF avec l'interface $NET_IF..."
cat << EOF > /etc/pf.conf
ext_if="$NET_IF"
set block-policy drop
set skip on lo0
block in all
pass out all keep state
EOF
sysrc pf_enable="YES"
service pf start

echo "Configuration des mises à jour automatiques..."
echo "0 0 * * * root pkg upgrade -y" >> /etc/crontab

echo "Installation et configuration terminées avec succès !"
echo "Redémarrez le système avec 'reboot' pour appliquer tous les changements."
