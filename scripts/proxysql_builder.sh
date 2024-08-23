#!/usr/bin/env bash

shell_quote_string() {
  echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is set - src rpm will be built
        --build_src_deb  If it is set - source deb package will be built
        --build_rpm         If it is set - rpm will be built
        --build_deb         If it is set - deb will be built
        --build_tarball     If it is set - tarball will be built
        --install_deps      Install build dependencies(root privilages are required)
        --branch            Branch for build
        --repo              Repo for build
        --help) usage ;;
Example $0 --builddir=/tmp/BUILD --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "$(shell_quote_string "$1")
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi

    for arg do
        val=$(echo "$arg" | sed -e 's;^--[^=]*=;;')
        case "$arg" in
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_src_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --build_tarball=*) BTARBALL="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --proxysql_branch=*) PROXYSQL_BRANCH="$val" ;;
            --proxysql_repo=*) PROXYSQL_REPO="$val" ;;
            --pat_repo=*) PAT_REPO="$val" ;;
            --pat_tag=*) PAT_TAG="$val" ;;
            --proxysql_ver=*) VERSION="$val" ;;
            --repo=*) GIT_REPO="$val" ;;
            --branch=*) GIT_BRANCH="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --help) usage ;;
            *)
              if test -n "$pick_args"
              then
                  append_arg_to_args "$arg"
              fi
              ;;
        esac
    done
}

switch_to_vault_repo() {
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
    sed -i 's|#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
}

check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
	then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

add_percona_yum_repo(){
    yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
    percona-release disable all
    percona-release enable ppg-11.19 testing
    return 
}

get_sources(){
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    PRODUCT=proxysql2
    echo "PRODUCT=${PRODUCT}" > proxysql.properties
    PRODUCT_FULL=${PRODUCT}-${VERSION}
    echo "VERSION=${VERSION}" >> proxysql.properties
    echo "PROXYSQL_VERSION=${VERSION}" >> proxysql.properties
    echo "GIT_VERSION=${GIT_VERSION}" >> proxysql.properties
    echo "REVISION=${REVISION}" >> proxysql.properties
    echo "RPM_RELEASE=${RPM_RELEASE}" >> proxysql.properties
    echo "DEB_RELEASE=${DEB_RELEASE}" >> proxysql.properties
    echo "PROXYSQL_REPO=${PROXYSQL_REPO}" >> proxysql.properties
    echo "GIT_REPO=${GIT_REPO}" >> proxysql.properties
    BRANCH_NAME="${BRANCH}"
    echo "BRANCH_NAME=${BRANCH_NAME}" >> proxysql.properties
    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> proxysql.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> proxysql.properties
    echo "BUILD_ID=${BUILD_ID}" >> proxysql.properties
    echo "PAT_TAG=${PAT_TAG}" >> proxysql.properties
    echo "GIT_BRANCH=${GIT_BRANCH}" >> proxysql.properties
    rm -rf proxysql-packaging
    git clone ${GIT_REPO}
    cd proxysql-packaging
    git checkout ${GIT_BRANCH}
    cd ../
    git clone ${PAT_REPO}
    cd proxysql-admin-tool
    git fetch origin
    if [ ! -z ${PAT_TAG} ]; then
        git checkout ${PAT_TAG}
    fi
    sed -i 's:2.0.12:2.0.15:' proxysql-admin
    cd ..
    git clone ${PROXYSQL_REPO} ${PRODUCT_FULL}
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    cd ${PRODUCT_FULL}
    git fetch origin
    git checkout ${PROXYSQL_BRANCH}
    GIT_VERSION=${VERSION}-percona
    REVISION=$(git rev-parse --short HEAD)
    sed -i "s/export CURVER?=.*/export CURVER?=${VERSION}/g" Makefile
    sed -i 's/shell cat.*/shell rpm --eval \%rhel)/' deps/Makefile
    sed -i 's:6.7:6:' deps/Makefile
    sed -i 's/shell cat.*/shell rpm --eval \%rhel)/' src/Makefile
    sed -i 's:6.7:6:' src/Makefile
    sed -i '94s|exit 0||' etc/init.d/proxysql
    sed -i "s:GITVERSION:\"${GIT_VERSION}-${RPM_RELEASE}\":g" include/proxysql.h
    cd ..
    echo "REVISION=${REVISION}" >> ${WORKDIR}/proxysql.properties
    cd ${PRODUCT_FULL}
    rm -fr debian rpm
    cp -ap ${WORKDIR}/proxysql-packaging/debian/ .
    cp -ap ${WORKDIR}/proxysql-packaging/rpm/ .
    cp -ap ${WORKDIR}/proxysql-packaging/scripts/ srcipts_packaging
    cp -ap ${WORKDIR}/proxysql-admin-tool/ .
    cd ${WORKDIR}
    #
    source proxysql.properties
    #

    tar --owner=0 --group=0 -czf ${PRODUCT_FULL}.tar.gz ${PRODUCT_FULL}
    echo "UPLOAD=UPLOAD/experimental/BUILDS/${PRODUCT}/${PRODUCT_FULL}/${PSM_BRANCH}/${REVISION}/${BUILD_ID}" >> proxysql.properties
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT_FULL}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT_FULL}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    #rm -rf proxysql*
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}
install_go() {
    wget -q https://dl.google.com/go/go1.22.2.linux-amd64.tar.gz
    tar -C /usr/bin -xzf go1.22.2.linux-amd64.tar.gz
    export PATH=$PATH:/usr/bin/go/bin
    go version
    which go
    command -v go
    whereis go 
}

