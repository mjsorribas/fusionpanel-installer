#!/usr/bin/env bash

# Official FusionPanel Automated Installation Script
# =============================================
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Supported Operating Systems: CentOS 6.*/7.* Minimal, Ubuntu server 12.04/14.04 
#  32bit and 64bit
#
#  Author Pascal Peyremorte (ppeyremorte@sentora.org)
#    (main merge of all installers, modularization, reworks and comments)
#  With huge help and contributions from Mehdi Blagui, Kevin Andrews and 
#  all those who participated to this and to previous installers.
#  Thanks to all.

FUSIONPANEL_INSTALLER_VERSION="0.0.1"
FUSIONPANEL_CORE_VERSION="master"
FUSIONPANEL_PRECONF_VERSION="master"

PANEL_PATH="/etc/fusionpanel"
PANEL_DATA="/var/fusionpanel"

#--- Display the 'welcome' splash/user warning info..
echo ""
echo "############################################################"
echo "#  Welcome to the Official FusionPanel Installer $FUSIONPANEL_INSTALLER_VERSION  #"
echo "############################################################"

echo -e "\nChecking that minimal requirements are ok"

# Ensure the OS is compatible with the launcher
if [ -f /etc/centos-release ]; then
    OS="CentOs"
    VERFULL=$(sed 's/^.*release //;s/ (Fin.*$//' /etc/centos-release)
    VER=${VERFULL:0:1} # return 6 or 7
elif [ -f /etc/lsb-release ]; then
    OS=$(grep DISTRIB_ID /etc/lsb-release | sed 's/^.*=//')
    VER=$(grep DISTRIB_RELEASE /etc/lsb-release | sed 's/^.*=//')
else
    OS=$(uname -s)
    VER=$(uname -r)
fi
ARCH=$(uname -m)

echo "Detected : $OS  $VER  $ARCH"

if [[ "$OS" = "CentOs" && ("$VER" = "6" || "$VER" = "7" ) || 
      "$OS" = "Ubuntu" && ("$VER" = "12.04" || "$VER" = "14.04" ) ]] ; then 
    echo "Ok."
else
    echo "Sorry, this OS is not supported by FusionPanel." 
    exit 1
fi

if [[ "$ARCH" == "i386" || "$ARCH" == "i486" || "$ARCH" == "i586" || "$ARCH" == "i686" ]]; then
    ARCH="i386"
elif [[ "$ARCH" != "x86_64" ]]; then
    echo "Unexpected architecture name was returned ($ARCH ). :-("
    echo "The installer have been designed for i[3-6]8- and x86_6' architectures. If you"
    echo " think it may work on your, please report it to the FusionPanel forum or bugtracker."
    exit 1
fi

# Check if the user is 'root' before allowing installation to commence
if [ $UID -ne 0 ]; then
    echo "Install failed: you must be logged in as 'root' to install."
    echo "Use command 'sudo -i', then enter root password and then try again."
    exit 1
fi

# Select modules that will be checked before start
if [[ "$OS" = "CentOs" ]] ; then
    PACKAGE_INSTALLER="yum -y -q install"
    PACKAGE_REMOVER="yum -y -q remove"

    if  [[ "$VER" = "7" ]]; then
        DB_PCKG="mariadb" &&  echo "DB server will be mariaDB"
    else 
        DB_PCKG="mysql" && echo "DB server will be mySQL"
    fi
    HTTP_PCKG="httpd"
    PHP_PCKG="php"
    BIND_PCKG="bind"
elif [[ "$OS" = "Ubuntu" ]]; then
    PACKAGE_INSTALLER="apt-get -yqq install"
    PACKAGE_REMOVER="apt-get -yqq remove"
    
    DB_PCKG="mysql-server"
    HTTP_PCKG="apache2"
    PHP_PCKG="apache2-mod-php5"
    BIND_PCKG="bind9"
fi
  
# Check for some common control panels that we know will affect the installation/operating of FusionPanel.
if [ -e /usr/local/cpanel ] || [ -e /usr/local/directadmin ] || [ -e /usr/local/solusvm/www ] || [ -e /usr/local/home/admispconfig ] || [ -e /usr/local/lxlabs/kloxo ] ; then
    echo "It appears that a control panel is already installed on your server; This installer"
    echo "is designed to install and configure FusionPanel on a clean OS installation only."
    echo -e "\nPlease re-install your OS before attempting to install using this script."
    exit 1
fi

# Check for some common packages that we know will affect the installation/operating of FusionPanel.
# We expect a clean OS so no apache/mySQL/bind/postfix/php!
if [[ "$OS" = "CentOs" ]] ; then
    inst() {
       rpm -q "$1" &> /dev/null
    }
elif [[ "$OS" = "Ubuntu" ]]; then
    inst() {
       dpkg -l "$1" 2> /dev/null | grep '^ii' &> /dev/null
    }
fi

# Note : Postfix is installed by default on centos netinstall / minimum install.
# The installer seems to work fine even if Postfix is already installed.
# -> The check of postfix is removed, but this comment remains to remember
for package in "$DB_PCKG" "dovecot-mysql" "$HTTP_PCKG" "$PHP_PCKG" "proftpd" "$BIND_PCKG" ; do
    if (inst "$package"); then
        echo "It appears that package $package is already installed. This installer"
        echo "is designed to install and configure FusionPanel on a clean OS installation only!"
        echo -e "\nPlease re-install your OS before attempting to install using this script."
        exit 1
    fi
done

# *************************************************
#--- Prepare or query informations required to install

# Install wget and util used to grab server IP, and get server IPs
$PACKAGE_INSTALLER wget 
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER bind-utils
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER dnsutils
fi
extern_ip="$(wget -qO- http://api.sentora.org/ip.txt)"
local_ip=$(ifconfig eth0 | sed -En 's|.*inet [^0-9]*(([0-9]*\.){3}[0-9]*).*$|\1|p')

# Enable parameters to be entered on commandline, required for vagrant install
#   -d <panel-domain>
#   -i <server-ip> (or -i local or -i public, see below)
#   -t <timezone-string>
# like :
#   fusionpanel_install.sh -t Europe/Paris -d panel.domain.tld -i xxx.xxx.xxx.xxx
# notes:
#   -d and -i must be both present or both absent
#   -i local  force use of local detected ip
#   -i public  force use of public detected ip
#   if -t is used without -d/-i, timezone is set from value given and not asked to user
#   if -t absent and -d/-i are present, timezone is not set at all

