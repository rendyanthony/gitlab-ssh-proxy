#!/usr/bin/sh

SRC_DIR=$(dirname $0)
BUILD_DIR="$SRC_DIR/build"
PREFIX=${PREFIX:-/usr/local}

clean() {
    rm -rf $BUILD_DIR
}

build() {
    set -e

    mkdir -p $BUILD_DIR
    checkmodule -M -m -o $BUILD_DIR/gitlab-ssh-proxy.mod $SRC_DIR/gitlab-ssh-proxy.te
    semodule_package -o $BUILD_DIR/gitlab-ssh-proxy.pp -m $BUILD_DIR/gitlab-ssh-proxy.mod

    test -n "$SUDO_UID" && chown -R $SUDO_UID:$SUDO_GID $BUILD_DIR

    set +e
}

install_pkg() {
    set -e

    install $SRC_DIR/gitlab-keys-check $PREFIX/bin
    install $SRC_DIR/gitlab-shell-proxy $PREFIX/bin

    test ! -e $BUILD_DIR/gitlab-ssh-proxy.pp && build
    semodule -i $BUILD_DIR/gitlab-ssh-proxy.pp

    set +e
}

remove() {
    test -e $PREFIX/bin/gitlab-keys-check && rm $PREFIX/bin/gitlab-keys-check
    test -e $PREFIX/bin/gitlab-shell-proxy && rm $PREFIX/bin/gitlab-shell-proxy
    ( semodule -l | grep gitlab-ssh-proxy > /dev/null ) && semodule -r gitlab-ssh-proxy
}

show_help() {
    echo "GitLab SSH Proxy"
    echo ""
    echo "Usage:"
    echo "  $0 [commands]..."
    echo ""
    echo "Available Commands:"
    echo "  build   Build SELinux policy module package in $BUILD_DIR"
    echo "  clean   Remove $BUILD_DIR directory"
    echo "  install Copy scripts to $PREFIX/bin and install SE module package"
    echo "  remove  Remove scripts from $PREFIX/bin and remove SE module package"
    echo "  help    Show available commands"
}

if [[ $# -lt 1 ]]; then
    show_help
    exit 0
fi

for cmd in "$@"
do
    case "$cmd" in
        build)
            build
            ;;

        clean)
            clean
            ;;

        install)
            install_pkg
            ;;

        remove)
            remove
            ;;

        help)
            show_help
            ;;

        *)
            echo "Error: unrecognized command '${cmd}'"
            echo "Use '$0 help' for supported commands"
            break
            ;;
    esac
done