update_pat() {
    git submodule update --init
    which go
    sed -i 's|command -v go|command -v bash|g' build_scheduler.sh
    sed -i 's|go build|/usr/bin/go/bin/go build|g' build_scheduler.sh
    sed -i 's|go mod|/usr/bin/go/bin/go mod|g' build_scheduler.sh
    bash -x build_scheduler.sh
    ./pxc_scheduler_handler --version
}

install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ $( id -u ) -ne 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)
    RHEL=$(rpm --eval %rhel)
    if [ "x$OS" = "xrpm" ]; then
      if [ "x${RHEL}" = "x7" -o "x${RHEL}" = "x8" ]; then
            switch_to_vault_repo
      fi
      yum -y install wget which
      add_percona_yum_repo
#      wget http://jenkins.percona.com/yum-repo/percona-dev.repo
#      mv -f percona-dev.repo /etc/yum.repos.d/
      yum clean all
      yum -y install curl epel-release
      if [ "x${RHEL}" = "x7" -o "x${RHEL}" = "x8" ]; then
            switch_to_vault_repo
      fi
      if [ x"$RHEL" = x6 ]; then
        until yum -y install centos-release-scl; do
            echo "waiting"
            sleep 1
        done
	curl https://jenkins.percona.com/downloads/cent6/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
        curl https://jenkins.percona.com/downloads/cent6/centos6-epel-eol.repo --output /etc/yum.repos.d/epel.repo
	curl https://jenkins.percona.com/downloads/cent6/centos6-scl-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl.repo
        curl https://jenkins.percona.com/downloads/cent6/centos6-scl-rh-eol.repo --output /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
        yum -y install epel-release
        yum -y install automake autoconf
        sed -i "s/mirrorlist=https/mirrorlist=http/" /etc/yum.repos.d/epel.repo
        yum -y install http://repo.okay.com.mx/centos/6/x86_64/release/okay-release-1-1.noarch.rpm || true
        yum -y upgrade automake autoconf
        yum -y install perl-IPC-Cmd
	wget --no-check-certificate http://people.centos.org/tru/devtools-2/devtools-2.repo -O /etc/yum.repos.d/devtools-2.repo
        yum -y install devtoolset-2-gcc devtoolset-2-binutils devtoolset-2-gcc-c++ cmake openssl-devel patch
        ln -fs /opt/rh/devtoolset-2/root/usr/bin/gcc /usr/bin/cc
        ln -fs /opt/rh/devtoolset-2/root/usr/bin/g++ /usr/bin/g++
        CC=gcc
        CXX=g++
        ${CXX} --version