while getopts d:i:t: opt; do
  case $opt in
  d)
      PANEL_FQDN=$OPTARG
      INSTALL="auto"
      ;;
  i)
      PUBLIC_IP=$OPTARG
      if [[ "$PUBLIC_IP" == "local" ]] ; then
          PUBLIC_IP=$local_ip
      elif [[ "$PUBLIC_IP" == "public" ]] ; then
          PUBLIC_IP=$extern_ip
      fi
      ;;
  t)
      echo "$OPTARG" > /etc/timezone
      tz=$(cat /etc/timezone)
      ;;
  esac
done
if [[ ("$PANEL_FQDN" != "" && "$PUBLIC_IP" == "") || 
      ("$PANEL_FQDN" == "" && "$PUBLIC_IP" != "") ]] ; then
    echo "-d and -i must be both present or both absent."
    exit 2
fi


if [[ "$tz" == "" && "$PANEL_FQDN" == "" ]] ; then
    # Propose selection list for the time zone
    echo "Preparing to select timezone, please wait a few seconds..."
    $PACKAGE_INSTALLER tzdata
    # setup server timezone
    if [[ "$OS" = "CentOs" ]]; then
        # make tzselect to save TZ in /etc/timezone
        echo "echo \$TZ > /etc/timezone" >> /usr/bin/tzselect
        tzselect
        tz=$(cat /etc/timezone)
    elif [[ "$OS" = "Ubuntu" ]]; then
        dpkg-reconfigure tzdata
        tz=$(cat /etc/timezone)
    fi
fi
# clear timezone information to focus user on important notice
clear

# Installer parameters
if [[ "$PANEL_FQDN" == "" ]] ; then
    echo -e "\n\e[1;33m=== Informations required to build your server ===\e[0m"
    echo 'The installer requires 2 pieces of information:'
    echo ' 1) the sub-domain that you want to use to access FusionPanel panel,'
    echo '   - do not use your main domain (like domain.com)'
    echo '   - use a sub-domain, e.g panel.domain.com'
    echo '   - or use the server hostname, e.g server1.domain.com'
    echo '   - DNS must already be configured and pointing to the server IP'
    echo '       for this sub-domain'
    echo ' 2) The public IP of the server.'
    echo ''

    PANEL_FQDN="$(/bin/hostname)"
    PUBLIC_IP=$extern_ip
    while true; do
        echo ""
        read -e -p "Enter the sub-domain you want to access FusionPanel panel: " -i "$PANEL_FQDN" PANEL_FQDN

        if [[ "$PUBLIC_IP" != "$local_ip" ]]; then
          echo -e "\nThe public IP of the server is $PUBLIC_IP. Its local IP is $local_ip"
          echo "  For a production server, the PUBLIC IP must be used."
        fi  
        read -e -p "Enter (or confirm) the public IP for this server: " -i "$PUBLIC_IP" PUBLIC_IP
        echo ""

        # Checks if the panel domain is a subdomain
        sub=$(echo "$PANEL_FQDN" | sed -n 's|\(.*\)\..*\..*|\1|p')
        if [[ "$sub" == "" ]]; then
            echo -e "\e[1;31mWARNING: $PANEL_FQDN is not a subdomain!\e[0m"
            confirm="true"
        fi

        # Checks if the panel domain is already assigned in DNS
        dns_panel_ip=$(host "$PANEL_FQDN"|grep address|cut -d" " -f4)
        if [[ "$dns_panel_ip" == "" ]]; then
            echo -e "\e[1;31mWARNING: $PANEL_FQDN is not defined in your DNS!\e[0m"
            echo "  You must add records in your DNS manager (and then wait until propagation is done)."
            echo "  For more information, read the FusionPanel documentation:"
            echo "   - http://docs.fusionpanel.org/index.php?node=7 (Installing FusionPanel)"
            echo "   - http://docs.fusionpanel.org/index.php?node=51 (Installer questions)"
            echo "  If this is a production installation, set the DNS up as soon as possible."
            confirm="true"
        else
            echo -e "\e[1;32mOK\e[0m: DNS successfully resolves $PANEL_FQDN to $dns_panel_ip"

            # Check if panel domain matches public IP
            if [[ "$dns_panel_ip" != "$PUBLIC_IP" ]]; then
                echo -e -n "\e[1;31mWARNING: $PANEL_FQDN DNS record does not point to $PUBLIC_IP!\e[0m"
                echo "  FusionPanel will not be reachable from http://$PANEL_FQDN"
                confirm="true"
            fi
        fi

        if [[ "$PUBLIC_IP" != "$extern_ip" && "$PUBLIC_IP" != "$local_ip" ]]; then
            echo -e -n "\e[1;31mWARNING: $PUBLIC_IP does not match detected IP !\e[0m"
            echo "  FusionPanel will not work with this IP..."
                confirm="true"
        fi
      
        echo ""
        # if any warning, ask confirmation to continue or propose to change
        if [[ "$confirm" != "" ]] ; then
            echo "There are some warnings..."
            echo "Are you really sure that you want to setup FusionPanel with these parameters?"
            read -e -p "(y):Accept and install, (n):Change domain or IP, (q):Quit installer? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) continue;;
                [Qq]* ) exit;;
            esac
        else
            read -e -p "All is ok. Do you want to install FusionPanel now (y/n)? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) exit;;
            esac
        fi
    done
fi

# ***************************************
# Installation really starts here

#--- Set custom logging methods so we create a log file in the current working directory.
logfile=$(date +%Y-%m-%d_%H.%M.%S_fusionpanel_install.log)
touch "$logfile"
exec > >(tee "$logfile")
exec 2>&1

echo "Installer version $FUSIONPANEL_INSTALLER_VERSION"
echo "FusionPanel core version $FUSIONPANEL_CORE_VERSION"
echo "FusionPanel preconf version $FUSIONPANEL_PRECONF_VERSION"
echo ""
echo "Installing FusionPanel $FUSIONPANEL_CORE_VERSION at http://$PANEL_FQDN and ip $PUBLIC_IP"
echo "on server under: $OS  $VER  $ARCH"
uname -a

# Function to disable a file by appending its name with _disabled
disable_file() {
    mv "$1" "$1_disabled_by_fusionpanel" &> /dev/null
}

#--- AppArmor must be disabled to avoid problems
if [[ "$OS" = "Ubuntu" ]]; then
    [ -f /etc/init.d/apparmor ]
    if [ $? = "0" ]; then
        echo -e "\n-- Disabling and removing AppArmor, please wait..."
        /etc/init.d/apparmor stop &> /dev/null
        update-rc.d -f apparmor remove &> /dev/null
        apt-get remove -y --purge apparmor* &> /dev/null
        disable_file /etc/init.d/apparmor &> /dev/null
        echo -e "AppArmor has been removed."
    fi
