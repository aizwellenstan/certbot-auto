#!/bin/sh
#
# Download and run the latest release version of the Certbot client.
#
# NOTE: THIS SCRIPT IS AUTO-GENERATED AND SELF-UPDATING
#
# IF YOU WANT TO EDIT IT LOCALLY, *ALWAYS* RUN YOUR COPY WITH THE
# "--no-self-upgrade" FLAG
#
# IF YOU WANT TO SEND PULL REQUESTS, THE REAL SOURCE FOR THIS FILE IS
# letsencrypt-auto-source/letsencrypt-auto.template AND
# letsencrypt-auto-source/pieces/bootstrappers/*

set -e  # Work even if somebody does "sh thisscript.sh".

# Note: you can set XDG_DATA_HOME or VENV_PATH before running this script,
# if you want to change where the virtual environment will be installed

# HOME might not be defined when being run through something like systemd
if [ -z "$HOME" ]; then
  HOME=~root
fi
if [ -z "$XDG_DATA_HOME" ]; then
  XDG_DATA_HOME=~/.local/share
fi
if [ -z "$VENV_PATH" ]; then
  # We export these values so they are preserved properly if this script is
  # rerun with sudo/su where $HOME/$XDG_DATA_HOME may have a different value.
  export OLD_VENV_PATH="$XDG_DATA_HOME/letsencrypt"
  export VENV_PATH="/opt/eff.org/certbot/venv"
fi
VENV_BIN="$VENV_PATH/bin"
BOOTSTRAP_VERSION_PATH="$VENV_PATH/certbot-auto-bootstrap-version.txt"
LE_AUTO_VERSION="1.14.0"
BASENAME=$(basename $0)
USAGE="Usage: $BASENAME [OPTIONS]
A self-updating wrapper script for the Certbot ACME client. When run, updates
to both this script and certbot will be downloaded and installed. After
ensuring you have the latest versions installed, certbot will be invoked with
all arguments you have provided.

Help for certbot itself cannot be provided until it is installed.

  --debug                                   attempt experimental installation
  -h, --help                                print this help
  -n, --non-interactive, --noninteractive   run without asking for user input
  --no-bootstrap                            do not install OS dependencies
  --no-permissions-check                    do not warn about file system permissions
  --no-self-upgrade                         do not download updates
  --os-packages-only                        install OS dependencies and exit
  --install-only                            install certbot, upgrade if needed, and exit
  -v, --verbose                             provide more output
  -q, --quiet                               provide only update/error output;
                                            implies --non-interactive

All arguments are accepted and forwarded to the Certbot client when run."
export CERTBOT_AUTO="$0"

for arg in "$@" ; do
  case "$arg" in
    --debug)
      DEBUG=1;;
    --os-packages-only)
      OS_PACKAGES_ONLY=1;;
    --install-only)
      INSTALL_ONLY=1;;
    --no-self-upgrade)
      # Do not upgrade this script (also prevents client upgrades, because each
      # copy of the script pins a hash of the python client)
      NO_SELF_UPGRADE=1;;
    --no-permissions-check)
      NO_PERMISSIONS_CHECK=1;;
    --no-bootstrap)
      NO_BOOTSTRAP=1;;
    --help)
      HELP=1;;
    --noninteractive|--non-interactive)
      NONINTERACTIVE=1;;
    --quiet)
      QUIET=1;;
    renew)
      ASSUME_YES=1;;
    --verbose)
      VERBOSE=1;;
    -[!-]*)
      OPTIND=1
      while getopts ":hnvq" short_arg $arg; do
        case "$short_arg" in
          h)
            HELP=1;;
          n)
            NONINTERACTIVE=1;;
          q)
            QUIET=1;;
          v)
            VERBOSE=1;;
        esac
      done;;
  esac
done

if [ $BASENAME = "letsencrypt-auto" ]; then
  # letsencrypt-auto does not respect --help or --yes for backwards compatibility
  NONINTERACTIVE=1
  HELP=0
fi

# Set ASSUME_YES to 1 if QUIET or NONINTERACTIVE
if [ "$QUIET" = 1 -o "$NONINTERACTIVE" = 1 ]; then
  ASSUME_YES=1
fi

say() {
    if [  "$QUIET" != 1 ]; then
        echo "$@"
    fi
}

error() {
    echo "$@"
}

# Support for busybox and others where there is no "command",
# but "which" instead
if command -v command > /dev/null 2>&1 ; then
  export EXISTS="command -v"
elif which which > /dev/null 2>&1 ; then
  export EXISTS="which"
else
  error "Cannot find command nor which... please install one!"
  exit 1
fi

# Certbot itself needs root access for almost all modes of operation.
# certbot-auto needs root access to bootstrap OS dependencies and install
# Certbot at a protected path so it can be safely run as root. To accomplish
# this, this script will attempt to run itself as root if it doesn't have the
# necessary privileges by using `sudo` or falling back to `su` if it is not
# available. The mechanism used to obtain root access can be set explicitly by
# setting the environment variable LE_AUTO_SUDO to 'sudo', 'su', 'su_sudo',
# 'SuSudo', or '' as used below.

# Because the parameters in `su -c` has to be a string,
# we need to properly escape it.
SuSudo() {
  args=""
  # This `while` loop iterates over all parameters given to this function.
  # For each parameter, all `'` will be replace by `'"'"'`, and the escaped string
  # will be wrapped in a pair of `'`, then appended to `$args` string
  # For example, `echo "It's only 1\$\!"` will be escaped to:
  #   'echo' 'It'"'"'s only 1$!'
  #     │       │└┼┘│
  #     │       │ │ └── `'s only 1$!'` the literal string
  #     │       │ └── `\"'\"` is a single quote (as a string)
  #     │       └── `'It'`, to be concatenated with the strings following it
  #     └── `echo` wrapped in a pair of `'`, it's totally fine for the shell command itself
  while [ $# -ne 0 ]; do
    args="$args'$(printf "%s" "$1" | sed -e "s/'/'\"'\"'/g")' "
    shift
  done
  su root -c "$args"
}

# Sets the environment variable SUDO to be the name of the program or function
# to call to get root access. If this script already has root privleges, SUDO
# is set to an empty string. The value in SUDO should be run with the command
# to called with root privileges as arguments.
SetRootAuthMechanism() {
  SUDO=""
  if [ -n "${LE_AUTO_SUDO+x}" ]; then
    case "$LE_AUTO_SUDO" in
      SuSudo|su_sudo|su)
        SUDO=SuSudo
        ;;
      sudo)
        SUDO="sudo -E"
        ;;
      '')
        # If we're not running with root, don't check that this script can only
        # be modified by system users and groups.
        NO_PERMISSIONS_CHECK=1
        ;;
      *)
        error "Error: unknown root authorization mechanism '$LE_AUTO_SUDO'."
        exit 1
    esac
    say "Using preset root authorization mechanism '$LE_AUTO_SUDO'."
  else
    if test "`id -u`" -ne "0" ; then
      if $EXISTS sudo 1>/dev/null 2>&1; then
        SUDO="sudo -E"
      else
        say \"sudo\" is not available, will use \"su\" for installation steps...
        SUDO=SuSudo
      fi
    fi
  fi
}

if [ "$1" = "--cb-auto-has-root" ]; then
  shift 1
else
  SetRootAuthMechanism
  if [ -n "$SUDO" ]; then
    say "Requesting to rerun $0 with root privileges..."
    $SUDO "$0" --cb-auto-has-root "$@"
    exit 0
  fi
fi

# Runs this script again with the given arguments. --cb-auto-has-root is added
# to the command line arguments to ensure we don't try to acquire root a
# second time. After the script is rerun, we exit the current script.
RerunWithArgs() {
    "$0" --cb-auto-has-root "$@"
    exit 0
}

BootstrapMessage() {
  # Arguments: Platform name
  say "Bootstrapping dependencies for $1... (you can skip this with --no-bootstrap)"
}

ExperimentalBootstrap() {
  # Arguments: Platform name, bootstrap function name
  if [ "$DEBUG" = 1 ]; then
    if [ "$2" != "" ]; then
      BootstrapMessage $1
      $2
    fi
  else
    error "FATAL: $1 support is very experimental at present..."
    error "if you would like to work on improving it, please ensure you have backups"
    error "and then run this script again with the --debug flag!"
    error "Alternatively, you can install OS dependencies yourself and run this script"
    error "again with --no-bootstrap."
    exit 1
  fi
}

DeprecationBootstrap() {
  # Arguments: Platform name, bootstrap function name
  if [ "$DEBUG" = 1 ]; then
    if [ "$2" != "" ]; then
      BootstrapMessage $1
      $2
    fi
  else
    error "WARNING: certbot-auto support for this $1 is DEPRECATED!"
    error "Please visit certbot.eff.org to learn how to download a version of"
    error "Certbot that is packaged for your system. While an existing version"
    error "of certbot-auto may work currently, we have stopped supporting updating"
    error "system packages for your system. Please switch to a packaged version"
    error "as soon as possible."
    exit 1
  fi
}

MIN_PYTHON_2_VERSION="2.7"
MIN_PYVER2=$(echo "$MIN_PYTHON_2_VERSION" | sed 's/\.//')
MIN_PYTHON_3_VERSION="3.6"
MIN_PYVER3=$(echo "$MIN_PYTHON_3_VERSION" | sed 's/\.//')
# Sets LE_PYTHON to Python version string and PYVER to the first two
# digits of the python version.
# MIN_PYVER and MIN_PYTHON_VERSION are also set by this function, and their
# values depend on if we try to use Python 3 or Python 2.
DeterminePythonVersion() {
  # Arguments: "NOCRASH" if we shouldn't crash if we don't find a good python
  #
  # If no Python is found, PYVER is set to 0.
  if [ "$USE_PYTHON_3" = 1 ]; then
    MIN_PYVER=$MIN_PYVER3
    MIN_PYTHON_VERSION=$MIN_PYTHON_3_VERSION
    for LE_PYTHON in "$LE_PYTHON" python3; do
      # Break (while keeping the LE_PYTHON value) if found.
      $EXISTS "$LE_PYTHON" > /dev/null && break
    done
  else
    MIN_PYVER=$MIN_PYVER2
    MIN_PYTHON_VERSION=$MIN_PYTHON_2_VERSION
    for LE_PYTHON in "$LE_PYTHON" python2.7 python27 python2 python; do
      # Break (while keeping the LE_PYTHON value) if found.
      $EXISTS "$LE_PYTHON" > /dev/null && break
    done
  fi
  if [ "$?" != "0" ]; then
    if [ "$1" != "NOCRASH" ]; then
      error "Cannot find any Pythons; please install one!"
      exit 1
    else
      PYVER=0
      return 0
    fi
  fi

  PYVER=$("$LE_PYTHON" -V 2>&1 | cut -d" " -f 2 | cut -d. -f1,2 | sed 's/\.//')
  if [ "$PYVER" -lt "$MIN_PYVER" ]; then
    if [ "$1" != "NOCRASH" ]; then
      error "You have an ancient version of Python entombed in your operating system..."
      error "This isn't going to work; you'll need at least version $MIN_PYTHON_VERSION."
      exit 1
    fi
  fi
}

# If new packages are installed by BootstrapDebCommon below, this version
# number must be increased.
BOOTSTRAP_DEB_COMMON_VERSION=1

