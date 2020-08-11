#!/bin/bash

function check_libs {
    local elf_path=$1

    for elf in $(find $elf_path -maxdepth 1 -exec file {} \; | grep 'ELF ' | cut -d':' -f1); do
        echo "$elf"
        ldd "$elf"
    done
    return
}

function prepare {
    CURDIR=$(pwd)
    TMP_DIR="$CURDIR/temp"

    mkdir -p "$CURDIR"/temp
    mkdir -p "$TMP_DIR"/dbdeployer/tarball "$TMP_DIR"/dbdeployer/deployment

    TARBALLS=""
    for tarball in $(find . -name "*.tar.gz"); do
        TARBALLS+=" $(basename $tarball)"
    done

    DIRLIST="usr/bin lib/private"
}

main () {
    prepare
    for tarfile in $TARBALLS; do
        echo "Unpacking tarball: $tarfile"
        cd "$TMP_DIR"
        tar xf "$CURDIR/$tarfile"
        cd "${tarfile%.tar.gz}"

        echo "Building ELFs ldd output list"
        for DIR in $DIRLIST; do
            if ! check_libs "$DIR" >> "$TMP_DIR"/libs_err.log; then
                echo "There is an error with libs linkage"
                echo "Displaying log: "
                cat "$TMP_DIR"/libs_err.log
                exit 1
            fi
        done

         echo "Checking for missing libraries"
         if [[ ! -z $(grep "not found" $TMP_DIR/libs_err.log) ]]; then
            echo "ERROR: There are missing libraries: "
            grep "not found" "$TMP_DIR"/libs_err.log
            echo "Log: "
            cat "$TMP_DIR"/libs_err.log
            exit 1
        fi

        rm -rf "${TMP_DIR:?}/*"
    done
}

case "$1" in
    --test) main ;;
    --help|*)
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --test
        --help) usage ;;
Example $0 --install_deps 
EOF
    ;;
esac