fi

#--- Adapt repositories and packages sources
echo -e "\n-- Updating repositories and packages sources"
if [[ "$OS" = "CentOs" ]]; then
    #EPEL Repo Install
    EPEL_BASE_URL="http://dl.fedoraproject.org/pub/epel/$VER/$ARCH";
    if  [[ "$VER" = "7" ]]; then
        EPEL_FILE=$(wget -q -O- "$EPEL_BASE_URL/e/" | grep -oP '(?<=href=")epel-release.*(?=">)')
        wget "$EPEL_BASE_URL/e/$EPEL_FILE"
    else 
        EPEL_FILE=$(wget -q -O- "$EPEL_BASE_URL/" | grep -oP '(?<=href=")epel-release.*(?=">)')
        wget "$EPEL_BASE_URL/$EPEL_FILE"
    fi
    $PACKAGE_INSTALLER -y install epel-release*.rpm
    rm "$EPEL_FILE"
    
    #To fix some problems of compatibility use of mirror centos.org to all users
    #Replace all mirrors by base repos to avoid any problems.
    sed -i 's|mirrorlist=http://mirrorlist.centos.org|#mirrorlist=http://mirrorlist.centos.org|' "/etc/yum.repos.d/CentOS-Base.repo"
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://mirror.centos.org|' "/etc/yum.repos.d/CentOS-Base.repo"

    #check if the machine and on openvz
    if [ -f "/etc/yum.repos.d/vz.repo" ]; then
        sed -i "s|mirrorlist=http://vzdownload.swsoft.com/download/mirrors/centos-$VER|baseurl=http://vzdownload.swsoft.com/ez/packages/centos/$VER/$ARCH/os/|" "/etc/yum.repos.d/vz.repo"
        sed -i "s|mirrorlist=http://vzdownload.swsoft.com/download/mirrors/updates-released-ce$VER|baseurl=http://vzdownload.swsoft.com/ez/packages/centos/$VER/$ARCH/updates/|" "/etc/yum.repos.d/vz.repo"
    fi

    #disable deposits that could result in installation errors
    disablerepo() {
        if [ -f "/etc/yum.repos.d/$1.repo" ]; then
            sed -i 's/enabled=1/enabled=0/g' "/etc/yum.repos.d/$1.repo"
        fi
    }
    disablerepo "elrepo"
    disablerepo "epel-testing"
    disablerepo "remi"
    disablerepo "rpmforge"
    disablerepo "rpmfusion-free-updates"
    disablerepo "rpmfusion-free-updates-testing"

    # We need to disable SELinux...
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0

    # Stop conflicting services and iptables to ensure all services will work
    service sendmail stop
    chkconfig sendmail off

    # disable firewall
    if  [[ "$VER" = "7" ]]; then
        FIREWALL_SERVICE="firewalld"
    else 
        FIREWALL_SERVICE="iptables"
    fi
    service "$FIREWALL_SERVICE" save
    service "$FIREWALL_SERVICE" stop
    chkconfig "$FIREWALL_SERVICE" off

    # Removal of conflicting packages prior to FusionPanel installation.
    if (inst bind-chroot) ; then 
        $PACKAGE_REMOVER bind-chroot
    fi
    if (inst qpid-cpp-client) ; then
        $PACKAGE_REMOVER qpid-cpp-client
    fi

elif [[ "$OS" = "Ubuntu" ]]; then 
    # Update the enabled Aptitude repositories
    echo -ne "\nUpdating Aptitude Repos: " >/dev/tty

    mkdir -p "/etc/apt/sources.list.d.save"
    cp -R "/etc/apt/sources.list.d/*" "/etc/apt/sources.list.d.save" &> /dev/null
    rm -rf "/etc/apt/sources.list/*"
    cp "/etc/apt/sources.list" "/etc/apt/sources.list.save"

    if [ "$VER" = "14.04" ]; then
        cat > /etc/apt/sources.list <<EOF
#Depots main restricted
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main restricted universe multiverse
EOF
    else
        cat > /etc/apt/sources.list <<EOF
#Depots main restricted
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted
deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted
 
deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted
deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted
deb-src http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted

#Depots Universe Multiverse 
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe multiverse
deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates universe multiverse

deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe multiverse
deb-src http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates universe multiverse
EOF
    fi
fi

#--- List all already installed packages (may help to debug)
echo -e "\n-- Listing of all packages installed:"
if [[ "$OS" = "CentOs" ]]; then
    rpm -qa | sort
elif [[ "$OS" = "Ubuntu" ]]; then
    dpkg --get-selections
fi

#--- Ensures that all packages are up to date
echo -e "\n-- Updating+upgrading system, it may take some time..."
if [[ "$OS" = "CentOs" ]]; then
    yum -y update
    yum -y upgrade
elif [[ "$OS" = "Ubuntu" ]]; then
    apt-get -yqq update
    apt-get -yqq upgrade
fi

#--- Install utility packages required by the installer and/or FusionPanel.
echo -e "\n-- Downloading and installing required tools..."
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER sudo vim make zip unzip chkconfig bash-completion
    $PACKAGE_INSTALLER ld-linux.so.2 libbz2.so.1 libdb-4.7.so libgd.so.2 
    $PACKAGE_INSTALLER curl curl-devel perl-libwww-perl libxml2 libxml2-devel zip bzip2-devel gcc gcc-c++ at make
    $PACKAGE_INSTALLER redhat-lsb-core
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER sudo vim make zip unzip debconf-utils at build-essential bash-completion
fi

#: <<'TO_BE_CHECKED'
#--- Prepare hostname
old_hostname=$(cat /etc/hostname)
# In file hostname
echo "$PANEL_FQDN" /etc/hostnames

# In file hosts
sed -i "s|$old_hostname|$PANEL_FQDN|" /etc/hosts

# For current session
hostname "$PANEL_FQDN"

# In network file
if [[ "$OS" = "CentOs" && "$VER" = "6" ]]; then
    sed -i "s|^\(HOSTNAME=\).*\$|HOSTNAME=$PANEL_FQDN|" /etc/sysconfig/network
    /etc/init.d/network restart
fi
#TO_BE_CHECKED

