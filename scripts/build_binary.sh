#!/bin/bash
# Bail out on errors, be strict
set -ue

# Examine parameters
TARGET="$(uname -m)"
TARGET_CFLAGS=''
#
# Some programs that may be overriden
TAR=${TAR:-tar}

# Check if we have a functional getopt(1)
if ! getopt --test
then
    go_out="$(getopt --options="i" --longoptions=i686 \
        --name="$(basename "$0")" -- "$@")"
    test $? -eq 0 || exit 1
    eval set -- $go_out
fi

for arg
do
    case "$arg" in
    -- ) shift; break;;
    -i | --i686 )
        shift
        TARGET="i686"
        TARGET_CFLAGS="-m32 -march=i686"
        ;;
    esac
done

# Working directory
if test "$#" -eq 0
then
    WORKDIR="$(readlink -f $(dirname $0)/../../../../)"

    # Check that the current directory is not empty
    if test "x$(echo *)" != "x*"
    then
        echo >&2 \
            "Current directory is not empty. Use $0 . to force build in ."
        exit 1
    fi

    WORKDIR_ABS="$(cd "$WORKDIR"; pwd)"

elif test "$#" -eq 1
then
    WORKDIR="$1"

    # Check that the provided directory exists and is a directory
    if ! test -d "$WORKDIR"
    then
        echo >&2 "$WORKDIR is not a directory"
        exit 1
    fi

    WORKDIR_ABS="$(cd "$WORKDIR"; pwd)"

else
    echo >&2 "Usage: $0 [target dir]"
    exit 1

fi
SOURCEDIR="$(cd $(dirname "$0"); cd ../../; pwd)"
VERSION="$(grep CURVER $SOURCEDIR/Makefile | awk -F'=' '{print $2}')"

# Compilation flags
export CC=${CC:-gcc}
export CXX=${CXX:-g++}
export CFLAGS=${CFLAGS:-}
export CXXFLAGS=${CXXFLAGS:-}
export MAKE_JFLAG=-j4

# Create a temporary working directory
BASEINSTALLDIR="$(cd "$WORKDIR" && TMPDIR="$WORKDIR_ABS" mktemp -d proxysql-build.XXXXXX)"
INSTALLDIR="$WORKDIR_ABS/$BASEINSTALLDIR/proxysql-$VERSION-$(uname -s)-$(uname -m)"   # Make it absolute

mkdir "$INSTALLDIR"

# Build
(
    cd "$WORKDIR"

    # Build proper
    (
        cd $SOURCEDIR

        # Install the files
        make clean
        mkdir -p "$INSTALLDIR"
        make -j 4 build_deps
        make -j 4
        mkdir -p $INSTALLDIR/usr/bin
        mkdir -p $INSTALLDIR/etc
        mkdir -p $INSTALLDIR/etc/init.d
        mkdir -p $INSTALLDIR/etc/logrotate.d
        mkdir -p $INSTALLDIR/tests
        install -m 0755 src/proxysql $INSTALLDIR/usr/bin
        install -m 0640 etc/proxysql.cnf $INSTALLDIR/etc
        install -m 0755 etc/init.d/proxysql $INSTALLDIR/etc/init.d
        cp -r tools/* $INSTALLDIR/usr/bin/
        if [ ! -d $INSTALLDIR/var/lib/proxysql ]; then mkdir -p $INSTALLDIR/var/lib/proxysql ; fi
        rm -fr proxysql-admin-tool
        git clone https://github.com/percona/proxysql-admin-tool.git
        cd proxysql-admin-tool
            git fetch origin
            #PAT_TAG - proxysql-admin-tool tag
            if [ -n "${PAT_TAG:-}" ]; then
                git checkout "${PAT_TAG}"
            fi
        cd ../
        install -m 0775 proxysql-admin-tool/proxysql-admin $INSTALLDIR/usr/bin/proxysql-admin
        install -m 0775 proxysql-admin-tool/proxysql-status $INSTALLDIR/usr/bin/proxysql-status
        install -m 0640 proxysql-admin-tool/proxysql-admin.cnf $INSTALLDIR/etc/
        install -m 0640 proxysql-admin-tool/proxysql-logrotate $INSTALLDIR/etc/logrotate.d/
	install -m 0775 proxysql-admin-tool/tests/* $INSTALLDIR/tests
    )
    exit_value=$?

    if test "x$exit_value" = "x0"
    then
      if [ -f /etc/debian_version ]; then
        export OS_RELEASE="$(lsb_release -sc)"
      fi
      if [ -f /etc/redhat-release ]; then
        export OS_RELEASE="centos$(lsb_release -sr | awk -F'.' '{print $1}')"
        RHEL=$(rpm --eval %rhel)
      fi
      $TAR czf "proxysql-$VERSION-$(uname -s)-$OS_RELEASE-$(uname -m).tar.gz" \
            --owner=0 --group=0 -C "$INSTALLDIR/../" \
            "proxysql-$VERSION-$(uname -s)-$(uname -m)"
    fi

    # Clean up build dir
    rm -rf "proxysql-$VERSION-$(uname -s)-$(uname -m)"

    exit $exit_value

)
exit_value=$?

# Clean up
rm -rf "$WORKDIR_ABS/$BASEINSTALLDIR"

exit $exit_value