#        INSTALL_LIST="git rpm-build clang autoconf libtool flex rpmdevtools wget llvm-toolset-7 devtoolset-7 rpmlint percona-postgresql11-devel gcc make  geos geos-devel proj libgeotiff-devel pcre-devel gmp-devel SFCGAL SFCGAL-devel gdal34-devel geos311-devel gmp-devel gtk2-devel json-c-devel libgeotiff16-devel proj72-devel protobuf-c-devel pkg-config"
        #yum -y install ${INSTALL_LIST}
        #source /opt/rh/devtoolset-7/enable
        #source /opt/rh/llvm-toolset-7/enable
      else
	 yum config-manager --enable PowerTools AppStream BaseOS *epel
	 dnf module -y disable postgresql
        # dnf config-manager --set-enabled ol${RHEL}_codeready_builder
        # INSTALL_LIST="git rpm-build clang autoconf libtool flex rpmdevtools wget llvm-toolset rpmlint percona-postgresql11-devel gcc make  geos geos-devel proj libgeotiff-devel pcre-devel gmp-devel SFCGAL SFCGAL-devel gdal35-devel geos311-devel gmp-devel gtk2-devel json-c-devel libgeotiff16-devel proj90-devel protobuf-c-devel pkg-config"
      #  yum -y install ${INSTALL_LIST}
     #   yum -y install binutils gcc gcc-c++
     #   yum clean all
     #   if [ ! -f  /usr/bin/llvm-config ]; then
     #       ln -s /usr/bin/llvm-config-64 /usr/bin/llvm-config
     #   fi
      fi
     # yum -y install docbook-xsl libxslt-devel
      INSTALL_LIST="git wget epel-release rpm-build gcc perl automake bzip2 cmake make gcc-c++ gcc git openssl openssl-devel gnutls gnutls-devel libtool patch python3 perl-IPC-Cmd libuuid-devel"
      yum -y install ${INSTALL_LIST}
      install_go
      #update_pat
      if [ $RHEL = 8 ]; then
          cat /etc/os-release
          yum -y update
          yum -y install python2 gnutls-devel libtool || true
          ln -s /usr/bin/python2.7 /usr/bin/python || true
          rpm -q centos-release || true
          rpm -q centos-linux-release || true
          yum -y install epel-release
          yum -y install libcurl-devel libunwind libunwind-devel
          yum -y install libunwind libunwind-devel
          yum -y upgrade
	  ln -s /usr/bin/python2.7 /usr/bin/python || true
          yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
          percona-release disable all
          percona-release enable tools testing
          yum -y install patchelf
      fi
      if [ $RHEL = 9 ]; then
          cat /etc/os-release
          yum -y update
          yum -y install python3 gnutls-devel libtool || true
          ln -s /usr/bin/python3.9 /usr/bin/python || true
          yum -y install yum-utils
          yum-config-manager --enable ol9_codeready_builder
          yum -y install epel-release
          yum -y install libcurl-devel libunwind libunwind-devel zlib-devel
      fi
      if [ $RHEL -eq 7 ]; then
          /usr/bin/python -V
          head -1 /usr/bin/yum
          yum -y install patchelf
      fi
      pushd /tmp
      wget --no-check-certificate https://cmake.org/files/v3.22/cmake-3.22.1.tar.gz 
      tar -zxf cmake-3.22.1.tar.gz
      cd cmake-3.22.1 && ./configure && make -j$(nproc) && make install && cd .. && rm -rf cmake-3.22.1.tar.gz cmake-3.22.1
      cmake --version
      popd
    else
      apt-get -y update
      apt-get -y install curl wget lsb-release
      export DEBIAN=$(lsb_release -sc)
      export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
      apt-get -y install gnupg2
      apt-get update || true
      ENV export DEBIAN_FRONTEND=noninteractive
      apt-get update
#      if [ ${DEBIAN_VERSION} != focal -a ${DEBIAN_VERSION} != bullseye -a ${DEBIAN_VERSION} != jammy ]; then
#	  wget -q -O - http://jenkins.percona.com/apt-repo/8507EFA5.pub | apt-key add -
#	  wget -q -O - http://jenkins.percona.com/apt-repo/CD2EFD2A.pub | apt-key add -