#--- Download FusionPanel archive from GitHub
echo -e "\n-- Downloading FusionPanel, Please wait, this may take several minutes, the installer will continue after this is complete!"
# Get latest fusionpanel
#wget -nv -O fusionpanel_core.zip https://github.com/fusionpanel/fusionpanel-core/archive/$FUSIONPANEL_CORE_VERSION.zip
#wget -nv -O fusionpanel_core.zip https://github.com/mjsorribas/fusionpanel-core/archive/master.zip
wget -nv -O fusionpanel_core.zip https://github.com/mjsorribas/fusionpanel-core/archive/$FUSIONPANEL_CORE_VERSION.zip
#git clone https://github.com/mjsorribas/fusionpanel-core.git
mkdir -p $PANEL_PATH
chown -R root:root $PANEL_PATH
unzip -oq fusionpanel_core.zip -d $PANEL_PATH
mv "$PANEL_PATH/fusionpanel-core-$FUSIONPANEL_CORE_VERSION" "$PANEL_PATH/panel"
rm fusionpanel_core.zip
rm "$PANEL_PATH/panel/LICENSE.md" "$PANEL_PATH/panel/README.md" "$PANEL_PATH/panel/.gitignore"
rm -rf "$PANEL_PATH/_delete_me"

# Remove unusued build branch until it is also removed from github fusionpanel-core master
rm -rf "$PANEL_PATH/panel/etc/build"

#--- Set-up FusionPanel directories and configure permissions
PANEL_CONF="$PANEL_PATH/configs"

mkdir -p $PANEL_CONF
mkdir -p $PANEL_PATH/docs
chmod -R 777 $PANEL_PATH

mkdir -p $PANEL_DATA/logs/proftpd
mkdir -p $PANEL_DATA/backups
chmod -R 777 $PANEL_DATA/

# Links for compatibility with zpanel access
ln -s $PANEL_PATH /etc/zpanel
ln -s $PANEL_DATA /var/zpanel

#--- Prepare FusionPanel executables
chmod +x $PANEL_PATH/panel/bin/zppy 
ln -s $PANEL_PATH/panel/bin/zppy /usr/bin/zppy

chmod +x $PANEL_PATH/panel/bin/setso
ln -s $PANEL_PATH/panel/bin/setso /usr/bin/setso

chmod +x $PANEL_PATH/panel/bin/setzadmin
ln -s $PANEL_PATH/panel/bin/setzadmin /usr/bin/setzadmin

#--- Install preconfig
wget -nv -O fusionpanel_preconfig.zip https://github.com/mjsorribas/fusionpanel-installers/archive/$FUSIONPANEL_PRECONF_VERSION.zip
unzip -oq fusionpanel_preconfig.zip
cp -rf fusionpanel-installers-$FUSIONPANEL_PRECONF_VERSION/preconf/* $PANEL_CONF
rm fusionpanel_preconfig*
rm -rf fusionpanel-*

#--- Prepare zsudo
cc -o $PANEL_PATH/panel/bin/zsudo $PANEL_CONF/bin/zsudo.c
sudo chown root $PANEL_PATH/panel/bin/zsudo
chmod +s $PANEL_PATH/panel/bin/zsudo

#--- Some functions used many times below
# Random password generator function
passwordgen() {
    l=$1
    [ "$l" == "" ] && l=16
    tr -dc A-Za-z0-9 < /dev/urandom | head -c ${l} | xargs
}

# Add first parameter in hosts file as local IP domain
add_local_domain() {
    if ! grep -q "127.0.0.1 $1" /etc/hosts; then
        echo "127.0.0.1 $1" >> /etc/hosts;
    fi
}

#-----------------------------------------------------------
# Install all softwares and dependencies required by FusionPanel.

if [[ "$OS" = "Ubuntu" ]]; then
    # Disable the DPKG prompts before we run the software install to enable fully automated install.
    export DEBIAN_FRONTEND=noninteractive
fi

#--- MySQL
echo -e "\n-- Installing MySQL"
mysqlpassword=$(passwordgen);
$PACKAGE_INSTALLER "$DB_PCKG"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER "DB_PCKG-devel" "$DB_PCKG-server" 
    MY_CNF_PATH="/etc/my.cnf"
    if  [[ "$VER" = "7" ]]; then
        DB_SERVICE="mariadb"
    else 
        DB_SERVICE="mysqld"
    fi
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER bsdutils libsasl2-modules-sql libsasl2-modules
    if [ "$VER" = "12.04" ]; then
        $PACKAGE_INSTALLER db4.7-util
    fi
    MY_CNF_PATH="/etc/mysql/my.cnf"
    DB_SERVICE="mysql"
fi
service $DB_SERVICE start

# setup mysql root password
mysqladmin -u root password "$mysqlpassword"

# small cleaning of mysql access
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User='root' AND Host != 'localhost'";
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User=''";
mysql -u root -p"$mysqlpassword" -e "FLUSH PRIVILEGES";

# remove test table that is no longer used
mysql -u root -p"$mysqlpassword" -e "DROP DATABASE IF EXISTS test";

# secure SELECT "hacker-code" INTO OUTFILE 
sed -i "s|\[mysqld\]|&\nsecure-file-priv = /var/tmp|" $MY_CNF_PATH

# setup fusionpanel access and core database
sed -i "s|YOUR_ROOT_MYSQL_PASSWORD|$mysqlpassword|" $PANEL_PATH/panel/cnf/db.php
mysql -u root -p"$mysqlpassword" < $PANEL_CONF/fusionpanel-install/sql/fusionpanel_core.sql

# Register mysql/mariadb service for autostart
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable "$DB_SERVICE".service
    else
        chkconfig "$DB_SERVICE" on
    fi
fi


#--- Postfix
echo -e "\n-- Installing Postfix"
postfixpassword=$(passwordgen);
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER postfix postfix-perl-scripts
    USR_LIB_PATH="/usr/libexec"
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER postfix postfix-mysql
    USR_LIB_PATH="/usr/lib"
fi
#--- OpenDKIM
echo -e "\n-- Installing OpenDKIM"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER opendkim
    USR_LIB_PATH="/usr/libexec"
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER opendkim
    USR_LIB_PATH="/usr/lib"
fi
#--- DenyHosts
echo -e "\n-- Installing DenyHosts"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER denyhosts
    USR_LIB_PATH="/usr/libexec"
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER denyhosts
    USR_LIB_PATH="/usr/lib"
fi

mysql -u root -p"$mysqlpassword" < $PANEL_CONF/fusionpanel-install/sql/fusionpanel_postfix.sql
mysql -u root -p"$mysqlpassword" -e "UPDATE mysql.user SET Password=PASSWORD('$postfixpassword') WHERE User='postfix' AND Host='localhost';";

mkdir $PANEL_DATA/vmail
useradd -r -g mail -d $PANEL_DATA/vmail -s /sbin/nologin -c "Virtual maildir" vmail
chown -R vmail:mail $PANEL_DATA/vmail
chmod -R 770 $PANEL_DATA/vmail

mkdir -p /var/spool/vacation
useradd -r -d /var/spool/vacation -s /sbin/nologin -c "Virtual vacation" vacation
chown -R vacation:vacation /var/spool/vacation
chmod -R 770 /var/spool/vacation

#Removed optionnal transport that was leaved empty, until it is fully handled.
#ln -s $PANEL_CONF/postfix/transport /etc/postfix/transport
#postmap /etc/postfix/transport

add_local_domain "$PANEL_FQDN"
add_local_domain "autoreply.$PANEL_FQDN"

rm -rf /etc/postfix/main.cf /etc/postfix/master.cf
ln -s $PANEL_CONF/postfix/master.cf /etc/postfix/master.cf
ln -s $PANEL_CONF/postfix/main.cf /etc/postfix/main.cf
ln -s $PANEL_CONF/postfix/vacation.pl /var/spool/vacation/vacation.pl

sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/postfix/*.cf
sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/postfix/vacation.conf
sed -i "s|!PANEL_FQDN!|$PANEL_FQDN|" $PANEL_CONF/postfix/main.cf

sed -i "s|!USR_LIB!|$USR_LIB_PATH|" $PANEL_CONF/postfix/master.cf
sed -i "s|!USR_LIB!|$USR_LIB_PATH|" $PANEL_CONF/postfix/main.cf
sed -i "s|!SERVER_IP!|$PUBLIC_IP|" $PANEL_CONF/postfix/main.cf 

VMAIL_UID=$(id -u vmail)
MAIL_GID=$(sed -nr "s/^mail:x:([0-9]+):.*/\1/p" /etc/group)
sed -i "s|!POS_UID!|$VMAIL_UID|" $PANEL_CONF/postfix/main.cf
sed -i "s|!POS_GID!|$MAIL_GID|" $PANEL_CONF/postfix/main.cf