BootstrapDebCommon() {
  # Current version tested with:
  #
  # - Ubuntu
  #     - 14.04 (x64)
  #     - 15.04 (x64)
  # - Debian
  #     - 7.9 "wheezy" (x64)
  #     - sid (2015-10-21) (x64)

  # Past versions tested with:
  #
  # - Debian 8.0 "jessie" (x64)
  # - Raspbian 7.8 (armhf)

  # Believed not to work:
  #
  # - Debian 6.0.10 "squeeze" (x64)

  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='-qq'
  fi

  apt-get $QUIET_FLAG update || error apt-get update hit problems but continuing anyway...

  # virtualenv binary can be found in different packages depending on
  # distro version (#346)

  virtualenv=
  # virtual env is known to apt and is installable
  if apt-cache show virtualenv > /dev/null 2>&1 ; then
    if ! LC_ALL=C apt-cache --quiet=0 show virtualenv 2>&1 | grep -q 'No packages found'; then
      virtualenv="virtualenv"
    fi
  fi

  if apt-cache show python-virtualenv > /dev/null 2>&1; then
    virtualenv="$virtualenv python-virtualenv"
  fi

  augeas_pkg="libaugeas0 augeas-lenses"

  if [ "$ASSUME_YES" = 1 ]; then
    YES_FLAG="-y"
  fi

  apt-get install $QUIET_FLAG $YES_FLAG --no-install-recommends \
    python \
    python-dev \
    $virtualenv \
    gcc \
    $augeas_pkg \
    libssl-dev \
    openssl \
    libffi-dev \
    ca-certificates \


  if ! $EXISTS virtualenv > /dev/null ; then
    error Failed to install a working \"virtualenv\" command, exiting
    exit 1
  fi
}

# If new packages are installed by BootstrapRpmCommonBase below, version
# numbers in rpm_common.sh and rpm_python3.sh must be increased.

# Sets TOOL to the name of the package manager
# Sets appropriate values for YES_FLAG and QUIET_FLAG based on $ASSUME_YES and $QUIET_FLAG.
# Note: this function is called both while selecting the bootstrap scripts and
# during the actual bootstrap. Some things like prompting to user can be done in the latter
# case, but not in the former one.
InitializeRPMCommonBase() {
  if type dnf 2>/dev/null
  then
    TOOL=dnf
  elif type yum 2>/dev/null
  then
    TOOL=yum

  else
    error "Neither yum nor dnf found. Aborting bootstrap!"
    exit 1
  fi

  if [ "$ASSUME_YES" = 1 ]; then
    YES_FLAG="-y"
  fi
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='--quiet'
  fi
}

BootstrapRpmCommonBase() {
  # Arguments: whitespace-delimited python packages to install

  InitializeRPMCommonBase # This call is superfluous in practice

  pkgs="
    gcc
    augeas-libs
    openssl
    openssl-devel
    libffi-devel
    redhat-rpm-config
    ca-certificates
  "

  # Add the python packages
  pkgs="$pkgs
    $1
  "

  if $TOOL list installed "httpd" >/dev/null 2>&1; then
    pkgs="$pkgs
      mod_ssl
    "
  fi

  if ! $TOOL install $YES_FLAG $QUIET_FLAG $pkgs; then
    error "Could not install OS dependencies. Aborting bootstrap!"
    exit 1
  fi
}

# If new packages are installed by BootstrapRpmCommon below, this version
# number must be increased.
BOOTSTRAP_RPM_COMMON_VERSION=1

BootstrapRpmCommon() {
  # Tested with:
  #   - Fedora 20, 21, 22, 23 (x64)
  #   - Centos 7 (x64: on DigitalOcean droplet)
  #   - CentOS 7 Minimal install in a Hyper-V VM
  #   - CentOS 6

  InitializeRPMCommonBase

  # Most RPM distros use the "python" or "python-" naming convention.  Let's try that first.
  if $TOOL list python >/dev/null 2>&1; then
    python_pkgs="$python
      python-devel
      python-virtualenv
      python-tools
      python-pip
    "
  # Fedora 26 starts to use the prefix python2 for python2 based packages.
  # this elseif is theoretically for any Fedora over version 26:
  elif $TOOL list python2 >/dev/null 2>&1; then
    python_pkgs="$python2
      python2-libs
      python2-setuptools
      python2-devel
      python2-virtualenv
      python2-tools
      python2-pip
    "
  # Some distros and older versions of current distros use a "python27"
  # instead of the "python" or "python-" naming convention.
  else
    python_pkgs="$python27
      python27-devel
      python27-virtualenv
      python27-tools
      python27-pip
    "
  fi

  BootstrapRpmCommonBase "$python_pkgs"
}

# If new packages are installed by BootstrapRpmPython3 below, this version
# number must be increased.
BOOTSTRAP_RPM_PYTHON3_LEGACY_VERSION=1

# Checks if rh-python36 can be installed.
Python36SclIsAvailable() {
  InitializeRPMCommonBase >/dev/null 2>&1;

  if "${TOOL}" list rh-python36 >/dev/null 2>&1; then
    return 0
  fi
  if "${TOOL}" list centos-release-scl >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Try to enable rh-python36 from SCL if it is necessary and possible.
EnablePython36SCL() {
  if "$EXISTS" python3.6 > /dev/null 2> /dev/null; then
      return 0
  fi
  if [ ! -f /opt/rh/rh-python36/enable ]; then
      return 0
  fi
  set +e
  if ! . /opt/rh/rh-python36/enable; then
    error 'Unable to enable rh-python36!'
    exit 1
  fi
  set -e
}

# This bootstrap concerns old RedHat-based distributions that do not ship by default
# with Python 2.7, but only Python 2.6. We bootstrap them by enabling SCL and installing
# Python 3.6. Some of these distributions are: CentOS/RHEL/OL/SL 6.
BootstrapRpmPython3Legacy() {
  # Tested with:
  #   - CentOS 6

  InitializeRPMCommonBase

  if ! "${TOOL}" list rh-python36 >/dev/null 2>&1; then
    echo "To use Certbot on this operating system, packages from the SCL repository need to be installed."
    if ! "${TOOL}" list centos-release-scl >/dev/null 2>&1; then
      error "Enable the SCL repository and try running Certbot again."
      exit 1
    fi
    if [ "${ASSUME_YES}" = 1 ]; then
      /bin/echo -n "Enabling the SCL repository in 3 seconds... (Press Ctrl-C to cancel)"
      sleep 1s
      /bin/echo -ne "\e[0K\rEnabling the SCL repository in 2 seconds... (Press Ctrl-C to cancel)"
      sleep 1s
      /bin/echo -e "\e[0K\rEnabling the SCL repository in 1 second... (Press Ctrl-C to cancel)"
      sleep 1s
    fi
    if ! "${TOOL}" install "${YES_FLAG}" "${QUIET_FLAG}" centos-release-scl; then
      error "Could not enable SCL. Aborting bootstrap!"
      exit 1
    fi
  fi

  # CentOS 6 must use rh-python36 from SCL
  if "${TOOL}" list rh-python36 >/dev/null 2>&1; then
    python_pkgs="rh-python36-python
      rh-python36-python-virtualenv
      rh-python36-python-devel
    "
  else
    error "No supported Python package available to install. Aborting bootstrap!"
    exit 1
  fi

  BootstrapRpmCommonBase "${python_pkgs}"

  # Enable SCL rh-python36 after bootstrapping.
  EnablePython36SCL
}

# If new packages are installed by BootstrapRpmPython3 below, this version
# number must be increased.
BOOTSTRAP_RPM_PYTHON3_VERSION=1

BootstrapRpmPython3() {
  # Tested with:
  #   - Fedora 29

  InitializeRPMCommonBase

  # Fedora 29 must use python3-virtualenv
  if $TOOL list python3-virtualenv >/dev/null 2>&1; then
    python_pkgs="python3
      python3-virtualenv
      python3-devel
    "
  else
    error "No supported Python package available to install. Aborting bootstrap!"
    exit 1
  fi

  BootstrapRpmCommonBase "$python_pkgs"
}

# If new packages are installed by BootstrapSuseCommon below, this version
# number must be increased.
BOOTSTRAP_SUSE_COMMON_VERSION=1

BootstrapSuseCommon() {
  # SLE12 don't have python-virtualenv

  if [ "$ASSUME_YES" = 1 ]; then
    zypper_flags="-nq"
    install_flags="-l"
  fi

  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='-qq'
  fi

  if zypper search -x python-virtualenv >/dev/null 2>&1; then
    OPENSUSE_VIRTUALENV_PACKAGES="python-virtualenv"
  else
    # Since Leap 15.0 (and associated Tumbleweed version), python-virtualenv
    # is a source package, and python2-virtualenv must be used instead.
    # Also currently python2-setuptools is not a dependency of python2-virtualenv,
    # while it should be. Installing it explicitly until upstream fix.
    OPENSUSE_VIRTUALENV_PACKAGES="python2-virtualenv python2-setuptools"
  fi

  zypper $QUIET_FLAG $zypper_flags in $install_flags \
    python \
    python-devel \
    $OPENSUSE_VIRTUALENV_PACKAGES \
    gcc \
    augeas-lenses \
    libopenssl-devel \
    libffi-devel \
    ca-certificates
}

# If new packages are installed by BootstrapArchCommon below, this version
# number must be increased.
BOOTSTRAP_ARCH_COMMON_VERSION=1

BootstrapArchCommon() {
  # Tested with:
  #   - ArchLinux (x86_64)
  #
  # "python-virtualenv" is Python3, but "python2-virtualenv" provides
  # only "virtualenv2" binary, not "virtualenv".

  deps="
    python2
    python-virtualenv
    gcc
    augeas
    openssl
    libffi
    ca-certificates
    pkg-config
  "

  # pacman -T exits with 127 if there are missing dependencies
  missing=$(pacman -T $deps) || true

  if [ "$ASSUME_YES" = 1 ]; then
    noconfirm="--noconfirm"
  fi

  if [ "$missing" ]; then
    if [ "$QUIET" = 1 ]; then
      pacman -S --needed $missing $noconfirm > /dev/null
    else
      pacman -S --needed $missing $noconfirm
    fi
  fi
}

# If new packages are installed by BootstrapGentooCommon below, this version
# number must be increased.
BOOTSTRAP_GENTOO_COMMON_VERSION=1

BootstrapGentooCommon() {
  PACKAGES="
    dev-lang/python:2.7
    dev-python/virtualenv
    app-admin/augeas
    dev-libs/openssl
    dev-libs/libffi
    app-misc/ca-certificates
    virtual/pkgconfig"

  ASK_OPTION="--ask"
  if [ "$ASSUME_YES" = 1 ]; then
    ASK_OPTION=""
  fi

  case "$PACKAGE_MANAGER" in
    (paludis)
      cave resolve --preserve-world --keep-targets if-possible $PACKAGES -x
      ;;
    (pkgcore)
      pmerge --noreplace --oneshot $ASK_OPTION $PACKAGES
      ;;
    (portage|*)
      emerge --noreplace --oneshot $ASK_OPTION $PACKAGES
      ;;
  esac
}

# If new packages are installed by BootstrapFreeBsd below, this version number
# must be increased.
BOOTSTRAP_FREEBSD_VERSION=1

BootstrapFreeBsd() {
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG="--quiet"
  fi

  pkg install -Ay $QUIET_FLAG \
    python \
    py27-virtualenv \
    augeas \
    libffi
}

# If new packages are installed by BootstrapMac below, this version number must
# be increased.
BOOTSTRAP_MAC_VERSION=1

BootstrapMac() {
  if hash brew 2>/dev/null; then
    say "Using Homebrew to install dependencies..."
    pkgman=brew
    pkgcmd="brew install"
  elif hash port 2>/dev/null; then
    say "Using MacPorts to install dependencies..."
    pkgman=port
    pkgcmd="port install"
  else
    say "No Homebrew/MacPorts; installing Homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    pkgman=brew
    pkgcmd="brew install"
  fi

  $pkgcmd augeas
  if [ "$(which python)" = "/System/Library/Frameworks/Python.framework/Versions/2.7/bin/python" \
      -o "$(which python)" = "/usr/bin/python" ]; then
    # We want to avoid using the system Python because it requires root to use pip.
    # python.org, MacPorts or HomeBrew Python installations should all be OK.
    say "Installing python..."
    $pkgcmd python
  fi

  # Workaround for _dlopen not finding augeas on macOS
  if [ "$pkgman" = "port" ] && ! [ -e "/usr/local/lib/libaugeas.dylib" ] && [ -e "/opt/local/lib/libaugeas.dylib" ]; then
    say "Applying augeas workaround"
    mkdir -p /usr/local/lib/
    ln -s /opt/local/lib/libaugeas.dylib /usr/local/lib/
  fi

  if ! hash pip 2>/dev/null; then
    say "pip not installed"
    say "Installing pip..."
    curl --silent --show-error --retry 5 https://bootstrap.pypa.io/get-pip.py | python
  fi

  if ! hash virtualenv 2>/dev/null; then
    say "virtualenv not installed."
    say "Installing with pip..."
    pip install virtualenv
  fi
}

# If new packages are installed by BootstrapSmartOS below, this version number
# must be increased.
BOOTSTRAP_SMARTOS_VERSION=1

BootstrapSmartOS() {
  pkgin update
  pkgin -y install 'gcc49' 'py27-augeas' 'py27-virtualenv'
}

# If new packages are installed by BootstrapMageiaCommon below, this version
# number must be increased.
BOOTSTRAP_MAGEIA_COMMON_VERSION=1

BootstrapMageiaCommon() {
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='--quiet'
  fi

  if ! urpmi --force $QUIET_FLAG \
      python \
      libpython-devel \
      python-virtualenv
    then
      error "Could not install Python dependencies. Aborting bootstrap!"
      exit 1
  fi

  if ! urpmi --force $QUIET_FLAG \
      git \
      gcc \
      python-augeas \
      libopenssl-devel \
      libffi-devel \
      rootcerts
    then
      error "Could not install additional dependencies. Aborting bootstrap!"
      exit 1
    fi
}


# Set Bootstrap to the function that installs OS dependencies on this system
# and BOOTSTRAP_VERSION to the unique identifier for the current version of
# that function. If Bootstrap is set to a function that doesn't install any
# packages BOOTSTRAP_VERSION is not set.
if [ -f /etc/debian_version ]; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/mageia-release ]; then
  # Mageia has both /etc/mageia-release and /etc/redhat-release
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/redhat-release ]; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
  # Run DeterminePythonVersion to decide on the basis of available Python versions
  # whether to use 2.x or 3.x on RedHat-like systems.
  # Then, revert LE_PYTHON to its previous state.
  prev_le_python="$LE_PYTHON"
  unset LE_PYTHON
  DeterminePythonVersion "NOCRASH"

  RPM_DIST_NAME=`(. /etc/os-release 2> /dev/null && echo $ID) || echo "unknown"`

  if [ "$PYVER" -eq 26 -a $(uname -m) != 'x86_64' ]; then
    # 32 bits CentOS 6 and affiliates are not supported anymore by certbot-auto.
    DEPRECATED_OS=1
  fi

  # Set RPM_DIST_VERSION to VERSION_ID from /etc/os-release after splitting on
  # '.' characters (e.g. "8.0" becomes "8"). If the command exits with an
  # error, RPM_DIST_VERSION is set to "unknown".
  RPM_DIST_VERSION=$( (. /etc/os-release 2> /dev/null && echo "$VERSION_ID") | cut -d '.' -f1 || echo "unknown")

  # If RPM_DIST_VERSION is an empty string or it contains any nonnumeric
  # characters, the value is unexpected so we set RPM_DIST_VERSION to 0.
  if [ -z "$RPM_DIST_VERSION" ] || [ -n "$(echo "$RPM_DIST_VERSION" | tr -d '[0-9]')" ]; then
     RPM_DIST_VERSION=0
  fi

  # Handle legacy RPM distributions
  if [ "$PYVER" -eq 26 ]; then
    # Check if an automated bootstrap can be achieved on this system.
    if ! Python36SclIsAvailable; then
      INTERACTIVE_BOOTSTRAP=1
    fi

    USE_PYTHON_3=1

    # Try now to enable SCL rh-python36 for systems already bootstrapped
    # NB: EnablePython36SCL has been defined along with BootstrapRpmPython3Legacy in certbot-auto
    EnablePython36SCL
  else
    # Starting to Fedora 29, python2 is on a deprecation path. Let's move to python3 then.
    # RHEL 8 also uses python3 by default.
    if [ "$RPM_DIST_NAME" = "fedora" -a "$RPM_DIST_VERSION" -ge 29 ]; then
      RPM_USE_PYTHON_3=1
    elif [ "$RPM_DIST_NAME" = "rhel" -a "$RPM_DIST_VERSION" -ge 8 ]; then
      RPM_USE_PYTHON_3=1
    elif [ "$RPM_DIST_NAME" = "centos" -a "$RPM_DIST_VERSION" -ge 8 ]; then
      RPM_USE_PYTHON_3=1
    else
      RPM_USE_PYTHON_3=0
    fi

    if [ "$RPM_USE_PYTHON_3" = 1 ]; then
      USE_PYTHON_3=1
    fi
  fi

  LE_PYTHON="$prev_le_python"
