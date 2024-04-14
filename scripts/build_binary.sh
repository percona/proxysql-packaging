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

if [ -f /etc/debian_version ]; then
    GLIBC_VER_TMP="$(dpkg-query -W -f='${Version}' libc6 | awk -F'-' '{print $1}')"
else
    GLIBC_VER_TMP="$(rpm glibc -qa --qf %{VERSION})"
fi
export GLIBC_VER=".glibc${GLIBC_VER_TMP}"

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
VERSION="$(grep CURVER $SOURCEDIR/Makefile | awk -F'=' '{print $2}' | tr -d ' ')"

# Compilation flags
export CC=${CC:-gcc}
export CXX=${CXX:-g++}
export CFLAGS=-fpic
if [ -f /etc/debian_version ]; then
    export CXXFLAGS=' -std=c++17 -fpic'
else
    export CXXFLAGS=' -std=c++11 -fpic'
fi
export MAKE_JFLAG=-j4

# Create a temporary working directory
BASEINSTALLDIR="$(cd "$WORKDIR" && TMPDIR="$WORKDIR_ABS" mktemp -d proxysql-build.XXXXXX)"
INSTALLDIR="$WORKDIR_ABS/$BASEINSTALLDIR/proxysql-$VERSION-$(uname -s)-$(uname -m)$GLIBC_VER"   # Make it absolute

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
        sed -i -e 's@^\(\s\+cd curl/curl \&\& ./configure .*\) \(--with-ssl=.*\)$@\1 --without-zstd \2@' deps/Makefile
        make -j 4 build_deps
        make -j 4
        mkdir -p $INSTALLDIR/usr/bin
        mkdir -p $INSTALLDIR/etc
        mkdir -p $INSTALLDIR/etc/init.d
        mkdir -p $INSTALLDIR/etc/logrotate.d
        mkdir -p $INSTALLDIR/tests
        mkdir -p $INSTALLDIR/var/run/proxysql
        mkdir -p $INSTALLDIR/var/run/pxc_scheduler_handler
        install -m 0755 src/proxysql $INSTALLDIR/usr/bin
        install -m 0640 etc/proxysql.cnf $INSTALLDIR/etc
        install -m 0755 etc/init.d/proxysql $INSTALLDIR/etc/init.d
        cp -r tools/* $INSTALLDIR/usr/bin/
        if [ ! -d $INSTALLDIR/var/lib/proxysql ]; then mkdir -p $INSTALLDIR/var/lib/proxysql ; fi
        rm -fr proxysql-admin-tool
        if [ -n "${PAT_REPO:-}" ]; then
            git clone ${PAT_REPO}
        else
            git clone https://github.com/percona/proxysql-admin-tool.git
        fi
        cd proxysql-admin-tool
            git fetch origin
            #PAT_TAG - proxysql-admin-tool tag
             if [ -n "${PAT_TAG:-}" ]; then
                git checkout "${PAT_TAG}"
            fi
            # PSQLADM-322 Add pxc_scheduler_handler into ProxySQL package
            git submodule update --init
            sed -i 's|command -v go|command -v bash|g' build_scheduler.sh
            BINGO=$(command -v go)
            sed -i "s|go build|${BINGO} build|g" build_scheduler.sh
            sed -i "s|go mod|${BINGO} mod|g" build_scheduler.sh
            sudo bash -x build_scheduler.sh
            ldd -v pxc_scheduler_handler
        cd ../
        install -m 0755 proxysql-admin-tool/proxysql-admin $INSTALLDIR/usr/bin/proxysql-admin
        install -m 0755 proxysql-admin-tool/proxysql-admin-common $INSTALLDIR/usr/bin/proxysql-admin-common
        install -m 0755 proxysql-admin-tool/proxysql-common $INSTALLDIR/usr/bin/proxysql-common
        install -m 0755 proxysql-admin-tool/proxysql-login-file $INSTALLDIR/usr/bin/proxysql-login-file
        install -m 0755 proxysql-admin-tool/proxysql-status $INSTALLDIR/usr/bin/proxysql-status
        install -m 0755 proxysql-admin-tool/percona-scheduler/pxc_scheduler_handler $INSTALLDIR/usr/bin/pxc_scheduler_handler
        install -m 0755 proxysql-admin-tool/percona-scheduler-admin $INSTALLDIR/usr/bin/percona-scheduler-admin
        install -m 0640 proxysql-admin-tool/proxysql-admin.cnf $INSTALLDIR/etc/
        install -m 0644 proxysql-admin-tool/config.toml $INSTALLDIR/etc/
        install -m 0640 proxysql-admin-tool/proxysql-logrotate $INSTALLDIR/etc/logrotate.d/
        install -m 0755 proxysql-admin-tool/tests/* $INSTALLDIR/tests
    )
    exit_value=$?

    if test "x$exit_value" = "x0"
    then

        cd "$INSTALLDIR"
        LIBLIST="libgcrypt.so libtasn1.so libgnutls.so libuuid.so libnettle.so libhogweed.so libidn2.so"
        DIRLIST="usr/bin lib/private"

        LIBPATH=""

        function gather_libs {
            local elf_path=$1
            for lib in $LIBLIST; do
                for elf in $(find $elf_path -maxdepth 1 -exec file {} \; | grep 'ELF ' | cut -d':' -f1); do
                    IFS=$'\n'
                    for libfromelf in $(ldd $elf | grep $lib | awk '{print $3}'); do
                        if [ ! -f lib/private/$(basename $(readlink -f $libfromelf)) ] && [ ! -L lib/$(basename $(readlink -f $libfromelf)) ]; then
                            echo "Copying lib $(basename $(readlink -f $libfromelf))"
                            cp $(readlink -f $libfromelf) lib/private

                            echo "Symlinking lib $(basename $(readlink -f $libfromelf))"
                            cd lib
                            ln -s private/$(basename $(readlink -f $libfromelf)) $(basename $(readlink -f $libfromelf))
                            cd -
                            
                            LIBPATH+=" $(echo $libfromelf | grep -v $(pwd))"
                        fi
                    done
                    unset IFS
                done
            done
        }

        function set_runpath {
            # Set proper runpath for bins but check before doing anything
            local elf_path=$1
            local r_path=$2
            for elf in $(find $elf_path -maxdepth 1 -exec file {} \; | grep 'ELF ' | cut -d':' -f1); do
                if [ $elf != "usr/bin/pxc_scheduler_handler" ]; then
                    echo "Checking LD_RUNPATH for $elf"
                    if [ -z $(patchelf --print-rpath $elf) ]; then
                        echo "Changing RUNPATH for $elf"
                        patchelf --set-rpath $r_path $elf
                    fi
                fi
            done
        }

        function replace_libs {
            local elf_path=$1
            for libpath_sorted in $LIBPATH; do
                for elf in $(find $elf_path -maxdepth 1 -exec file {} \; | grep 'ELF ' | cut -d':' -f1); do
                    LDD=$(ldd $elf | grep $libpath_sorted|head -n1|awk '{print $1}')
                    if [[ ! -z $LDD  ]]; then
                        echo "Replacing lib $(basename $(readlink -f $libpath_sorted)) for $elf"
                        patchelf --replace-needed $LDD $(basename $(readlink -f $libpath_sorted)) $elf
                    fi
                done
            done
        }
        function check_libs {
            local elf_path=$1
            for elf in $(find $elf_path -maxdepth 1 -exec file {} \; | grep 'ELF ' | cut -d':' -f1); do
                if ! ldd $elf; then
                    exit 1
                fi
            done
        }

        if [ ! -d lib/private ]; then
            mkdir -p lib/private
        fi
        # Gather libs
        for DIR in $DIRLIST; do
            gather_libs $DIR
        done

        # Set proper runpath
        set_runpath usr/bin '$ORIGIN/../../lib/private/'
        set_runpath lib/private '$ORIGIN'

        # Replace libs
        for DIR in $DIRLIST; do
            replace_libs $DIR
        done

        # Make final check in order to determine any error after linkage
        for DIR in $DIRLIST; do
            check_libs $DIR
        done
        
        cd "$WORKDIR"
        ls -la

        $TAR czf "proxysql-$VERSION-$(uname -s)-$(uname -m)$GLIBC_VER.tar.gz" --owner=0 --group=0 -C "$INSTALLDIR/../" "proxysql-$VERSION-$(uname -s)-$(uname -m)$GLIBC_VER"
    fi

    # Clean up build dir
    rm -rf "proxysql-$VERSION-$(uname -s)-$(uname -m)$GLIBC_VER"

    exit $exit_value

)
exit_value=$?

# Clean up
rm -rf "$WORKDIR_ABS/$BASEINSTALLDIR"

exit $exit_value