#	  echo "deb http://jenkins.percona.com/apt-repo/ ${DEBIAN_VERSION} main" > percona-dev.list
#	  mv -f percona-dev.list /etc/apt/sources.list.d/
#      fi
      until DEBIAN_FRONTEND=noninteractive  apt-get update; do 
          echo "waiting"
          sleep 1
      done
      INSTALL_LIST="build-essential gnupg2 devscripts gawk pkg-config debhelper cmake wget libssl-dev gawk lynx zlib1g-dev bison byacc flex automake bzip2 cmake make g++ gcc git openssl libssl-dev libgnutls28-dev libtool patch gnutls-dev libgnutls28-dev libcurl4-openssl-dev libunwind8 libunwind-dev uuid-dev"
       until DEBIAN_FRONTEND=noninteractive apt-get -y --allow-unauthenticated install ${INSTALL_LIST}; do
        sleep 1
        echo "waiting"
      done
      if [ "x${DEBIAN}" = "xfocal" -o "x${DEBIAN}" = "xjammy" -o "x${DEBIAN}" = "xbullseye" ]; then
          apt-get -y install python2
          ln -s /usr/bin/python2 /usr/bin/python || true
      else
          apt-get install -y dh-systemd
      fi
      if [ "x${DEBIAN}" = "xbullseye" -o "x${DEBIAN}" = "xjammy" ]; then
          apt install -y gcc-9 g++-9 cmake
          ln -s -f /usr/bin/g++-9 /usr/bin/g++
          ln -s -f /usr/bin/gcc-9 /usr/bin/gcc
          ln -s -f /usr/bin/gcc-ar-9 /usr/bin/gcc-ar
          ln -s -f /usr/bin/gcc-nm-9 /usr/bin/gcc-nm
          ln -s -f /usr/bin/gcc-ranlib-9 /usr/bin/gcc-ranlib
          ln -s -f /usr/bin/x86_64-linux-gnu-g++-9 /usr/bin/x86_64-linux-gnu-g++
          ln -s -f /usr/bin/x86_64-linux-gnu-gcc-9 /usr/bin/x86_64-linux-gnu-gcc
          ln -s -f /usr/bin/x86_64-linux-gnu-gcc-ar-9 /usr/bin/x86_64-linux-gnu-gcc-ar
          ln -s -f /usr/bin/x86_64-linux-gnu-gcc-nm-9 /usr/bin/x86_64-linux-gnu-gcc-nm
          ln -s -f /usr/bin/x86_64-linux-gnu-gcc-ranlib-9 /usr/bin/x86_64-linux-gnu-gcc-ranlib
      fi
      if [ "x${DEBIAN}" = "xjammy" -o "x${DEBIAN}" = "xxenial" -o "x${DEBIAN}" = "xbionic" -o "x${DEBIAN}" = "xbuster" -o "x${DEBIAN}" = "xstretch" ]; then
      # Fix syntax error in cmake 3.20
    # https://github.com/mariadb-corporation/mariadb-connector-c/commit/242cab8cbcd91af882233730a83627d3b12ced83
    # remove next blok if a new version of mariadb-connector-c is used
    
    # sudo apt-get remove -y cmake
          wget https://github.com/Kitware/CMake/releases/download/v3.19.8/cmake-3.19.8.tar.gz
          tar -zxvf cmake-3.19.8.tar.gz
          cd cmake-3.19.8/
          ./bootstrap
          make
          make install
          PATH=$PATH:/usr/local/bin
          cmake --version
      fi
      if [ "x${DEBIAN}" = "xbuster" -o "x${DEBIAN}" = "xbionic" ]; then
	  wget https://repo.percona.com/percona/apt/percona-release_latest.${DEBIAN}_all.deb
          dpkg -i ./percona-release_latest.${DEBIAN}_all.deb
          percona-release enable tools testing
          apt-get update
          apt-get install -y patchelf 
      fi
      install_go
      #update_pat
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'proxysql*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'proxysql*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "proxysql*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "proxysql*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    ls $WORKDIR
    get_tar "source_tarball"
    rm -fr rpmbuild
    #ls | grep -v tar.gz | xargs rm -rf
    TARFILE=$(find . -name 'proxysql*.tar.gz' | sort | tail -n1)
    SRC_DIR=${TARFILE%.tar.gz}
    tar xvf ${TARFILE}
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/rpm' --strip=1
    #
    cp -av rpm/* rpmbuild/SOURCES
    cd ${WORKDIR}/${PRODUCT_FULL}/proxysql-admin-tool
    update_pat
    cd $WORKDIR
    cp -ap ${WORKDIR}/${PRODUCT_FULL}/proxysql-admin-tool/* rpmbuild/SOURCES/
    cp -ap ${WORKDIR}/${PRODUCT_FULL}/proxysql-admin-tool/percona-scheduler/pxc_scheduler_handler rpmbuild/SOURCES/
    cp -ap ${WORKDIR}/${PRODUCT_FULL}/proxysql-admin-tool/config.toml rpmbuild/SOURCES/
    cd rpmbuild/SOURCES
    
   # wget --no-check-certificate https://download.osgeo.org/postgis/docs/postgis-3.3.1.pdf
    #wget --no-check-certificate https://www.postgresql.org/files/documentation/pdf/12/postgresql-12-A4.pdf
    cd ../../
    cp -av rpmbuild/SOURCES/proxysql.spec rpmbuild/SPECS
#    cd ${WORKDIR}/rpmbuild/SPECS
#    cp -ap ${WORKDIR}/proxysql-packaging/rpm/*.spec .
#    cp -ap ${WORKDIR}/proxysql-admin-tool/* rpmbuild/SOURCES/
#    cp -ap ${WORKDIR}/proxysql-admin-tool/percona-scheduler/pxc_scheduler_handler rpmbuild/SOURCES/
#    cp -ap ${WORKDIR}/proxysql-admin-tool/config.toml rpmbuild/SOURCES/
    cd ${WORKDIR}
    #
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
   # if [ -f /opt/rh/devtoolset-7/enable ]; then
   #     source /opt/rh/devtoolset-7/enable
   #     source /opt/rh/llvm-toolset-7/enable
   # fi
    sed -i "s:@@VERSION@@:${VERSION}:g" rpmbuild/SPECS/proxysql.spec
    sed -i "s:@@RELEASE@@:${RPM_RELEASE}%{?dist}:g" rpmbuild/SPECS/proxysql.spec
    sed -i "s|del proxysql|del proxysql \&\& /etc/init.d/proxysql restart|g" rpmbuild/SPECS/proxysql.spec
    sed -i "s/rm \-rf \/var\/run\/proxysql/\/etc\/init.d\/proxysql restart/g" rpmbuild/SPECS/proxysql.spec
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/proxysql.spec
    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    return
}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'proxysql*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'proxysql*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    rm -fr rpmbuild
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cp $SRC_RPM rpmbuild/SRPMS/

    cd rpmbuild/SRPMS/
    #
    cd $WORKDIR
    RHEL=$(rpm --eval %rhel)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    [ -f /opt/percona-devtoolset/enable ] && source /opt/percona-devtoolset/enable
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --rebuild rpmbuild/SRPMS/${SRC_RPM} 

    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrpm" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    #rm -rf proxysql2*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #
    TARFILE=$(basename $(find . -name 'proxysql*.tar.gz' | sort | tail -n1))
    DEBIAN=$(lsb_release -sc)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    tar zxf ${TARFILE}
    BUILDDIR=${TARFILE%.tar.gz}
    #
    
    mv ${TARFILE} ${PRODUCT}_${VERSION}.orig.tar.gz
    cd ${BUILDDIR}/proxysql-admin-tool
    update_pat
    cd ..
    cp -ap proxysql-admin-tool/* tools/
    cp -ap proxysql-admin-tool/percona-scheduler/pxc_scheduler_handler tools/
    cp -ap proxysql-admin-tool/config.toml etc/
    mv tools/LICENSE .
    mv tools/proxysql-admin.cnf etc/ 
    cd debian
    #rm -rf changelog
    sed -i "s:@@VERSION@@:${VERSION}:g" changelog
    sed -i "s:@@VERSION@@:${VERSION}:g" control
 
    cd ../
    dch -D unstable --force-distribution -v "${VERSION}" "Update to new upstream release Proxysql ${VERSION}-${DEB_RELEASE}"
    dpkg-buildpackage -S
    cd ../
    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb
    cp *.tar.xz $WORKDIR/source_deb
    cp *_source.changes $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.orig.tar.gz $WORKDIR/source_deb
    cp *.tar.xz $CURDIR/source_deb
    cp *_source.changes $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.orig.tar.gz $CURDIR/source_deb
}

build_tarball(){
    if [ $BTARBALL = 0 ]
    then
        echo "Binary tarball will not be created"
        return;
    fi
    export DEBIAN_VERSION=$(lsb_release -sc)
    cd $WORKDIR
    mkdir TARGET 
    [ -f /opt/percona-devtoolset/enable ] && source /opt/percona-devtoolset/enable
    [ -f /opt/rh/devtoolset-8/enable ] && source /opt/rh/devtoolset-8/enable
    echo "PROXYSQL_VERSION=${VERSION}" > proxysql.properties
    echo "PAT_TAG=${PAT_TAG}" >> proxysql.properties
    source proxysql.properties
    get_tar "source_tarball"
    TARBALL=$(find . -type f -name 'proxysql*.tar.gz')
    #VERSION_TMP=$(echo ${TARBALL}| awk -F '-' '{print $2}')
   # echo $VERSION_TMP
   # VERSION=${VERSION_TMP%.tar.gz}
   # DIRNAME=${NAME}-${VERSION}
    tar xzf ${TARBALL}
    cd ${WORKDIR}
    git clone ${GIT_REPO}
    cd proxysql-packaging
    git checkout ${GIT_BRANCH}
    cd $WORKDIR
    gcc --version
    sed -i 's/$SOURCEDIR\/Makefile/$SOURCEDIR\/proxysql2-${PROXYSQL_VERSION}\/Makefile/' ./proxysql-packaging/scripts/build_binary.sh
    sed -i 's/cd $SOURCEDIR/cd $SOURCEDIR\/proxysql2-${PROXYSQL_VERSION}/' ./proxysql-packaging/scripts/build_binary.sh
    sed -i '73i source $SOURCEDIR/proxysql.properties' ./proxysql-packaging/scripts/build_binary.sh
    sed -i '248i cp proxysql-$VERSION-$(uname -s)-$(uname -m)$GLIBC_VER.tar.gz $SOURCEDIR' ./proxysql-packaging/scripts/build_binary.sh
    sed -i 's/s|go build|${BINGO} build|g/s|go build|\/usr\/bin\/go\/bin\/go build|g/' ./proxysql-packaging/scripts/build_binary.sh
    sed -i 's/s|go mod|${BINGO} mod|g/s|go mod|\/usr\/bin\/go\/bin\/go mod|g/' ./proxysql-packaging/scripts/build_binary.sh
    sed -i 's/sudo bash/bash/' ./proxysql-packaging/scripts/build_binary.sh
    sed -i '/BINGO/d' ./proxysql-packaging/scripts/build_binary.sh
    bash -x ./proxysql-packaging/scripts/build_binary.sh ${WORKDIR}/TARGET

    cd ${WORKDIR}/TARGET
    if [ "x${DEBIAN_VERSION}" = "xxenial" ]; then
        ls -la
        TARBALL_NEW=$(find . -type f -name '*.tar.gz')
        NAME=$(echo ${TARBALL_NEW}| awk -F'.tar' '{print $1}')
        tar -xvzf ${TARBALL_NEW}
        rm -f ${TARBALL_NEW}
        cd ${NAME}
        cd usr/bin
        curl https://jenkins.percona.com/downloads/PSQLADM-268/openssl -o proxysql-admin-openssl
        chmod 755 proxysql-admin-openssl
        cd ../../../
        mv ${NAME} ${NAME}.xenial
        tar -zcvf ${NAME}.xenial.tar.gz ${NAME}.xenial
    fi
    mkdir -p $CURDIR/tarball
    mkdir -p $WORKDIR/tarball
    cp $WORKDIR/*glibc*tar.gz $WORKDIR/tarball
    cp $WORKDIR/*glibc*tar.gz $CURDIR/tarball
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes'
    do
        get_deb_sources $file
    done
    cd $WORKDIR
    tar xvf ${PRODUCT}_${VERSION}.orig.tar.gz
    rm -fv *.deb
    #
    export DEBIAN_VERSION=$(lsb_release -sc)
    export DEBIAN=$(lsb_release -sc)
    export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    export DIRNAME=$(echo ${DSC%.dsc} | sed -e 's:_:-:g')
    #export VERSION=$(echo ${DSC%.dsc} | awk -F'_' '{print $2}')
    #
    echo "ARCH=${ARCH}" >> proxysql.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> proxysql.properties
    echo VERSION=${VERSION} >> proxysql.properties
    #
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n1))
    #
    dpkg-source -x ${DSC}
    #
    cd ${PRODUCT}-${VERSION}
    cd proxysql-admin-tool
    update_pat
    cd ..
    cp -ap proxysql-admin-tool/* tools/
    cp -ap proxysql-admin-tool/percona-scheduler/pxc_scheduler_handler tools/
    cp -ap proxysql-admin-tool/config.toml etc/
    mv tools/LICENSE .
    mv tools/proxysql-admin.cnf etc/
    sed -i "s:@@VERSION@@:${VERSION}:g" debian/changelog
    sed -i "s:@@VERSION@@:${VERSION}:g" debian/control
    if [ $DEBIAN_VERSION = "bionic" -o $DEBIAN_VERSION = "jessie" -o $DEBIAN_VERSION = "focal" -o $DEBIAN_VERSION = "jammy" -o $DEBIAN_VERSION = "buster" -o $DEBIAN_VERSION = "stretch" -o $DEBIAN_VERSION = "artful" -o $DEBIAN_VERSION = "bionic" -o ${DEBIAN_VERSION} = "bullseye" -o ${DEBIAN_VERSION} = "bookworm" -o ${DEBIAN_VERSION} = "noble" ]; then
        mv debian/control.systemd debian/control
        mv debian/rules.systemd debian/rules    
    elif [ $DEBIAN_VERSION = "xenial" ] && [[ $VERSION == *2* ]]; then
        curl https://jenkins.percona.com/downloads/PSQLADM-268/openssl -o tools/openssl
        mv debian/install.xenial debian/install
        mv debian/rules.xenial debian/rules
    fi
    dch -m -D "${DEBIAN_VERSION}" --force-distribution -v "2:${VERSION}-${DEB_RELEASE}.${DEBIAN_VERSION}" 'Update distribution'
    unset $(locale|cut -d= -f1)
    if [ ${DEBIAN_VERSION} = "focal" -o ${DEBIAN_VERSION} = "jammy" -o ${DEBIAN_VERSION} = "bullseye" -o ${DEBIAN_VERSION} = "bookworm" -o ${DEBIAN_VERSION} = "noble" ]; then
	sed -i 's:8:9:' debian/compat
        sed -i 's:, dh-systemd::' debian/control
    fi
    if [ ${DEBIAN_VERSION} = "jammy" ]; then
	sed -i 's:8:10:' debian/compat
        sed -i 's:, dh-systemd::' debian/control
    fi
    dpkg-buildpackage -rfakeroot -us -uc -b
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.*deb $WORKDIR/deb
    cp $WORKDIR/*.*deb $CURDIR/deb
}
#main
export GIT_SSL_NO_VERIFY=1
CURDIR=$(pwd)
VERSION_FILE=$CURDIR/proxysql.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
TARBALL=0
BTARBALL=0
SOURCE=0
OS_NAME=
ARCH=
OS=
INSTALL=0
RPM_RELEASE=1.1
DEB_RELEASE=1.1
REVISION=0
GIT_BRANCH="v2.1"
GIT_REPO=https://github.com/percona/proxysql-packaging.git
PAT_REPO=https://github.com/percona/proxysql-admin-tool.git
PAT_TAG="v2.5.3-dev"
PROXYSQL_BRANCH="v2.5.3"
PROXYSQL_REPO="https://github.com/sysown/proxysql.git"
PRODUCT=proxysql2
DEBUG=0
parse_arguments PICK-ARGS-FROM-ARGV "$@"
VERSION=${VERSION}
RELEASE='1'
PRODUCT_FULL=${PRODUCT}-${VERSION}

check_workdir
get_system
install_deps
get_sources
build_srpm
build_source_deb
build_rpm
build_deb
build_tarball