elif [ -f /etc/os-release ] && `grep -q openSUSE /etc/os-release` ; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/arch-release ]; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/manjaro-release ]; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/gentoo-release ]; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif uname | grep -iq FreeBSD ; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif uname | grep -iq Darwin ; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/issue ] && grep -iq "Amazon Linux" /etc/issue ; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
elif [ -f /etc/product ] && grep -q "Joyent Instance" /etc/product ; then
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
else
  DEPRECATED_OS=1
  NO_SELF_UPGRADE=1
fi

# We handle this case after determining the normal bootstrap version to allow
# variables like USE_PYTHON_3 to be properly set. As described above, if the
# Bootstrap function doesn't install any packages, BOOTSTRAP_VERSION should not
# be set so we unset it here.
if [ "$NO_BOOTSTRAP" = 1 ]; then
  Bootstrap() {
    :
  }
  unset BOOTSTRAP_VERSION
fi

if [ "$DEPRECATED_OS" = 1 ]; then
  Bootstrap() {
    error "Skipping bootstrap because certbot-auto is deprecated on this system."
  }
  unset BOOTSTRAP_VERSION
fi

# Sets PREV_BOOTSTRAP_VERSION to the identifier for the bootstrap script used
# to install OS dependencies on this system. PREV_BOOTSTRAP_VERSION isn't set
# if it is unknown how OS dependencies were installed on this system.
SetPrevBootstrapVersion() {
  if [ -f $BOOTSTRAP_VERSION_PATH ]; then
    PREV_BOOTSTRAP_VERSION=$(cat "$BOOTSTRAP_VERSION_PATH")
  # The list below only contains bootstrap version strings that existed before
  # we started writing them to disk.
  #
  # DO NOT MODIFY THIS LIST UNLESS YOU KNOW WHAT YOU'RE DOING!
  elif grep -Fqx "$BOOTSTRAP_VERSION" << "UNLIKELY_EOF"
BootstrapDebCommon 1
BootstrapMageiaCommon 1
BootstrapRpmCommon 1
BootstrapSuseCommon 1
BootstrapArchCommon 1
BootstrapGentooCommon 1
BootstrapFreeBsd 1
BootstrapMac 1
BootstrapSmartOS 1
UNLIKELY_EOF
  then
    # If there's no bootstrap version saved to disk, but the currently selected
    # bootstrap script is from before we started saving the version number,
    # return the currently selected version to prevent us from rebootstrapping
    # unnecessarily.
    PREV_BOOTSTRAP_VERSION="$BOOTSTRAP_VERSION"
  fi
}

TempDir() {
  mktemp -d 2>/dev/null || mktemp -d -t 'le'  # Linux || macOS
}

# Returns 0 if a letsencrypt installation exists at $OLD_VENV_PATH, otherwise,
# returns a non-zero number.
OldVenvExists() {
    [ -n "$OLD_VENV_PATH" -a -f "$OLD_VENV_PATH/bin/letsencrypt" ]
}

# Given python path, version 1 and version 2, check if version 1 is outdated compared to version 2.
# An unofficial version provided as version 1 (eg. 0.28.0.dev0) will be treated
# specifically by printing "UNOFFICIAL". Otherwise, print "OUTDATED" if version 1
# is outdated, and "UP_TO_DATE" if not.
# This function relies only on installed python environment (2.x or 3.x) by certbot-auto.
CompareVersions() {
    "$1" - "$2" "$3" << "UNLIKELY_EOF"
import sys
from distutils.version import StrictVersion

try:
    current = StrictVersion(sys.argv[1])
except ValueError:
    sys.stdout.write('UNOFFICIAL')
    sys.exit()

try:
    remote = StrictVersion(sys.argv[2])
except ValueError:
    sys.stdout.write('UP_TO_DATE')
    sys.exit()

if current < remote:
    sys.stdout.write('OUTDATED')
else:
    sys.stdout.write('UP_TO_DATE')
UNLIKELY_EOF
}

# Create a new virtual environment for Certbot. It will overwrite any existing one.
# Parameters: LE_PYTHON, VENV_PATH, PYVER, VERBOSE
CreateVenv() {
    "$1" - "$2" "$3" "$4" << "UNLIKELY_EOF"
#!/usr/bin/env python
import os
import shutil
import subprocess
import sys


def create_venv(venv_path, pyver, verbose):
    if os.path.exists(venv_path):
        shutil.rmtree(venv_path)

    stdout = sys.stdout if verbose == '1' else open(os.devnull, 'w')

    if int(pyver) <= 27:
        # Use virtualenv binary
        environ = os.environ.copy()
        environ['VIRTUALENV_NO_DOWNLOAD'] = '1'
        command = ['virtualenv', '--no-site-packages', '--python', sys.executable, venv_path]
        subprocess.check_call(command, stdout=stdout, env=environ)
    else:
        # Use embedded venv module in Python 3
        command = [sys.executable, '-m', 'venv', venv_path]
        subprocess.check_call(command, stdout=stdout)


if __name__ == '__main__':
    create_venv(*sys.argv[1:])

UNLIKELY_EOF
}