# remove unusued directives that issue warnings
sed -i '/virtual_mailbox_limit_maps/d' $PANEL_CONF/postfix/main.cf
sed -i '/smtpd_bind_address/d' $PANEL_CONF/postfix/master.cf

# Register postfix service for autostart (it is automatically started)
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable postfix.service
        # systemctl start postfix.service
    else
        chkconfig postfix on
        # /etc/init.d/postfix start
    fi
fi


#--- Dovecot (includes Sieve)
echo -e "\n-- Installing Dovecot"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER dovecot dovecot-mysql dovecot-pigeonhole 
    sed -i "s|#first_valid_uid = ?|first_valid_uid = $VMAIL_UID\n#last_valid_uid = $VMAIL_UID\n\nfirst_valid_gid = $MAIL_GID\n#last_valid_gid = $MAIL_GID|" $PANEL_CONF/dovecot2/dovecot.conf
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER dovecot-mysql dovecot-imapd dovecot-pop3d dovecot-common dovecot-managesieved dovecot-lmtpd 
    sed -i "s|#first_valid_uid = ?|first_valid_uid = $VMAIL_UID\nlast_valid_uid = $VMAIL_UID\n\nfirst_valid_gid = $MAIL_GID\nlast_valid_gid = $MAIL_GID|" $PANEL_CONF/dovecot2/dovecot.conf
fi

mkdir -p $PANEL_DATA/sieve
chown -R vmail:mail $PANEL_DATA/sieve
mkdir -p /var/lib/dovecot/sieve/
touch /var/lib/dovecot/sieve/default.sieve
ln -s $PANEL_CONF/dovecot2/globalfilter.sieve $PANEL_DATA/sieve/globalfilter.sieve

rm -rf /etc/dovecot/dovecot.conf
ln -s $PANEL_CONF/dovecot2/dovecot.conf /etc/dovecot/dovecot.conf
sed -i "s|!POSTMASTER_EMAIL!|postmaster@$PANEL_FQDN|" $PANEL_CONF/dovecot2/dovecot.conf
sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/dovecot2/dovecot-dict-quota.conf
sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/dovecot2/dovecot-mysql.conf
sed -i "s|!DOV_UID!|$VMAIL_UID|" $PANEL_CONF/dovecot2/dovecot-mysql.conf
sed -i "s|!DOV_GID!|$MAIL_GID|" $PANEL_CONF/dovecot2/dovecot-mysql.conf

touch /var/log/dovecot.log /var/log/dovecot-info.log /var/log/dovecot-debug.log
chown vmail:mail /var/log/dovecot*
chmod 660 /var/log/dovecot*

# Register dovecot service for autostart and start it
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable dovecot.service
        systemctl start dovecot.service
    else
        chkconfig dovecot on
        /etc/init.d/dovecot start
    fi
fi

#--- Apache server
echo -e "\n-- Installing and configuring Apache"
$PACKAGE_INSTALLER "$HTTP_PCKG"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER "$HTTP_PCKG-devel"
    HTTP_CONF_PATH="/etc/httpd/conf/httpd.conf"
    HTTP_VARS_PATH="/etc/sysconfig/httpd"
    HTTP_SERVICE="httpd"
    HTTP_USER="apache"
    HTTP_GROUP="apache"
    if [[ "$VER" = "7" ]]; then
        # Disable extra modules in centos 7
        disable_file /etc/httpd/conf.modules.d/01-cgi.conf
        disable_file /etc/httpd/conf.modules.d/00-lua.conf
        disable_file /etc/httpd/conf.modules.d/00-dav.conf
    else
        disable_file /etc/httpd/conf.d/welcome.conf
        disable_file /etc/httpd/conf.d/webalizer.conf
    fi     
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER libapache2-mod-bw
    HTTP_CONF_PATH="/etc/apache2/apache2.conf"
    HTTP_VARS_PATH="/etc/apache2/envvars"
    HTTP_SERVICE="apache2"
    HTTP_USER="www-data"
    HTTP_GROUP="www-data"
    a2enmod rewrite
fi

if ! grep -q "Include $PANEL_CONF/apache/httpd.conf" "$HTTP_CONF_PATH"; then
    echo "Include $PANEL_CONF/apache/httpd.conf" >> "$HTTP_CONF_PATH";
fi
add_local_domain "$(hostname)"

if ! grep -q "apache ALL=NOPASSWD: $PANEL_PATH/panel/bin/zsudo" /etc/sudoers; then
    echo "apache ALL=NOPASSWD: $PANEL_PATH/panel/bin/zsudo" >> /etc/sudoers;
fi

# Create root directory for public HTTP docs
mkdir -p $PANEL_DATA/hostdata/zadmin/public_html
chown -R $HTTP_USER:$HTTP_GROUP $PANEL_DATA/hostdata/
chmod -R 770 $PANEL_DATA/hostdata/

mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$HTTP_SERVICE' WHERE so_name_vc='httpd_exe'"
mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$HTTP_SERVICE' WHERE so_name_vc='apache_sn'"

#Set keepalive on (default is off)
sed -i "s|KeepAlive Off|KeepAlive On|" "$HTTP_CONF_PATH"

# Permissions fix for Apache and ProFTPD (to enable them to play nicely together!)
if ! grep -q "umask 002" "$HTTP_VARS_PATH"; then
    echo "umask 002" >> "$HTTP_VARS_PATH";
fi

# remove default virtual site to ensure FusionPanel is the default vhost
if [[ "$OS" = "CentOs" ]]; then
    sed -i "s|DocumentRoot \"/var/www/html\"|DocumentRoot $PANEL_PATH/panel|" "$HTTP_CONF_PATH"
elif [[ "$OS" = "Ubuntu" ]]; then
    # disable completely sites-enabled/000-default.conf
    if [[ "$VER" = "14.04" ]]; then 
        sed -i "s|IncludeOptional sites-enabled|#&|" "$HTTP_CONF_PATH"
    else
        sed -i "s|Include sites-enabled|#&|" "$HTTP_CONF_PATH"
    fi
fi

# Comment "NameVirtualHost" and Listen directives that are handled in vhosts file
if [[ "$OS" = "CentOs" ]]; then
    sed -i "s|^\(NameVirtualHost .*$\)|#\1\n# NameVirtualHost is now handled in FusionPanel vhosts file|" "$HTTP_CONF_PATH"
    sed -i 's|^\(Listen .*$\)|#\1\n# Listen is now handled in FusionPanel vhosts file|' "$HTTP_CONF_PATH"
elif [[ "$OS" = "Ubuntu" ]]; then
    sed -i "s|\(Include ports.conf\)|#\1\n# Ports are now handled in FusionPanel vhosts file|" "$HTTP_CONF_PATH"
    disable_file /etc/apache2/ports.conf
fi

# adjustments for apache 2.4
if [[ ("$OS" = "CentOs" && "$VER" = "7") || 
      ("$OS" = "Ubuntu" && "$VER" = "14.04") ]] ; then 
    # Order deny,allow / Deny from all   ->  Require all denied
    sed -i 's|Order deny,allow|Require all denied|I'  $PANEL_CONF/apache/httpd.conf
    sed -i '/Deny from all/d' $PANEL_CONF/apache/httpd.conf

    # Order allow,deny / Allow from all  ->  Require all granted
    sed -i 's|Order allow,deny|Require all granted|I' $PANEL_CONF/apache/httpd-vhosts.conf
    sed -i '/Allow from all/d' $PANEL_CONF/apache/httpd-vhosts.conf

    sed -i 's|Order allow,deny|Require all granted|I'  $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php
    sed -i '/Allow from all/d' $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php

    # Remove NameVirtualHost that is now without effect and generate warning
    sed -i '/NameVirtualHost/{N;d}' $PANEL_CONF/apache/httpd-vhosts.conf
    sed -i '/# NameVirtualHost is/ {N;N;N;N;N;d}' $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php

    # Options must have ALL (or none) +/- prefix, disable listing directories
    sed -i 's| FollowSymLinks [-]Indexes| +FollowSymLinks -Indexes|' $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php
fi


#--- PHP
echo -e "\n-- Installing and configuring PHP"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER php php-devel php-gd php-mbstring php-intl php-mysql php-xml php-xmlrpc
    $PACKAGE_INSTALLER php-mcrypt php-imap  #Epel packages
    PHP_INI_PATH="/etc/php.ini"
    PHP_EXT_PATH="/etc/php.d"
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER libapache2-mod-php5 php5-common php5-cli php5-mysql php5-gd php5-mcrypt php5-curl php-pear php5-imap php5-xmlrpc php5-xsl
    if [ "$VER" = "14.04" ]; then
        php5enmod mcrypt  # missing in the package for Ubuntu 14!
    else
        $PACKAGE_INSTALLER php5-suhosin
    fi
    PHP_INI_PATH="/etc/php5/apache2/php.ini"
fi
# Setup php upload dir
mkdir -p $PANEL_DATA/temp
chmod 1777 $PANEL_DATA/temp/
chown -R $HTTP_USER:$HTTP_GROUP $PANEL_DATA/temp/

# Setup php session save directory
mkdir "$PANEL_DATA/sessions"
chown $HTTP_USER:$HTTP_GROUP "$PANEL_DATA/sessions"
chmod 733 "$PANEL_DATA/sessions"
chmod +t "$PANEL_DATA/sessions"

if [[ "$OS" = "CentOs" ]]; then
    # Remove session & php values from apache that cause override
    sed -i "/php_value/d" /etc/httpd/conf.d/php.conf
elif [[ "$OS" = "Ubuntu" ]]; then
    sed -i "s|;session.save_path = \"/var/lib/php5\"|session.save_path = \"$PANEL_DATA/sessions\"|" $PHP_INI_PATH
fi
sed -i "/php_value/d" $PHP_INI_PATH
echo "session.save_path = $PANEL_DATA/sessions;">> $PHP_INI_PATH

# setup timezone and upload temp dir
sed -i "s|;date.timezone =|date.timezone = $tz|" $PHP_INI_PATH
sed -i "s|;upload_tmp_dir =|upload_tmp_dir = $PANEL_DATA/temp/|" $PHP_INI_PATH

# Disable php signature in headers to hide it from hackers
sed -i "s|expose_php = On|expose_php = Off|" $PHP_INI_PATH

# Build suhosin for PHP 5.x which is required by FusionPanel. 
if [[ "$OS" = "CentOs" || ( "$OS" = "Ubuntu" && "$VER" = "14.04") ]] ; then
    echo -e "\n# Building suhosin"
    if [[ "$OS" = "Ubuntu" ]]; then
        $PACKAGE_INSTALLER php5-dev
    fi
    wget -nv -O suhosin.zip https://github.com/stefanesser/suhosin/archive/suhosin-0.9.36.zip
    unzip -q suhosin.zip
    rm -f suhosin.zip
    cd suhosin-suhosin-0.9.36
    phpize &> /dev/null
    ./configure &> /dev/null
    make &> /dev/null
    make install 
    cd ..
    rm -rf suhosin-suhosin-0.9.36
    if [[ "$OS" = "CentOs" ]]; then 
        echo 'extension=suhosin.so' > $PHP_EXT_PATH/suhosin.ini
    elif [[ "$OS" = "Ubuntu" ]]; then
        sed -i 'N;/default extension directory./a\extension=suhosin.so' $PHP_INI_PATH
    fi	