# Check that the given PATH_TO_CHECK has secured permissions.
# Parameters: LE_PYTHON, PATH_TO_CHECK
CheckPathPermissions() {
    "$1" - "$2" << "UNLIKELY_EOF"
"""Verifies certbot-auto cannot be modified by unprivileged users.

This script takes the path to certbot-auto as its only command line
argument.  It then checks that the file can only be modified by uid/gid
< 1000 and if other users can modify the file, it prints a warning with
a suggestion on how to solve the problem.

Permissions on symlinks in the absolute path of certbot-auto are ignored
and only the canonical path to certbot-auto is checked. There could be
permissions problems due to the symlinks that are unreported by this
script, however, issues like this were not caused by our documentation
and are ignored for the sake of simplicity.

All warnings are printed to stdout rather than stderr so all stderr
output from this script can be suppressed to avoid printing messages if
this script fails for some reason.

"""
from __future__ import print_function

import os
import stat
import sys


FORUM_POST_URL = 'https://community.letsencrypt.org/t/certbot-auto-deployment-best-practices/91979/'


def has_safe_permissions(path):
    """Returns True if the given path has secure permissions.

    The permissions are considered safe if the file is only writable by
    uid/gid < 1000.

    The reason we allow more IDs than 0 is because on some systems such
    as Debian, system users/groups other than uid/gid 0 are used for the
    path we recommend in our instructions which is /usr/local/bin.  1000
    was chosen because on Debian 0-999 is reserved for system IDs[1] and
    on RHEL either 0-499 or 0-999 is reserved depending on the
    version[2][3]. Due to these differences across different OSes, this
    detection isn't perfect so we only determine permissions are
    insecure when we can be reasonably confident there is a problem
    regardless of the underlying OS.

    [1] https://www.debian.org/doc/debian-policy/ch-opersys.html#uid-and-gid-classes
    [2] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/deployment_guide/ch-managing_users_and_groups
    [3] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/ch-managing_users_and_groups

    :param str path: filesystem path to check
    :returns: True if the path has secure permissions, otherwise, False
    :rtype: bool

    """
    # os.stat follows symlinks before obtaining information about a file.
    stat_result = os.stat(path)
    if stat_result.st_mode & stat.S_IWOTH:
        return False
    if stat_result.st_mode & stat.S_IWGRP and stat_result.st_gid >= 1000:
        return False
    if stat_result.st_mode & stat.S_IWUSR and stat_result.st_uid >= 1000:
        return False
    return True


def main(certbot_auto_path):
    current_path = os.path.realpath(certbot_auto_path)
    last_path = None
    permissions_ok = True
    # This loop makes use of the fact that os.path.dirname('/') == '/'.
    while current_path != last_path and permissions_ok:
        permissions_ok = has_safe_permissions(current_path)
        last_path = current_path
        current_path = os.path.dirname(current_path)

    if not permissions_ok:
        print('{0} has insecure permissions!'.format(certbot_auto_path))
        print('To learn how to fix them, visit {0}'.format(FORUM_POST_URL))


if __name__ == '__main__':
    main(sys.argv[1])

UNLIKELY_EOF
}

if [ "$1" = "--le-auto-phase2" ]; then
  # Phase 2: Create venv, install LE, and run.

  shift 1  # the --le-auto-phase2 arg

  if [ "$DEPRECATED_OS" = 1 ]; then
    # Phase 2 damage control mode for deprecated OSes.
    # In this situation, we bypass any bootstrap or certbot venv setup.
    error "Your system is not supported by certbot-auto anymore."

    if [ ! -d "$VENV_PATH" ] && OldVenvExists; then
      VENV_BIN="$OLD_VENV_PATH/bin"
    fi

    if [ -f "$VENV_BIN/letsencrypt" -a "$INSTALL_ONLY" != 1 ]; then
      error "certbot-auto and its Certbot installation will no longer receive updates."
      error "You will not receive any bug fixes including those fixing server compatibility"
      error "or security problems."
      error "Please visit https://certbot.eff.org/ to check for other alternatives."
      "$VENV_BIN/letsencrypt" "$@"
      exit 0
    else
      error "Certbot cannot be installed."
      error "Please visit https://certbot.eff.org/ to check for other alternatives."
      exit 1
    fi
  fi

  SetPrevBootstrapVersion

  if [ -z "$PHASE_1_VERSION" -a "$USE_PYTHON_3" = 1 ]; then
    unset LE_PYTHON
  fi

  INSTALLED_VERSION="none"
  if [ -d "$VENV_PATH" ] || OldVenvExists; then
    # If the selected Bootstrap function isn't a noop and it differs from the
    # previously used version
    if [ -n "$BOOTSTRAP_VERSION" -a "$BOOTSTRAP_VERSION" != "$PREV_BOOTSTRAP_VERSION" ]; then
      # Check if we can rebootstrap without manual user intervention: this requires that
      # certbot-auto is in non-interactive mode AND selected bootstrap does not claim to
      # require a manual user intervention.
      if [ "$NONINTERACTIVE" = 1 -a "$INTERACTIVE_BOOTSTRAP" != 1 ]; then
        CAN_REBOOTSTRAP=1
      fi
      # Check if rebootstrap can be done non-interactively and current shell is non-interactive
      # (true if stdin and stdout are not attached to a terminal).
      if [ \( "$CAN_REBOOTSTRAP" = 1 \) -o \( \( -t 0 \) -a \( -t 1 \) \) ]; then
        if [ -d "$VENV_PATH" ]; then
          rm -rf "$VENV_PATH"
        fi
        # In the case the old venv was just a symlink to the new one,
        # OldVenvExists is now false because we deleted the venv at VENV_PATH.
        if OldVenvExists; then
          rm -rf "$OLD_VENV_PATH"
          ln -s "$VENV_PATH" "$OLD_VENV_PATH"
        fi
        RerunWithArgs "$@"
      # Otherwise bootstrap needs to be done manually by the user.
      else
        # If it is because bootstrapping is interactive, --non-interactive will be of no use.
        if [ "$INTERACTIVE_BOOTSTRAP" = 1 ]; then
          error "Skipping upgrade because new OS dependencies may need to be installed."
          error "This requires manual user intervention: please run this script again manually."
        # If this is because of the environment (eg. non interactive shell without
        # --non-interactive flag set), help the user in that direction.
        else
          error "Skipping upgrade because new OS dependencies may need to be installed."
          error
          error "To upgrade to a newer version, please run this script again manually so you can"
          error "approve changes or with --non-interactive on the command line to automatically"
          error "install any required packages."
        fi
        # Set INSTALLED_VERSION to be the same so we don't update the venv
        INSTALLED_VERSION="$LE_AUTO_VERSION"
        # Continue to use OLD_VENV_PATH if the new venv doesn't exist
        if [ ! -d "$VENV_PATH" ]; then
          VENV_BIN="$OLD_VENV_PATH/bin"
        fi
      fi
    elif [ -f "$VENV_BIN/letsencrypt" ]; then
      # --version output ran through grep due to python-cryptography DeprecationWarnings
      # grep for both certbot and letsencrypt until certbot and shim packages have been released
      INSTALLED_VERSION=$("$VENV_BIN/letsencrypt" --version 2>&1 | grep "^certbot\|^letsencrypt" | cut -d " " -f 2)
      if [ -z "$INSTALLED_VERSION" ]; then
          error "Error: couldn't get currently installed version for $VENV_BIN/letsencrypt: " 1>&2
          "$VENV_BIN/letsencrypt" --version
          exit 1
      fi
    fi
  fi

  if [ "$LE_AUTO_VERSION" != "$INSTALLED_VERSION" ]; then
    say "Creating virtual environment..."
    DeterminePythonVersion
    CreateVenv "$LE_PYTHON" "$VENV_PATH" "$PYVER" "$VERBOSE"

    if [ -n "$BOOTSTRAP_VERSION" ]; then
      echo "$BOOTSTRAP_VERSION" > "$BOOTSTRAP_VERSION_PATH"
    elif [ -n "$PREV_BOOTSTRAP_VERSION" ]; then
      echo "$PREV_BOOTSTRAP_VERSION" > "$BOOTSTRAP_VERSION_PATH"
    fi

    say "Installing Python packages..."
    TEMP_DIR=$(TempDir)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    # There is no $ interpolation due to quotes on starting heredoc delimiter.
    # -------------------------------------------------------------------------
    cat << "UNLIKELY_EOF" > "$TEMP_DIR/letsencrypt-auto-requirements.txt"
# This is the flattened list of packages certbot-auto installs.
# To generate this, do (with docker and package hashin installed):
# ```
# letsencrypt-auto-source/rebuild_dependencies.py \
#   letsencrypt-auto-source/pieces/dependency-requirements.txt
# ```
# If you want to update a single dependency, run commands similar to these:
# ```
# pip install hashin
# hashin -r dependency-requirements.txt cryptography==1.5.2
# ```
ConfigArgParse==1.2.3 \
    --hash=sha256:edd17be986d5c1ba2e307150b8e5f5107aba125f3574dddd02c85d5cdcfd37dc
certifi==2020.4.5.1 \
    --hash=sha256:1d987a998c75633c40847cc966fcf5904906c920a7f17ef374f5aa4282abd304 \
    --hash=sha256:51fcb31174be6e6664c5f69e3e1691a2d72a1a12e90f872cbdb1567eb47b6519
cffi==1.14.0 \
    --hash=sha256:001bf3242a1bb04d985d63e138230802c6c8d4db3668fb545fb5005ddf5bb5ff \
    --hash=sha256:00789914be39dffba161cfc5be31b55775de5ba2235fe49aa28c148236c4e06b \
    --hash=sha256:028a579fc9aed3af38f4892bdcc7390508adabc30c6af4a6e4f611b0c680e6ac \
    --hash=sha256:14491a910663bf9f13ddf2bc8f60562d6bc5315c1f09c704937ef17293fb85b0 \
    --hash=sha256:1cae98a7054b5c9391eb3249b86e0e99ab1e02bb0cc0575da191aedadbdf4384 \
    --hash=sha256:2089ed025da3919d2e75a4d963d008330c96751127dd6f73c8dc0c65041b4c26 \
    --hash=sha256:2d384f4a127a15ba701207f7639d94106693b6cd64173d6c8988e2c25f3ac2b6 \
    --hash=sha256:337d448e5a725bba2d8293c48d9353fc68d0e9e4088d62a9571def317797522b \
    --hash=sha256:399aed636c7d3749bbed55bc907c3288cb43c65c4389964ad5ff849b6370603e \
    --hash=sha256:3b911c2dbd4f423b4c4fcca138cadde747abdb20d196c4a48708b8a2d32b16dd \
    --hash=sha256:3d311bcc4a41408cf5854f06ef2c5cab88f9fded37a3b95936c9879c1640d4c2 \
    --hash=sha256:62ae9af2d069ea2698bf536dcfe1e4eed9090211dbaafeeedf5cb6c41b352f66 \
    --hash=sha256:66e41db66b47d0d8672d8ed2708ba91b2f2524ece3dee48b5dfb36be8c2f21dc \
    --hash=sha256:675686925a9fb403edba0114db74e741d8181683dcf216be697d208857e04ca8 \
    --hash=sha256:7e63cbcf2429a8dbfe48dcc2322d5f2220b77b2e17b7ba023d6166d84655da55 \
    --hash=sha256:8a6c688fefb4e1cd56feb6c511984a6c4f7ec7d2a1ff31a10254f3c817054ae4 \
    --hash=sha256:8c0ffc886aea5df6a1762d0019e9cb05f825d0eec1f520c51be9d198701daee5 \
    --hash=sha256:95cd16d3dee553f882540c1ffe331d085c9e629499ceadfbda4d4fde635f4b7d \
    --hash=sha256:99f748a7e71ff382613b4e1acc0ac83bf7ad167fb3802e35e90d9763daba4d78 \
    --hash=sha256:b8c78301cefcf5fd914aad35d3c04c2b21ce8629b5e4f4e45ae6812e461910fa \
    --hash=sha256:c420917b188a5582a56d8b93bdd8e0f6eca08c84ff623a4c16e809152cd35793 \
    --hash=sha256:c43866529f2f06fe0edc6246eb4faa34f03fe88b64a0a9a942561c8e22f4b71f \
    --hash=sha256:cab50b8c2250b46fe738c77dbd25ce017d5e6fb35d3407606e7a4180656a5a6a \
    --hash=sha256:cef128cb4d5e0b3493f058f10ce32365972c554572ff821e175dbc6f8ff6924f \
    --hash=sha256:cf16e3cf6c0a5fdd9bc10c21687e19d29ad1fe863372b5543deaec1039581a30 \
    --hash=sha256:e56c744aa6ff427a607763346e4170629caf7e48ead6921745986db3692f987f \
    --hash=sha256:e577934fc5f8779c554639376beeaa5657d54349096ef24abe8c74c5d9c117c3 \
    --hash=sha256:f2b0fa0c01d8a0c7483afd9f31d7ecf2d71760ca24499c8697aeb5ca37dc090c