fi

# Register apache(+php) service for autostart and start it
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable "$HTTP_SERVICE.service"
        systemctl start "$HTTP_SERVICE.service"
    else
        chkconfig "$HTTP_SERVICE" on
        "/etc/init.d/$HTTP_SERVICE" start
    fi
fi


#--- ProFTPd
echo -e "\n-- Installing ProFTPD"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER proftpd proftpd-mysql 
    FTP_CONF_PATH='/etc/proftpd.conf'
    sed -i "s|nogroup|nobody|" $PANEL_CONF/proftpd/proftpd-mysql.conf
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER proftpd-mod-mysql
    FTP_CONF_PATH='/etc/proftpd/proftpd.conf'
fi

# Create and init proftpd database
mysql -u root -p"$mysqlpassword" < $PANEL_CONF/fusionpanel-install/sql/fusionpanel_proftpd.sql

# Create and configure mysql password for proftpd
proftpdpassword=$(passwordgen);
sed -i "s|!SQL_PASSWORD!|$proftpdpassword|" $PANEL_CONF/proftpd/proftpd-mysql.conf
mysql -u root -p"$mysqlpassword" -e "UPDATE mysql.user SET Password=PASSWORD('$proftpdpassword') WHERE User='proftpd' AND Host='localhost'";

# Assign httpd user and group to all users that will be created
HTTP_UID=$(id -u "$HTTP_USER")
HTTP_GID=$(sed -nr "s/^$HTTP_GROUP:x:([0-9]+):.*/\1/p" /etc/group)
mysql -u root -p"$mysqlpassword" -e "ALTER TABLE fusionpanel_proftpd.ftpuser ALTER COLUMN uid SET DEFAULT $HTTP_UID"
mysql -u root -p"$mysqlpassword" -e "ALTER TABLE fusionpanel_proftpd.ftpuser ALTER COLUMN gid SET DEFAULT $HTTP_GID"
sed -i "s|!SQL_MIN_ID!|$HTTP_UID|" $PANEL_CONF/proftpd/proftpd-mysql.conf

# Setup proftpd base file to call fusionpanel config
rm -f "$FTP_CONF_PATH"
#touch "$FTP_CONF_PATH"
#echo "include $PANEL_CONF/proftpd/proftpd-mysql.conf" >> "$FTP_CONF_PATH";
ln -s "$PANEL_CONF/proftpd/proftpd-mysql.conf" "$FTP_CONF_PATH"

chmod -R 644 $PANEL_DATA/logs/proftpd

# Register proftpd service for autostart and start it
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable proftpd.service
        systemctl start proftpd.service
    else
        chkconfig proftpd on
        /etc/init.d/proftpd start
    fi
fi

#--- BIND
echo -e "\n-- Installing and configuring Bind"
if [[ "$OS" = "CentOs" ]]; then
    $PACKAGE_INSTALLER bind bind-utils bind-libs
    BIND_PATH="/etc/named/"
    BIND_FILES="/etc"
    BIND_SERVICE="named"
    BIND_USER="named"
elif [[ "$OS" = "Ubuntu" ]]; then
    $PACKAGE_INSTALLER bind9 bind9utils
    BIND_PATH="/etc/bind/"
    BIND_FILES="/etc/bind"
    BIND_SERVICE="bind9"
    BIND_USER="bind"
    mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='' WHERE so_name_vc='bind_log'"
fi
mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$BIND_PATH' WHERE so_name_vc='bind_dir'"
mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$BIND_SERVICE' WHERE so_name_vc='bind_service'"
chmod -R 777 $PANEL_CONF/bind/zones/

# Setup logging directory
mkdir $PANEL_DATA/logs/bind
touch $PANEL_DATA/logs/bind/bind.log $PANEL_DATA/logs/bind/debug.log
chown $BIND_USER $PANEL_DATA/logs/bind/bind.log $PANEL_DATA/logs/bind/debug.log
chmod 660 $PANEL_DATA/logs/bind/bind.log $PANEL_DATA/logs/bind/debug.log

if [[ "$OS" = "CentOs" ]]; then
    chmod 751 /var/named
    chmod 771 /var/named/data
    sed -i 's|bind/zones.rfc1918|named.rfc1912.zones|' $PANEL_CONF/bind/named.conf
elif [[ "$OS" = "Ubuntu" ]]; then
    mkdir -p /var/named/dynamic
    touch /var/named/dynamic/managed-keys.bind
    chown -R bind:bind /var/named/
    chmod -R 777 $PANEL_CONF/bind/etc

    chown root:root $BIND_FILES/rndc.key
    chmod 755 $BIND_FILES/rndc.key
fi
# Some link to enable call from path
ln -s /usr/sbin/named-checkconf /usr/bin/named-checkconf
ln -s /usr/sbin/named-checkzone /usr/bin/named-checkzone
ln -s /usr/sbin/named-compilezone /usr/bin/named-compilezone

# Setup acl IP to forbid zone transfer
sed -i "s|!SERVER_IP!|$PUBLIC_IP|" $PANEL_CONF/bind/named.conf

# Build key and conf files
rm -rf $BIND_FILES/named.conf $BIND_FILES/rndc.conf $BIND_FILES/rndc.key
rndc-confgen -a -r /dev/urandom
cat $BIND_FILES/rndc.key $PANEL_CONF/bind/named.conf > $BIND_FILES/named.conf
cat $BIND_FILES/rndc.key $PANEL_CONF/bind/rndc.conf > $BIND_FILES/rndc.conf
rm -f $BIND_FILES/rndc.key

# Register Bind service for autostart and start it
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable named.service
        systemctl start named.service
    else
        chkconfig named on
        /etc/init.d/named start
    fi
fi


#--- CRON and ATD
echo -e "\n-- Installing and configuring cron tasks"
if [[ "$OS" = "CentOs" ]]; then
    #cronie & crontabs may be missing
    $PACKAGE_INSTALLER crontabs
    CRON_DIR="/var/spool/cron"
    CRON_SERVICE="crond"
elif [[ "$OS" = "Ubuntu" ]]; then
    CRON_DIR="/var/spool/cron/crontabs"
    CRON_SERVICE="cron"
fi
CRON_USER="$HTTP_USER"

# prepare daemon crontab
# sed -i "s|!USER!|$CRON_USER|" "$PANEL_CONF/cron/zdaemon" #it screw update search!#
sed -i "s|!USER!|root|" "$PANEL_CONF/cron/zdaemon"
cp "$PANEL_CONF/cron/zdaemon" /etc/cron.d/zdaemon
chmod 644 /etc/cron.d/zdaemon