chardet==3.0.4 \
    --hash=sha256:84ab92ed1c4d4f16916e05906b6b75a6c0fb5db821cc65e70cbd64a3e2a5eaae \
    --hash=sha256:fc323ffcaeaed0e0a02bf4d117757b98aed530d9ed4531e3e15460124c106691
configobj==5.0.6 \
    --hash=sha256:a2f5650770e1c87fb335af19a9b7eb73fc05ccf22144eb68db7d00cd2bcb0902
cryptography==2.8 \
    --hash=sha256:02079a6addc7b5140ba0825f542c0869ff4df9a69c360e339ecead5baefa843c \
    --hash=sha256:1df22371fbf2004c6f64e927668734070a8953362cd8370ddd336774d6743595 \
    --hash=sha256:369d2346db5934345787451504853ad9d342d7f721ae82d098083e1f49a582ad \
    --hash=sha256:3cda1f0ed8747339bbdf71b9f38ca74c7b592f24f65cdb3ab3765e4b02871651 \
    --hash=sha256:44ff04138935882fef7c686878e1c8fd80a723161ad6a98da31e14b7553170c2 \
    --hash=sha256:4b1030728872c59687badcca1e225a9103440e467c17d6d1730ab3d2d64bfeff \
    --hash=sha256:58363dbd966afb4f89b3b11dfb8ff200058fbc3b947507675c19ceb46104b48d \
    --hash=sha256:6ec280fb24d27e3d97aa731e16207d58bd8ae94ef6eab97249a2afe4ba643d42 \
    --hash=sha256:7270a6c29199adc1297776937a05b59720e8a782531f1f122f2eb8467f9aab4d \
    --hash=sha256:73fd30c57fa2d0a1d7a49c561c40c2f79c7d6c374cc7750e9ac7c99176f6428e \
    --hash=sha256:7f09806ed4fbea8f51585231ba742b58cbcfbfe823ea197d8c89a5e433c7e912 \
    --hash=sha256:90df0cc93e1f8d2fba8365fb59a858f51a11a394d64dbf3ef844f783844cc793 \
    --hash=sha256:971221ed40f058f5662a604bd1ae6e4521d84e6cad0b7b170564cc34169c8f13 \
    --hash=sha256:a518c153a2b5ed6b8cc03f7ae79d5ffad7315ad4569b2d5333a13c38d64bd8d7 \
    --hash=sha256:b0de590a8b0979649ebeef8bb9f54394d3a41f66c5584fff4220901739b6b2f0 \
    --hash=sha256:b43f53f29816ba1db8525f006fa6f49292e9b029554b3eb56a189a70f2a40879 \
    --hash=sha256:d31402aad60ed889c7e57934a03477b572a03af7794fa8fb1780f21ea8f6551f \
    --hash=sha256:de96157ec73458a7f14e3d26f17f8128c959084931e8997b9e655a39c8fde9f9 \
    --hash=sha256:df6b4dca2e11865e6cfbfb708e800efb18370f5a46fd601d3755bc7f85b3a8a2 \
    --hash=sha256:ecadccc7ba52193963c0475ac9f6fa28ac01e01349a2ca48509667ef41ffd2cf \
    --hash=sha256:fb81c17e0ebe3358486cd8cc3ad78adbae58af12fc2bf2bc0bb84e8090fa5ce8
distro==1.5.0 \
    --hash=sha256:0e58756ae38fbd8fc3020d54badb8eae17c5b9dcbed388b17bb55b8a5928df92 \
    --hash=sha256:df74eed763e18d10d0da624258524ae80486432cd17392d9c3d96f5e83cd2799
enum34==1.1.10; python_version < '3.4' \
    --hash=sha256:a98a201d6de3f2ab3db284e70a33b0f896fbf35f8086594e8c9e74b909058d53 \
    --hash=sha256:c3858660960c984d6ab0ebad691265180da2b43f07e061c0f8dca9ef3cffd328 \
    --hash=sha256:cce6a7477ed816bd2542d03d53db9f0db935dd013b70f336a95c73979289f248
funcsigs==1.0.2 \
    --hash=sha256:330cc27ccbf7f1e992e69fef78261dc7c6569012cf397db8d3de0234e6c937ca \
    --hash=sha256:a7bb0f2cf3a3fd1ab2732cb49eba4252c2af4240442415b4abce3b87022a8f50
idna==2.9 \
    --hash=sha256:7588d1c14ae4c77d74036e8c22ff447b26d0fde8f007354fd48a7814db15b7cb \
    --hash=sha256:a068a21ceac8a4d63dbfd964670474107f541babbd2250d61922f029858365fa
ipaddress==1.0.23 \
    --hash=sha256:6e0f4a39e66cb5bb9a137b00276a2eff74f93b71dcbdad6f10ff7df9d3557fcc \
    --hash=sha256:b7f8e0369580bb4a24d5ba1d7cc29660a4a6987763faf1d8a8046830e020e7e2
josepy==1.3.0 \
    --hash=sha256:c341ffa403399b18e9eae9012f804843045764d1390f9cb4648980a7569b1619 \
    --hash=sha256:e54882c64be12a2a76533f73d33cba9e331950fda9e2731e843490b774e7a01c
mock==1.3.0 \
    --hash=sha256:1e247dbecc6ce057299eb7ee019ad68314bb93152e81d9a6110d35f4d5eca0f6 \
    --hash=sha256:3f573a18be94de886d1191f27c168427ef693e8dcfcecf95b170577b2eb69cbb
parsedatetime==2.5 \
    --hash=sha256:3b835fc54e472c17ef447be37458b400e3fefdf14bb1ffdedb5d2c853acf4ba1 \
    --hash=sha256:d2e9ddb1e463de871d32088a3f3cea3dc8282b1b2800e081bd0ef86900451667
pbr==5.4.5 \
    --hash=sha256:07f558fece33b05caf857474a366dfcc00562bca13dd8b47b2b3e22d9f9bf55c \
    --hash=sha256:579170e23f8e0c2f24b0de612f71f648eccb79fb1322c814ae6b3c07b5ba23e8
pyOpenSSL==19.1.0 \
    --hash=sha256:621880965a720b8ece2f1b2f54ea2071966ab00e2970ad2ce11d596102063504 \
    --hash=sha256:9a24494b2602aaf402be5c9e30a0b82d4a5c67528fe8fb475e3f3bc00dd69507
pyRFC3339==1.1 \
    --hash=sha256:67196cb83b470709c580bb4738b83165e67c6cc60e1f2e4f286cfcb402a926f4 \
    --hash=sha256:81b8cbe1519cdb79bed04910dd6fa4e181faf8c88dff1e1b987b5f7ab23a5b1a
pycparser==2.20 \
    --hash=sha256:2d475327684562c3a96cc71adf7dc8c4f0565175cf86b6d7a404ff4c771f15f0 \
    --hash=sha256:7582ad22678f0fcd81102833f60ef8d0e57288b6b5fb00323d101be910e35705
pyparsing==2.4.7 \
    --hash=sha256:c203ec8783bf771a155b207279b9bccb8dea02d8f0c9e5f8ead507bc3246ecc1 \
    --hash=sha256:ef9d7589ef3c200abe66653d3f1ab1033c3c419ae9b9bdb1240a85b024efc88b
python-augeas==0.5.0 \
    --hash=sha256:67d59d66cdba8d624e0389b87b2a83a176f21f16a87553b50f5703b23f29bac2
pytz==2020.1 \
    --hash=sha256:a494d53b6d39c3c6e44c3bec237336e14305e4f29bbf800b599253057fbb79ed \
    --hash=sha256:c35965d010ce31b23eeb663ed3cc8c906275d6be1a34393a1d73a41febf4a048
requests==2.23.0 \
    --hash=sha256:43999036bfa82904b6af1d99e4882b560e5e2c68e5c4b0aa03b655f3d7d73fee \
    --hash=sha256:b3f43d496c6daba4493e7c431722aeb7dbc6288f52a6e04e7b6023b0247817e6
requests-toolbelt==0.9.1 \
    --hash=sha256:380606e1d10dc85c3bd47bf5a6095f815ec007be7a8b69c878507068df059e6f \
    --hash=sha256:968089d4584ad4ad7c171454f0a5c6dac23971e9472521ea3b6d49d610aa6fc0
six==1.15.0 \
    --hash=sha256:30639c035cdb23534cd4aa2dd52c3bf48f06e5f4a941509c8bafd8ce11080259 \
    --hash=sha256:8b74bedcbbbaca38ff6d7491d76f2b06b3592611af620f8426e82dddb04a5ced
urllib3==1.25.9 \
    --hash=sha256:3018294ebefce6572a474f0604c2021e33b3fd8006ecd11d62107a5d2a963527 \
    --hash=sha256:88206b0eb87e6d677d424843ac5209e3fb9d0190d0ee169599165ec25e9d9115
zope.component==4.6.1 \
    --hash=sha256:bfbe55d4a93e70a78b10edc3aad4de31bb8860919b7cbd8d66f717f7d7b279ac \
    --hash=sha256:d9c7c27673d787faff8a83797ce34d6ebcae26a370e25bddb465ac2182766aca
zope.deferredimport==4.3.1 \
    --hash=sha256:57b2345e7b5eef47efcd4f634ff16c93e4265de3dcf325afc7315ade48d909e1 \
    --hash=sha256:9a0c211df44aa95f1c4e6d2626f90b400f56989180d3ef96032d708da3d23e0a
zope.deprecation==4.4.0 \
    --hash=sha256:0d453338f04bacf91bbfba545d8bcdf529aa829e67b705eac8c1a7fdce66e2df \
    --hash=sha256:f1480b74995958b24ce37b0ef04d3663d2683e5d6debc96726eff18acf4ea113
zope.event==4.4 \
    --hash=sha256:69c27debad9bdacd9ce9b735dad382142281ac770c4a432b533d6d65c4614bcf \
    --hash=sha256:d8e97d165fd5a0997b45f5303ae11ea3338becfe68c401dd88ffd2113fe5cae7
zope.hookable==5.0.1 \
    --hash=sha256:0194b9b9e7f614abba60c90b231908861036578297515d3d6508eb10190f266d \
    --hash=sha256:0c2977473918bdefc6fa8dfb311f154e7f13c6133957fe649704deca79b92093 \
    --hash=sha256:17b8bdb3b77e03a152ca0d5ca185a7ae0156f5e5a2dbddf538676633a1f7380f \
    --hash=sha256:29d07681a78042cdd15b268ae9decffed9ace68a53eebeb61d65ae931d158841 \
    --hash=sha256:36fb1b35d1150267cb0543a1ddd950c0bc2c75ed0e6e92e3aaa6ac2e29416cb7 \
    --hash=sha256:3aed60c2bb5e812bbf9295c70f25b17ac37c233f30447a96c67913ba5073642f \
    --hash=sha256:3cac1565cc768911e72ca9ec4ddf5c5109e1fef0104f19f06649cf1874943b60 \
    --hash=sha256:3d4bc0cc4a37c3cd3081063142eeb2125511db3c13f6dc932d899c512690378e \
    --hash=sha256:3f73096f27b8c28be53ffb6604f7b570fbbb82f273c6febe5f58119009b59898 \
    --hash=sha256:522d1153d93f2d48aa0bd9fb778d8d4500be2e4dcf86c3150768f0e3adbbc4ef \
    --hash=sha256:523d2928fb7377bbdbc9af9c0b14ad73e6eaf226349f105733bdae27efd15b5a \
    --hash=sha256:5848309d4fc5c02150a45e8f8d2227e5bfda386a508bbd3160fed7c633c5a2fa \
    --hash=sha256:6781f86e6d54a110980a76e761eb54590630fd2af2a17d7edf02a079d2646c1d \
    --hash=sha256:6fd27921ebf3aaa945fa25d790f1f2046204f24dba4946f82f5f0a442577c3e9 \
    --hash=sha256:70d581862863f6bf9e175e85c9d70c2d7155f53fb04dcdb2f73cf288ca559a53 \
    --hash=sha256:81867c23b0dc66c8366f351d00923f2bc5902820a24c2534dfd7bf01a5879963 \
    --hash=sha256:81db29edadcbb740cd2716c95a297893a546ed89db1bfe9110168732d7f0afdd \
    --hash=sha256:86bd12624068cea60860a0759af5e2c3adc89c12aef6f71cf12f577e28deefe3 \
    --hash=sha256:9c184d8f9f7a76e1ced99855ccf390ffdd0ec3765e5cbf7b9cada600accc0a1e \
    --hash=sha256:acc789e8c29c13555e43fe4bf9fcd15a65512c9645e97bbaa5602e3201252b02 \
    --hash=sha256:afaa740206b7660d4cc3b8f120426c85761f51379af7a5b05451f624ad12b0af \
    --hash=sha256:b5f5fa323f878bb16eae68ea1ba7f6c0419d4695d0248bed4b18f51d7ce5ab85 \
    --hash=sha256:bd89e0e2c67bf4ac3aca2a19702b1a37269fb1923827f68324ac2e7afd6e3406 \
    --hash=sha256:c212de743283ec0735db24ec6ad913758df3af1b7217550ff270038062afd6ae \
    --hash=sha256:ca553f524293a0bdea05e7f44c3e685e4b7b022cb37d87bc4a3efa0f86587a8d \
    --hash=sha256:cab67065a3db92f636128d3157cc5424a145f82d96fb47159c539132833a6d36 \
    --hash=sha256:d3b3b3eedfdbf6b02898216e85aa6baf50207f4378a2a6803d6d47650cd37031 \
    --hash=sha256:d9f4a5a72f40256b686d31c5c0b1fde503172307beb12c1568296e76118e402c \
    --hash=sha256:df5067d87aaa111ed5d050e1ee853ba284969497f91806efd42425f5348f1c06 \
    --hash=sha256:e2587644812c6138f05b8a41594a8337c6790e3baf9a01915e52438c13fc6bef \
    --hash=sha256:e27fd877662db94f897f3fd532ef211ca4901eb1a70ba456f15c0866a985464a \
    --hash=sha256:e427ebbdd223c72e06ba94c004bb04e996c84dec8a0fa84e837556ae145c439e \
    --hash=sha256:e583ad4309c203ef75a09d43434cf9c2b4fa247997ecb0dcad769982c39411c7 \
    --hash=sha256:e760b2bc8ece9200804f0c2b64d10147ecaf18455a2a90827fbec4c9d84f3ad5 \
    --hash=sha256:ea9a9cc8bcc70e18023f30fa2f53d11ae069572a162791224e60cd65df55fb69 \
    --hash=sha256:ecb3f17dce4803c1099bd21742cd126b59817a4e76a6544d31d2cca6e30dbffd \
    --hash=sha256:ed794e3b3de42486d30444fb60b5561e724ee8a2d1b17b0c2e0f81e3ddaf7a87 \
    --hash=sha256:ee885d347279e38226d0a437b6a932f207f691c502ee565aba27a7022f1285df \
    --hash=sha256:fd5e7bc5f24f7e3d490698f7b854659a9851da2187414617cd5ed360af7efd63 \
    --hash=sha256:fe45f6870f7588ac7b2763ff1ce98cce59369717afe70cc353ec5218bc854bcc
zope.interface==5.1.0 \
    --hash=sha256:0103cba5ed09f27d2e3de7e48bb320338592e2fabc5ce1432cf33808eb2dfd8b \
    --hash=sha256:14415d6979356629f1c386c8c4249b4d0082f2ea7f75871ebad2e29584bd16c5 \
    --hash=sha256:1ae4693ccee94c6e0c88a4568fb3b34af8871c60f5ba30cf9f94977ed0e53ddd \
    --hash=sha256:1b87ed2dc05cb835138f6a6e3595593fea3564d712cb2eb2de963a41fd35758c \
    --hash=sha256:269b27f60bcf45438e8683269f8ecd1235fa13e5411de93dae3b9ee4fe7f7bc7 \
    --hash=sha256:27d287e61639d692563d9dab76bafe071fbeb26818dd6a32a0022f3f7ca884b5 \
    --hash=sha256:39106649c3082972106f930766ae23d1464a73b7d30b3698c986f74bf1256a34 \
    --hash=sha256:40e4c42bd27ed3c11b2c983fecfb03356fae1209de10686d03c02c8696a1d90e \
    --hash=sha256:461d4339b3b8f3335d7e2c90ce335eb275488c587b61aca4b305196dde2ff086 \
    --hash=sha256:4f98f70328bc788c86a6a1a8a14b0ea979f81ae6015dd6c72978f1feff70ecda \
    --hash=sha256:558a20a0845d1a5dc6ff87cd0f63d7dac982d7c3be05d2ffb6322a87c17fa286 \
    --hash=sha256:562dccd37acec149458c1791da459f130c6cf8902c94c93b8d47c6337b9fb826 \
    --hash=sha256:5e86c66a6dea8ab6152e83b0facc856dc4d435fe0f872f01d66ce0a2131b7f1d \
    --hash=sha256:60a207efcd8c11d6bbeb7862e33418fba4e4ad79846d88d160d7231fcb42a5ee \
    --hash=sha256:645a7092b77fdbc3f68d3cc98f9d3e71510e419f54019d6e282328c0dd140dcd \
    --hash=sha256:6874367586c020705a44eecdad5d6b587c64b892e34305bb6ed87c9bbe22a5e9 \
    --hash=sha256:74bf0a4f9091131de09286f9a605db449840e313753949fe07c8d0fe7659ad1e \
    --hash=sha256:7b726194f938791a6691c7592c8b9e805fc6d1b9632a833b9c0640828cd49cbc \
    --hash=sha256:8149ded7f90154fdc1a40e0c8975df58041a6f693b8f7edcd9348484e9dc17fe \
    --hash=sha256:8cccf7057c7d19064a9e27660f5aec4e5c4001ffcf653a47531bde19b5aa2a8a \
    --hash=sha256:911714b08b63d155f9c948da2b5534b223a1a4fc50bb67139ab68b277c938578 \
    --hash=sha256:a5f8f85986197d1dd6444763c4a15c991bfed86d835a1f6f7d476f7198d5f56a \
    --hash=sha256:a744132d0abaa854d1aad50ba9bc64e79c6f835b3e92521db4235a1991176813 \
    --hash=sha256:af2c14efc0bb0e91af63d00080ccc067866fb8cbbaca2b0438ab4105f5e0f08d \
    --hash=sha256:b054eb0a8aa712c8e9030065a59b5e6a5cf0746ecdb5f087cca5ec7685690c19 \
    --hash=sha256:b0becb75418f8a130e9d465e718316cd17c7a8acce6fe8fe07adc72762bee425 \
    --hash=sha256:b1d2ed1cbda2ae107283befd9284e650d840f8f7568cb9060b5466d25dc48975 \
    --hash=sha256:ba4261c8ad00b49d48bbb3b5af388bb7576edfc0ca50a49c11dcb77caa1d897e \
    --hash=sha256:d1fe9d7d09bb07228650903d6a9dc48ea649e3b8c69b1d263419cc722b3938e8 \
    --hash=sha256:d7804f6a71fc2dda888ef2de266727ec2f3915373d5a785ed4ddc603bbc91e08 \
    --hash=sha256:da2844fba024dd58eaa712561da47dcd1e7ad544a257482392472eae1c86d5e5 \
    --hash=sha256:dcefc97d1daf8d55199420e9162ab584ed0893a109f45e438b9794ced44c9fd0 \
    --hash=sha256:dd98c436a1fc56f48c70882cc243df89ad036210d871c7427dc164b31500dc11 \
    --hash=sha256:e74671e43ed4569fbd7989e5eecc7d06dc134b571872ab1d5a88f4a123814e9f \
    --hash=sha256:eb9b92f456ff3ec746cd4935b73c1117538d6124b8617bc0fe6fda0b3816e345 \
    --hash=sha256:ebb4e637a1fb861c34e48a00d03cffa9234f42bef923aec44e5625ffb9a8e8f9 \
    --hash=sha256:ef739fe89e7f43fb6494a43b1878a36273e5924869ba1d866f752c5812ae8d58 \
    --hash=sha256:f40db0e02a8157d2b90857c24d89b6310f9b6c3642369852cdc3b5ac49b92afc \
    --hash=sha256:f68bf937f113b88c866d090fea0bc52a098695173fc613b055a17ff0cf9683b6 \
    --hash=sha256:fb55c182a3f7b84c1a2d6de5fa7b1a05d4660d866b91dbf8d74549c57a1499e8
zope.proxy==4.3.5 \
    --hash=sha256:00573dfa755d0703ab84bb23cb6ecf97bb683c34b340d4df76651f97b0bab068 \
    --hash=sha256:092049280f2848d2ba1b57b71fe04881762a220a97b65288bcb0968bb199ec30 \
    --hash=sha256:0cbd27b4d3718b5ec74fc65ffa53c78d34c65c6fd9411b8352d2a4f855220cf1 \
    --hash=sha256:17fc7e16d0c81f833a138818a30f366696653d521febc8e892858041c4d88785 \
    --hash=sha256:19577dfeb70e8a67249ba92c8ad20589a1a2d86a8d693647fa8385408a4c17b0 \
    --hash=sha256:207aa914576b1181597a1516e1b90599dc690c095343ae281b0772e44945e6a4 \
    --hash=sha256:219a7db5ed53e523eb4a4769f13105118b6d5b04ed169a283c9775af221e231f \
    --hash=sha256:2b50ea79849e46b5f4f2b0247a3687505d32d161eeb16a75f6f7e6cd81936e43 \
    --hash=sha256:5903d38362b6c716e66bbe470f190579c530a5baf03dbc8500e5c2357aa569a5 \
    --hash=sha256:5c24903675e271bd688c6e9e7df5775ac6b168feb87dbe0e4bcc90805f21b28f \
    --hash=sha256:5ef6bc5ed98139e084f4e91100f2b098a0cd3493d4e76f9d6b3f7b95d7ad0f06 \
    --hash=sha256:61b55ae3c23a126a788b33ffb18f37d6668e79a05e756588d9e4d4be7246ab1c \
    --hash=sha256:63ddb992931a5e616c87d3d89f5a58db086e617548005c7f9059fac68c03a5cc \
    --hash=sha256:6943da9c09870490dcfd50c4909c0cc19f434fa6948f61282dc9cb07bcf08160 \
    --hash=sha256:6ad40f85c1207803d581d5d75e9ea25327cd524925699a83dfc03bf8e4ba72b7 \
    --hash=sha256:6b44433a79bdd7af0e3337bd7bbcf53dd1f9b0fa66bf21bcb756060ce32a96c1 \
    --hash=sha256:6bbaa245015d933a4172395baad7874373f162955d73612f0b66b6c2c33b6366 \
    --hash=sha256:7007227f4ea85b40a2f5e5a244479f6a6dfcf906db9b55e812a814a8f0e2c28d \
    --hash=sha256:74884a0aec1f1609190ec8b34b5d58fb3b5353cf22b96161e13e0e835f13518f \
    --hash=sha256:7d25fe5571ddb16369054f54cdd883f23de9941476d97f2b92eb6d7d83afe22d \
    --hash=sha256:7e162bdc5e3baad26b2262240be7d2bab36991d85a6a556e48b9dfb402370261 \
    --hash=sha256:814d62678dc3a30f4aa081982d830b7c342cf230ffc9d030b020cb154eeebf9e \
    --hash=sha256:8878a34c5313ee52e20aa50b03138af8d472bae465710fb954d133a9bfd3c38d \
    --hash=sha256:a66a0d94e5b081d5d695e66d6667e91e74d79e273eee95c1747717ba9cb70792 \
    --hash=sha256:a69f5cbf4addcfdf03dda564a671040127a6b7c34cf9fe4973582e68441b63fa \
    --hash=sha256:b00f9f0c334d07709d3f73a7cb8ae63c6ca1a90c790a63b5e7effa666ef96021 \
    --hash=sha256:b6ed71e4a7b4690447b626f499d978aa13197a0e592950e5d7020308f6054698 \
    --hash=sha256:bdf5041e5851526e885af579d2f455348dba68d74f14a32781933569a327fddf \
    --hash=sha256:be034360dd34e62608419f86e799c97d389c10a0e677a25f236a971b2f40dac9 \
    --hash=sha256:cc8f590a5eed30b314ae6b0232d925519ade433f663de79cc3783e4b10d662ba \
    --hash=sha256:cd7a318a15fe6cc4584bf3c4426f092ed08c0fd012cf2a9173114234fe193e11 \
    --hash=sha256:cf19b5f63a59c20306e034e691402b02055c8f4e38bf6792c23cad489162a642 \
    --hash=sha256:cfc781ce442ec407c841e9aa51d0e1024f72b6ec34caa8fdb6ef9576d549acf2 \
    --hash=sha256:dea9f6f8633571e18bc20cad83603072e697103a567f4b0738d52dd0211b4527 \
    --hash=sha256:e4a86a1d5eb2cce83c5972b3930c7c1eac81ab3508464345e2b8e54f119d5505 \
    --hash=sha256:e7106374d4a74ed9ff00c46cc00f0a9f06a0775f8868e423f85d4464d2333679 \
    --hash=sha256:e98a8a585b5668aa9e34d10f7785abf9545fe72663b4bfc16c99a115185ae6a5 \
    --hash=sha256:f64840e68483316eb58d82c376ad3585ca995e69e33b230436de0cdddf7363f9 \
    --hash=sha256:f8f4b0a9e6683e43889852130595c8854d8ae237f2324a053cdd884de936aa9b \
    --hash=sha256:fc45a53219ed30a7f670a6d8c98527af0020e6fd4ee4c0a8fb59f147f06d816c