# prepare user crontabs
CRON_FILE="$CRON_DIR/$CRON_USER"
mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$CRON_FILE' WHERE so_name_vc='cron_file'"
mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$CRON_FILE' WHERE so_name_vc='cron_reload_path'"
mysql -u root -p"$mysqlpassword" -e "UPDATE fusionpanel_core.x_settings SET so_value_tx='$CRON_USER' WHERE so_name_vc='cron_reload_user'"
{
    echo "SHELL=/bin/bash"
    echo "PATH=/sbin:/bin:/usr/sbin:/usr/bin"
    echo ""
} > mycron
crontab -u $HTTP_USER mycron
rm -f mycron

chmod 744 "$CRON_DIR"
chown -R $HTTP_USER:$HTTP_USER "$CRON_DIR"
chmod 644 "$CRON_FILE"

# Register cron and atd services for autostart and start them
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" ]]; then
        systemctl enable crond.service
        systemctl start crond.service
        systemctl start atd.service
    else
        chkconfig crond on
        /etc/init.d/crond start
        /etc/init.d/atd start
    fi
fi


#--- phpMyAdmin
echo -e "\n-- Configuring phpMyAdmin"
phpmyadminsecret=$(passwordgen);
chmod 644 $PANEL_CONF/phpmyadmin/config.inc.php
sed -i "s|\$cfg\['blowfish_secret'\] \= 'FUSIONPANEL';|\$cfg\['blowfish_secret'\] \= '$phpmyadminsecret';|" $PANEL_CONF/phpmyadmin/config.inc.php
ln -s $PANEL_CONF/phpmyadmin/config.inc.php $PANEL_PATH/panel/etc/apps/phpmyadmin/config.inc.php
# Remove phpMyAdmin's setup folder in case it was left behind
rm -rf $PANEL_PATH/panel/etc/apps/phpmyadmin/setup


#--- Roundcube
echo -e "\n-- Configuring Roundcube"
roundcube_des_key=$(passwordgen 24);
mysql -u root -p"$mysqlpassword" < $PANEL_CONF/fusionpanel-install/sql/fusionpanel_roundcube.sql
sed -i "s|YOUR_MYSQL_ROOT_PASSWORD|$mysqlpassword|" $PANEL_CONF/roundcube/db.inc.php
sed -i "s|#||" $PANEL_CONF/roundcube/db.inc.php
sed -i "s|rcmail-!24ByteDESkey\*Str|$roundcube_des_key|" $PANEL_CONF/roundcube/main.inc.php
rm -rf $PANEL_PATH/panel/etc/apps/webmail/config/main.inc.php
ln -s $PANEL_CONF/roundcube/main.inc.php $PANEL_PATH/panel/etc/apps/webmail/config/main.inc.php
ln -s $PANEL_CONF/roundcube/config.inc.php $PANEL_PATH/panel/etc/apps/webmail/plugins/managesieve/config.inc.php
ln -s $PANEL_CONF/roundcube/db.inc.php $PANEL_PATH/panel/etc/apps/webmail/config/db.inc.php

#--- Webalizer
echo -e "\n-- Configuring Webalizer"
$PACKAGE_INSTALLER webalizer
if [[ "$OS" = "CentOs" ]]; then
    rm -rf /etc/webalizer.conf
elif [[ "$OS" = "Ubuntu" ]]; then
    rm -rf /etc/webalizer/webalizer.conf
fi


#--- Set some FusionPanel database entries using. setso and setzadmin (require PHP)
echo -e "\n-- Configuring FusionPanel"
zadminpassword=$(passwordgen);
setzadmin --set "$zadminpassword";
$PANEL_PATH/panel/bin/setso --set fusionpanel_domain "$PANEL_FQDN"
$PANEL_PATH/panel/bin/setso --set server_ip "$PUBLIC_IP"

# make the daemon to build vhosts file.
$PANEL_PATH/panel/bin/setso --set apache_changed "true"
php -q $PANEL_PATH/panel/bin/daemon.php

#--- Firewall ?


#--- Restart all services to capture output messages, if any
if [[ "$OS" = "CentOs" && "$VER" == "7" ]]; then
    # CentOs7 does not return anything except redirection to systemctl :-(
    service() {
       echo "Restarting $1"
       systemctl restart "$1.service"
    }
fi

service "$DB_SERVICE" restart
service "$HTTP_SERVICE" restart
service postfix restart
service dovecot restart
service "$CRON_SERVICE" restart
service "$BIND_SERVICE" restart
service proftpd restart
service atd restart
service opendkim restart
service denyhosts restart

chkconfig httpd on
chkconfig mysqld on
chkconfig named on
chkconfig proftpd on
chkconfig postfix on
chkconfig dovecot on
chkconfig opendkim on
chkconfig denyhosts on


#--- Store the passwords for user reference
{
    echo "Server IP address      : $PUBLIC_IP"
    echo "Panel URL              : http://$PANEL_FQDN"
    echo "zadmin Password        : $zadminpassword"
    echo ""
    echo "MySQL Root Password    : $mysqlpassword"
    echo "MySQL Postfix Password : $postfixpassword"
    echo "MySQL ProFTPd Password : $proftpdpassword"
} >> /root/passwords.txt

#--- Advise the admin that FusionPanel is now installed and accessible.
echo "#########################################################" &>/dev/tty
echo " Congratulations FusionPanel has now been installed on your"   &>/dev/tty
echo " server. Please review the log file left in /root/ for "   &>/dev/tty
echo " any errors encountered during installation."              &>/dev/tty
echo ""                                                          &>/dev/tty
echo " Login to FusionPanel at http://$PANEL_FQDN"                   &>/dev/tty
echo " FusionPanel Username       : zadmin"                          &>/dev/tty
echo " FusionPanel Password       : $zadminpassword"                 &>/dev/tty
echo ""                                                          &>/dev/tty
echo " MySQL Root Password    : $mysqlpassword"                  &>/dev/tty
echo " MySQL Postfix Password : $postfixpassword"                &>/dev/tty
echo " MySQL ProFTPd Password : $proftpdpassword"                &>/dev/tty
echo "   (theses passwords are saved in /root/passwords.txt)"    &>/dev/tty
echo ""                                                          &>/dev/tty
echo "#########################################################" &>/dev/tty
echo "" &>/dev/tty

# Wait until the user have read before restarts the server...
if [[ "$INSTALL" != "auto" ]] ; then
    while true; do
        read -e -p "Restart your server now to complete the install (y/n)? " rsn
        case $rsn in
            [Yy]* ) break;;
            [Nn]* ) exit;
        esac
    done
    shutdown -r now
fi