# Contains the requirements for the letsencrypt package.
#
# Since the letsencrypt package depends on certbot and using pip with hashes
# requires that all installed packages have hashes listed, this allows
# dependency-requirements.txt to be used without requiring a hash for a
# (potentially unreleased) Certbot package.

letsencrypt==0.7.0 \
    --hash=sha256:105a5fb107e45bcd0722eb89696986dcf5f08a86a321d6aef25a0c7c63375ade \
    --hash=sha256:c36e532c486a7e92155ee09da54b436a3c420813ec1c590b98f635d924720de9

certbot==1.14.0 \
    --hash=sha256:67b4d26ceaea6c7f8325d0d45169e7a165a2cabc7122c84bc971ba068ca19cca \
    --hash=sha256:959ea90c6bb8dca38eab9772722cb940972ef6afcd5f15deef08b3c3636841eb
acme==1.14.0 \
    --hash=sha256:4f48c41261202f1a389ec2986b2580b58f53e0d5a1ae2463b34318d78b87fc66 \
    --hash=sha256:61daccfb0343628cbbca551a7fc4c82482113952c21db3fe0c585b7c98fa1c35
certbot-apache==1.14.0 \
    --hash=sha256:b757038db23db707c44630fecb46e99172bd791f0db5a8e623c0842613c4d3d9 \
    --hash=sha256:887fe4a21af2de1e5c2c9428bacba6eb7c1219257bc70f1a1d8447c8a321adb0
certbot-nginx==1.14.0 \
    --hash=sha256:8916a815437988d6c192df9f035bb7a176eab20eee0956677b335d0698d243fb \
    --hash=sha256:cc2a8a0de56d9bb6b2efbda6c80c647dad8db2bb90675cac03ade94bd5fc8597

UNLIKELY_EOF
    # -------------------------------------------------------------------------
    cat << "UNLIKELY_EOF" > "$TEMP_DIR/pipstrap.py"
#!/usr/bin/env python
"""A small script that can act as a trust root for installing pip >=8
Embed this in your project, and your VCS checkout is all you have to trust. In
a post-peep era, this lets you claw your way to a hash-checking version of pip,
with which you can install the rest of your dependencies safely. All it assumes
is Python 2.6 or better and *some* version of pip already installed. If
anything goes wrong, it will exit with a non-zero status code.
"""
# This is here so embedded copies are MIT-compliant:
# Copyright (c) 2016 Erik Rose
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
from __future__ import print_function
from distutils.version import StrictVersion
from hashlib import sha256
from os import environ
from os.path import join
from shutil import rmtree
try:
    from subprocess import check_output
except ImportError:
    from subprocess import CalledProcessError, PIPE, Popen

    def check_output(*popenargs, **kwargs):
        if 'stdout' in kwargs:
            raise ValueError('stdout argument not allowed, it will be '
                             'overridden.')
        process = Popen(stdout=PIPE, *popenargs, **kwargs)
        output, unused_err = process.communicate()
        retcode = process.poll()
        if retcode:
            cmd = kwargs.get("args")
            if cmd is None:
                cmd = popenargs[0]
            raise CalledProcessError(retcode, cmd)
        return output
import sys
from tempfile import mkdtemp
try:
    from urllib2 import build_opener, HTTPHandler, HTTPSHandler
except ImportError:
    from urllib.request import build_opener, HTTPHandler, HTTPSHandler
try:
    from urlparse import urlparse
except ImportError:
    from urllib.parse import urlparse  # 3.4


__version__ = 1, 5, 1
PIP_VERSION = '9.0.1'
DEFAULT_INDEX_BASE = 'https://pypi.python.org'


# wheel has a conditional dependency on argparse:
maybe_argparse = (
    [('18/dd/e617cfc3f6210ae183374cd9f6a26b20514bbb5a792af97949c5aacddf0f/'
      'argparse-1.4.0.tar.gz',
      '62b089a55be1d8949cd2bc7e0df0bddb9e028faefc8c32038cc84862aefdd6e4')]
    if sys.version_info < (2, 7, 0) else [])


# Be careful when updating the pinned versions here, in particular for pip.
# Indeed starting from 10.0, pip will build dependencies in isolation if the
# related projects are compliant with PEP 517. This is not something we want
# as of now, so the isolation build will need to be disabled wherever
# pipstrap is used (see https://github.com/certbot/certbot/issues/8256).
PACKAGES = maybe_argparse + [
    # Pip has no dependencies, as it vendors everything:
    ('11/b6/abcb525026a4be042b486df43905d6893fb04f05aac21c32c638e939e447/'
     'pip-{0}.tar.gz'.format(PIP_VERSION),
     '09f243e1a7b461f654c26a725fa373211bb7ff17a9300058b205c61658ca940d'),
    # This version of setuptools has only optional dependencies:
    ('37/1b/b25507861991beeade31473868463dad0e58b1978c209de27384ae541b0b/'
     'setuptools-40.6.3.zip',
     '3b474dad69c49f0d2d86696b68105f3a6f195f7ab655af12ef9a9c326d2b08f8'),
    ('c9/1d/bd19e691fd4cfe908c76c429fe6e4436c9e83583c4414b54f6c85471954a/'
     'wheel-0.29.0.tar.gz',
     '1ebb8ad7e26b448e9caa4773d2357849bf80ff9e313964bcaf79cbf0201a1648')
]


class HashError(Exception):
    def __str__(self):
        url, path, actual, expected = self.args
        return ('{url} did not match the expected hash {expected}. Instead, '
                'it was {actual}. The file (left at {path}) may have been '
                'tampered with.'.format(**locals()))


def hashed_download(url, temp, digest):
    """Download ``url`` to ``temp``, make sure it has the SHA-256 ``digest``,
    and return its path."""
    # Based on pip 1.4.1's URLOpener but with cert verification removed. Python
    # >=2.7.9 verifies HTTPS certs itself, and, in any case, the cert
    # authenticity has only privacy (not arbitrary code execution)
    # implications, since we're checking hashes.
    def opener(using_https=True):
        opener = build_opener(HTTPSHandler())
        if using_https:
            # Strip out HTTPHandler to prevent MITM spoof:
            for handler in opener.handlers:
                if isinstance(handler, HTTPHandler):
                    opener.handlers.remove(handler)
        return opener

    def read_chunks(response, chunk_size):
        while True:
            chunk = response.read(chunk_size)
            if not chunk:
                break
            yield chunk

    parsed_url = urlparse(url)
    response = opener(using_https=parsed_url.scheme == 'https').open(url)
    path = join(temp, parsed_url.path.split('/')[-1])
    actual_hash = sha256()
    with open(path, 'wb') as file:
        for chunk in read_chunks(response, 4096):
            file.write(chunk)
            actual_hash.update(chunk)

    actual_digest = actual_hash.hexdigest()
    if actual_digest != digest:
        raise HashError(url, path, actual_digest, digest)
    return path


def get_index_base():
    """Return the URL to the dir containing the "packages" folder.
    Try to wring something out of PIP_INDEX_URL, if set. Hack "/simple" off the
    end if it's there; that is likely to give us the right dir.
    """
    env_var = environ.get('PIP_INDEX_URL', '').rstrip('/')
    if env_var:
        SIMPLE = '/simple'
        if env_var.endswith(SIMPLE):
            return env_var[:-len(SIMPLE)]
        else:
            return env_var
    else:
        return DEFAULT_INDEX_BASE


def main():
    python = sys.executable or 'python'
    pip_version = StrictVersion(check_output([python, '-m', 'pip', '--version'])
                                .decode('utf-8').split()[1])
    has_pip_cache = pip_version >= StrictVersion('6.0')
    index_base = get_index_base()
    temp = mkdtemp(prefix='pipstrap-')
    try:
        downloads = [hashed_download(index_base + '/packages/' + path,
                                     temp,
                                     digest)
                     for path, digest in PACKAGES]
        # Calling pip as a module is the preferred way to avoid problems about pip self-upgrade.
        command = [python, '-m', 'pip', 'install', '--no-index', '--no-deps', '-U']
        # Disable cache since it is not used and it otherwise sometimes throws permission warnings:
        command.extend(['--no-cache-dir'] if has_pip_cache else [])
        command.extend(downloads)
        check_output(command)
    except HashError as exc:
        print(exc)
    except Exception:
        rmtree(temp)
        raise
    else:
        rmtree(temp)
        return 0
    return 1


if __name__ == '__main__':
    sys.exit(main())

UNLIKELY_EOF
    # -------------------------------------------------------------------------
    # Set PATH so pipstrap upgrades the right (v)env:
    PATH="$VENV_BIN:$PATH" "$VENV_BIN/python" "$TEMP_DIR/pipstrap.py"
    set +e
    if [ "$VERBOSE" = 1 ]; then
      "$VENV_BIN/pip" install --disable-pip-version-check --no-cache-dir --require-hashes -r "$TEMP_DIR/letsencrypt-auto-requirements.txt"
    else
      PIP_OUT=`"$VENV_BIN/pip" install --disable-pip-version-check --no-cache-dir --require-hashes -r "$TEMP_DIR/letsencrypt-auto-requirements.txt" 2>&1`
    fi
    PIP_STATUS=$?
    set -e
    if [ "$PIP_STATUS" != 0 ]; then
      # Report error. (Otherwise, be quiet.)
      error "Had a problem while installing Python packages."
      if [ "$VERBOSE" != 1 ]; then
        error
        error "pip prints the following errors: "
        error "====================================================="
        error "$PIP_OUT"
        error "====================================================="
        error
        error "Certbot has problem setting up the virtual environment."

        if `echo $PIP_OUT | grep -q Killed` || `echo $PIP_OUT | grep -q "allocate memory"` ; then
          error
          error "Based on your pip output, the problem can likely be fixed by "
          error "increasing the available memory."
        else
          error
          error "We were not be able to guess the right solution from your pip "
          error "output."
        fi

        error
        error "Consult https://certbot.eff.org/docs/install.html#problems-with-python-virtual-environment"
        error "for possible solutions."
        error "You may also find some support resources at https://certbot.eff.org/support/ ."
      fi
      rm -rf "$VENV_PATH"
      exit 1
    fi

    if [ -d "$OLD_VENV_PATH" -a ! -L "$OLD_VENV_PATH" ]; then
      rm -rf "$OLD_VENV_PATH"
      ln -s "$VENV_PATH" "$OLD_VENV_PATH"
    fi

    say "Installation succeeded."
  fi

  # If you're modifying any of the code after this point in this current `if` block, you
  # may need to update the "$DEPRECATED_OS" = 1 case at the beginning of phase 2 as well.

  if [ "$INSTALL_ONLY" = 1 ]; then
    say "Certbot is installed."
    exit 0
  fi

  "$VENV_BIN/letsencrypt" "$@"

else
  # Phase 1: Upgrade certbot-auto if necessary, then self-invoke.
  #
  # Each phase checks the version of only the thing it is responsible for
  # upgrading. Phase 1 checks the version of the latest release of
  # certbot-auto (which is always the same as that of the certbot
  # package). Phase 2 checks the version of the locally installed certbot.
  export PHASE_1_VERSION="$LE_AUTO_VERSION"

  if [ ! -f "$VENV_BIN/letsencrypt" ]; then
    if ! OldVenvExists; then
      if [ "$HELP" = 1 ]; then
        echo "$USAGE"
        exit 0
      fi
      # If it looks like we've never bootstrapped before, bootstrap:
      Bootstrap
    fi
  fi
  if [ "$OS_PACKAGES_ONLY" = 1 ]; then
    say "OS packages installed."
    exit 0
  fi

  DeterminePythonVersion "NOCRASH"
  # Don't warn about file permissions if the user disabled the check or we
  # can't find an up-to-date Python.
  if [ "$PYVER" -ge "$MIN_PYVER" -a "$NO_PERMISSIONS_CHECK" != 1 ]; then
    # If the script fails for some reason, don't break certbot-auto.
    set +e
    # Suppress unexpected error output.
    CHECK_PERM_OUT=$(CheckPathPermissions "$LE_PYTHON" "$0" 2>/dev/null)
    CHECK_PERM_STATUS="$?"
    set -e
    # Only print output if the script ran successfully and it actually produced
    # output. The latter check resolves
    # https://github.com/certbot/certbot/issues/7012.
    if [ "$CHECK_PERM_STATUS" = 0 -a -n "$CHECK_PERM_OUT" ]; then
      error "$CHECK_PERM_OUT"
    fi
  fi

  if [ "$NO_SELF_UPGRADE" != 1 ]; then
    TEMP_DIR=$(TempDir)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    # ---------------------------------------------------------------------------
    cat << "UNLIKELY_EOF" > "$TEMP_DIR/fetch.py"
"""Do downloading and JSON parsing without additional dependencies. ::

    # Print latest released version of LE to stdout:
    python fetch.py --latest-version

    # Download letsencrypt-auto script from git tag v1.2.3 into the folder I'm
    # in, and make sure its signature verifies:
    python fetch.py --le-auto-script v1.2.3

On failure, return non-zero.

"""

from __future__ import print_function, unicode_literals

from distutils.version import LooseVersion
from json import loads
from os import devnull, environ
from os.path import dirname, join
import re
import ssl
from subprocess import check_call, CalledProcessError
from sys import argv, exit
try:
    from urllib2 import build_opener, HTTPHandler, HTTPSHandler
    from urllib2 import HTTPError, URLError
except ImportError:
    from urllib.request import build_opener, HTTPHandler, HTTPSHandler
    from urllib.error import HTTPError, URLError

PUBLIC_KEY = environ.get('LE_AUTO_PUBLIC_KEY', """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6MR8W/galdxnpGqBsYbq
OzQb2eyW15YFjDDEMI0ZOzt8f504obNs920lDnpPD2/KqgsfjOgw2K7xWDJIj/18
xUvWPk3LDkrnokNiRkA3KOx3W6fHycKL+zID7zy+xZYBuh2fLyQtWV1VGQ45iNRp
9+Zo7rH86cdfgkdnWTlNSHyTLW9NbXvyv/E12bppPcEvgCTAQXgnDVJ0/sqmeiij
n9tTFh03aM+R2V/21h8aTraAS24qiPCz6gkmYGC8yr6mglcnNoYbsLNYZ69zF1XH
cXPduCPdPdfLlzVlKK1/U7hkA28eG3BIAMh6uJYBRJTpiGgaGdPd7YekUB8S6cy+
CQIDAQAB
-----END PUBLIC KEY-----
""")

class ExpectedError(Exception):
    """A novice-readable exception that also carries the original exception for
    debugging"""


class HttpsGetter(object):
    def __init__(self):
        """Build an HTTPS opener."""
        # Based on pip 1.4.1's URLOpener
        # This verifies certs on only Python >=2.7.9, and when NO_CERT_VERIFY isn't set.
        if environ.get('NO_CERT_VERIFY') == '1' and hasattr(ssl, 'SSLContext'):
            self._opener = build_opener(HTTPSHandler(context=cert_none_context()))
        else:
            self._opener = build_opener(HTTPSHandler())
        # Strip out HTTPHandler to prevent MITM spoof:
        for handler in self._opener.handlers:
            if isinstance(handler, HTTPHandler):
                self._opener.handlers.remove(handler)

    def get(self, url):
        """Return the document contents pointed to by an HTTPS URL.

        If something goes wrong (404, timeout, etc.), raise ExpectedError.

        """
        try:
            # socket module docs say default timeout is None: that is, no
            # timeout
            return self._opener.open(url, timeout=30).read()
        except (HTTPError, IOError) as exc:
            raise ExpectedError("Couldn't download %s." % url, exc)


def write(contents, dir, filename):
    """Write something to a file in a certain directory."""
    with open(join(dir, filename), 'wb') as file:
        file.write(contents)


def latest_stable_version(get):
    """Return the latest stable release of letsencrypt."""
    metadata = loads(get(
        environ.get('LE_AUTO_JSON_URL',
                    'https://pypi.python.org/pypi/certbot/json')).decode('UTF-8'))
    # metadata['info']['version'] actually returns the latest of any kind of
    # release release, contrary to https://wiki.python.org/moin/PyPIJSON.
    # The regex is a sufficient regex for picking out prereleases for most
    # packages, LE included.
    return str(max(LooseVersion(r) for r
                   in metadata['releases'].keys()
                   if re.match('^[0-9.]+$', r)))


def verified_new_le_auto(get, tag, temp_dir):
    """Return the path to a verified, up-to-date letsencrypt-auto script.

    If the download's signature does not verify or something else goes wrong
    with the verification process, raise ExpectedError.

    """
    le_auto_dir = environ.get(
        'LE_AUTO_DIR_TEMPLATE',
        'https://raw.githubusercontent.com/certbot/certbot/%s/'
        'letsencrypt-auto-source/') % tag
    write(get(le_auto_dir + 'letsencrypt-auto'), temp_dir, 'letsencrypt-auto')
    write(get(le_auto_dir + 'letsencrypt-auto.sig'), temp_dir, 'letsencrypt-auto.sig')
    write(PUBLIC_KEY.encode('UTF-8'), temp_dir, 'public_key.pem')
    try:
        with open(devnull, 'w') as dev_null:
            check_call(['openssl', 'dgst', '-sha256', '-verify',
                        join(temp_dir, 'public_key.pem'),
                        '-signature',
                        join(temp_dir, 'letsencrypt-auto.sig'),
                        join(temp_dir, 'letsencrypt-auto')],
                       stdout=dev_null,
                       stderr=dev_null)
    except CalledProcessError as exc:
        raise ExpectedError("Couldn't verify signature of downloaded "
                            "certbot-auto.", exc)


def cert_none_context():
    """Create a SSLContext object to not check hostname."""
    # PROTOCOL_TLS isn't available before 2.7.13 but this code is for 2.7.9+, so use this.
    context = ssl.SSLContext(ssl.PROTOCOL_SSLv23)
    context.verify_mode = ssl.CERT_NONE
    return context


def main():
    get = HttpsGetter().get
    flag = argv[1]
    try:
        if flag == '--latest-version':
            print(latest_stable_version(get))
        elif flag == '--le-auto-script':
            tag = argv[2]
            verified_new_le_auto(get, tag, dirname(argv[0]))
    except ExpectedError as exc:
        print(exc.args[0], exc.args[1])
        return 1
    else:
        return 0


if __name__ == '__main__':
    exit(main())

UNLIKELY_EOF
    # ---------------------------------------------------------------------------
    if [ "$PYVER" -lt "$MIN_PYVER" ]; then
      error "WARNING: couldn't find Python $MIN_PYTHON_VERSION+ to check for updates."
    elif ! REMOTE_VERSION=`"$LE_PYTHON" "$TEMP_DIR/fetch.py" --latest-version` ; then
      error "WARNING: unable to check for updates."
    fi

    # If for any reason REMOTE_VERSION is not set, let's assume certbot-auto is up-to-date,
    # and do not go into the self-upgrading process.
    if [ -n "$REMOTE_VERSION" ]; then
      LE_VERSION_STATE=`CompareVersions "$LE_PYTHON" "$LE_AUTO_VERSION" "$REMOTE_VERSION"`

      if [ "$LE_VERSION_STATE" = "UNOFFICIAL" ]; then
        say "Unofficial certbot-auto version detected, self-upgrade is disabled: $LE_AUTO_VERSION"
      elif [ "$LE_VERSION_STATE" = "OUTDATED" ]; then
        say "Upgrading certbot-auto $LE_AUTO_VERSION to $REMOTE_VERSION..."

        # Now we drop into Python so we don't have to install even more
        # dependencies (curl, etc.), for better flow control, and for the option of
        # future Windows compatibility.
        "$LE_PYTHON" "$TEMP_DIR/fetch.py" --le-auto-script "v$REMOTE_VERSION"

        # Install new copy of certbot-auto.
        # TODO: Deal with quotes in pathnames.
        say "Replacing certbot-auto..."
        # Clone permissions with cp. chmod and chown don't have a --reference
        # option on macOS or BSD, and stat -c on Linux is stat -f on macOS and BSD:
        cp -p "$0" "$TEMP_DIR/letsencrypt-auto.permission-clone"
        cp "$TEMP_DIR/letsencrypt-auto" "$TEMP_DIR/letsencrypt-auto.permission-clone"
        # Using mv rather than cp leaves the old file descriptor pointing to the
        # original copy so the shell can continue to read it unmolested. mv across
        # filesystems is non-atomic, doing `rm dest, cp src dest, rm src`, but the
        # cp is unlikely to fail if the rm doesn't.
        mv -f "$TEMP_DIR/letsencrypt-auto.permission-clone" "$0"
      fi  # A newer version is available.
    fi
  fi  # Self-upgrading is allowed.

  RerunWithArgs --le-auto-phase2 "$@"
fi
