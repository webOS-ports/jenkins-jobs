#!/bin/bash

BUILD_SCRIPT_VERSION="1.0.0"
BUILD_SCRIPT_NAME=`basename ${0}`

pushd `dirname $0` > /dev/null
BUILD_WORKSPACE=`pwd -P`
popd > /dev/null

BUILD_DIR="webos-ports"
BUILD_TOPDIR="${BUILD_WORKSPACE}/${BUILD_DIR}"

# These are used by in following functions, declare them here so that
# they are defined even when we're only sourcing this script
BUILD_TIME_STR="TIME: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} %e %S %U %P %c %w %R %F %M %x %C"

BUILD_TIMESTAMP_START=`date -u +%s`
BUILD_TIMESTAMP_OLD=${BUILD_TIMESTAMP_START}

BUILD_TIME_LOG=${BUILD_TOPDIR}/time.txt

function print_timestamp {
    BUILD_TIMESTAMP=`date -u +%s`
    BUILD_TIMESTAMPH=`date -u +%Y%m%dT%TZ`

    local BUILD_TIMEDIFF=`expr ${BUILD_TIMESTAMP} - ${BUILD_TIMESTAMP_OLD}`
    local BUILD_TIMEDIFF_START=`expr ${BUILD_TIMESTAMP} - ${BUILD_TIMESTAMP_START}`
    BUILD_TIMESTAMP_OLD=${BUILD_TIMESTAMP}
    printf "TIME: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} ${1}: ${BUILD_TIMESTAMP}, +${BUILD_TIMEDIFF}, +${BUILD_TIMEDIFF_START}, ${BUILD_TIMESTAMPH}\n" | tee -a ${BUILD_TIME_LOG}
}

function parse_job_name {
    case ${JOB_NAME} in
        luneos-stable_*)
            BUILD_VERSION="stable"
            ;;
        luneos-testing_*)
            BUILD_VERSION="testing"
            ;;
        luneos-unstable_*)
            BUILD_VERSION="unstable"
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized version in JOB_NAME: '${JOB_NAME}', it should start with luneos- and 'stable', 'testing' or 'unstable'"
            exit 1
            ;;
    esac

    case ${JOB_NAME} in
        *_a500)
            BUILD_MACHINE="a500"
            ;;
        *_grouper)
            BUILD_MACHINE="grouper"
            ;;
        *_maguro)
            BUILD_MACHINE="maguro"
            ;;
        *_mako)
            BUILD_MACHINE="mako"
            ;;
        *_qemuarm)
            BUILD_MACHINE="qemuarm"
            ;;
        *_qemux86)
            BUILD_MACHINE="qemux86"
            ;;
        *_qemux86-64)
            BUILD_MACHINE="qemux86-64"
            ;;
        *_tenderloin)
            BUILD_MACHINE="tenderloin"
            ;;
        *_workspace-*)
            # global jobs
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine in JOB_NAME: '${JOB_NAME}', it should end with '_a500', '_grouper', '_maguro', '_mako', '_qemuarm', '_qemux86', '_qemux86-64' or '_tenderloin'"
            exit 1
            ;;
    esac

    case ${JOB_NAME} in
        *_workspace-cleanup)
            BUILD_TYPE="cleanup"
            ;;
        *_workspace-compare-signatures)
            BUILD_TYPE="compare-signatures"
            ;;
        *_workspace-prepare)
            BUILD_TYPE="prepare"
            ;;
        *_workspace-rsync)
            BUILD_TYPE="rsync"
            ;;
        *_feeds-new-staging)
            BUILD_TYPE="new-staging"
            ;;
        *_feeds-sync-to-public)
            BUILD_TYPE="sync-to-public"
            ;;
        *)
            BUILD_TYPE="build"
            ;;
    esac
}

function set_images {
    if [ "${BUILD_TYPE}" != "build" ] ; then
        return
    fi
    case ${BUILD_MACHINE} in
        grouper|maguro|mako)
            BUILD_IMAGES="webos-ports-dev-package"
            ;;
        qemuarm|tenderloin|a500)
            BUILD_IMAGES="webos-ports-dev-image"
            ;;
        qemux86|qemux86-64)
            BUILD_IMAGES="webos-ports-dev-emulator-appliance"
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine: '${BUILD_MACHINE}', script doesn't know which images to build"
            exit 1
            ;;
    esac
}

function run_build {
    declare -i RESULT=0
    sanity-check
    if [ "${BUILD_VERSION}" = "stable" ] ; then
        scripts/staging_update.sh
        . scripts/staging_header.sh
    else
        make update 2>&1
        export CURRENT_STAGING=0
    fi
    export WEBOS_DISTRO_BUILD_ID="${BUILD_VERSION}-${CURRENT_STAGING}-${BUILD_NUMBER}"
    cd ${BUILD_TOPDIR}
    . ./setup-env
    export MACHINE="${BUILD_MACHINE}"
    /usr/bin/time -f "${BUILD_TIME_STR}" \
        bitbake -k ${BUILD_IMAGES} 2>&1 | tee /dev/stderr | grep '^TIME:' >> ${BUILD_TIME_LOG}
    RESULT+=${PIPESTATUS[0]}
    delete_unnecessary_images
    exit ${RESULT}
}

function sanity-check {
    # check that tmpfs is mounted and has enough space
    if ! mount | grep -q "${BUILD_TOPDIR}/tmp-glibc type tmpfs"; then
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} tmpfs isn't mounted in ${BUILD_TOPDIR}/tmp-glibc"
        exit 1
    fi
    local available_tmpfs=`df -BG ${BUILD_TOPDIR}/tmp-glibc | grep ${BUILD_TOPDIR}/tmp-glibc | awk '{print $4}' | sed 's/G$//g'`
    if [ "${available_tmpfs}" -lt 15 ] ; then
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} tmpfs mounted in ${BUILD_TOPDIR}/tmp-glibc has less than 15G free"
        exit 1
    fi
    local tmpfs tmpfs_allocated_all=0
    for tmpfs in `mount | grep "tmp-glibc type tmpfs" | awk '{print $3}'`; do
        df -BG $tmpfs | grep $tmpfs;
        local tmpfs_allocated=`df -BG $tmpfs | grep $tmpfs | awk '{print $3}' | sed 's/G$//g'`
        tmpfs_allocated_all=`expr ${tmpfs_allocated_all} + ${tmpfs_allocated}`
    done
    # we have 2 tmpfs mounts with max size 80GB, but only 97GB of RAM, show error when more than 65G is already allocated
    # in them
    if [ "${tmpfs_allocated_all}" -gt 65 ] ; then
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} sum of allocated space in tmpfs mounts is more than 65G, clean some builds"
        exit 1
    fi
}

function run_cleanup {
    if [ -d ${BUILD_TOPDIR} ] ; then
        cd ${BUILD_TOPDIR};
        du -hs sstate-cache
        openembedded-core/scripts/sstate-cache-management.sh -L --cache-dir=sstate-cache -d -y || true
        du -hs sstate-cache
        rm -f bitbake.lock pseudodone
        if [ -d tmp-glibc ] ; then
            cd tmp-glibc;
            mkdir old || true
            mv -f cooker* deploy log pkgdata sstate-control stamps sysroots work work-shared abi_version qa.log saved_tmpdir cache/default-glibc cache/bb_codeparser* cache/local_file_checksum_cache.dat old || true
            #~/daemonize.sh rm -rf old
            rm -rf old
        fi
    fi
    echo "Cleanup finished"
}

function run_compare-signatures {
    cd ${BUILD_TOPDIR}
    . ./setup-env
    openembedded-core/scripts/sstate-diff-machines.sh --machines="qemux86 maguro grouper" --targets=webos-ports-dev-image --tmpdir=tmp-glibc/;
    if [ ! -d sstate-diff ]; then mkdir sstate-diff; fi
    mv tmp-glibc/sstate-diff/* sstate-diff

    rsync -avir sstate-diff jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/
}

function run_prepare {
    [ -f Makefile ] && echo "Makefile exists (ok)" || wget https://raw.github.com/webOS-ports/webos-ports-setup/${BUILD_VERSION}/Makefile
    sed -i "s#^BRANCH_COMMON.*#BRANCH_COMMON = ${BUILD_VERSION}#g" Makefile

    make update-common

    echo "UPDATE_CONFFILES_ENABLED = 1" > config.mk
    echo "RESET_ENABLED = 1" >> config.mk
    [ -d ${BUILD_TOPDIR} ] && echo "webos-ports already checked out (ok)" || make setup-webos-ports 2>&1
    make update-conffiles 2>&1

    cp common/conf/local.conf ${BUILD_TOPDIR}/conf/local.conf
    sed -i 's/#PARALLEL_MAKE.*/PARALLEL_MAKE = "-j 8"/'          ${BUILD_TOPDIR}/conf/local.conf
    sed -i 's/#BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = "4"/' ${BUILD_TOPDIR}/conf/local.conf
    sed -i 's/# INHERIT += "rm_work"/INHERIT += "rm_work"/' ${BUILD_TOPDIR}/conf/local.conf

    sed -i '/^DISTRO_FEED_/d' ${BUILD_TOPDIR}/conf/local.conf
    echo "DISTRO_FEED_PREFIX=\"luneos-${BUILD_VERSION}\"" >> ${BUILD_TOPDIR}/conf/local.conf
    echo "DISTRO_FEED_URI=\"http://build.webos-ports.org/luneos-${BUILD_VERSION}/ipk/\"" >> ${BUILD_TOPDIR}/conf/local.conf

    echo 'BB_GENERATE_MIRROR_TARBALLS = "1"' >> ${BUILD_TOPDIR}/conf/local.conf

    # remove default SSTATE_MIRRORS ?= "file://.* http://build.webos-ports.org/luneos-${BUILD_VERSION}/sstate-cache/PATH"
    sed -i '/^SSTATE_MIRRORS/d' ${BUILD_TOPDIR}/conf/local.conf

    if [ "${BUILD_VERSION}" = "unstable" ] ; then
        echo "SSTATE_MIRRORS ?= \"\
        file://.* http://build.webos-ports.org/luneos-${BUILD_VERSION}/sstate-cache/PATH \
        \"" >> ${BUILD_TOPDIR}/conf/local.conf
    elif [ "${BUILD_VERSION}" = "testing" ] ; then
        echo "SSTATE_MIRRORS ?= \"\
        file://.* http://build.webos-ports.org/luneos-${BUILD_VERSION}/sstate-cache/PATH \n\
        file://.* http://build.webos-ports.org/luneos-unstable/sstate-cache/PATH \n\
        \"" >> ${BUILD_TOPDIR}/conf/local.conf
    elif [ "${BUILD_VERSION}" = "stable" ] ; then
        echo "SSTATE_MIRRORS ?= \"\
        file://.* http://build.webos-ports.org/luneos-${BUILD_VERSION}/sstate-cache/PATH \n\
        file://.* http://build.webos-ports.org/luneos-testing/sstate-cache/PATH \n\
        file://.* http://build.webos-ports.org/luneos-unstable/sstate-cache/PATH \n\
        \"" >> ${BUILD_TOPDIR}/conf/local.conf
    fi

    echo 'CONNECTIVITY_CHECK_URIS = ""' >> ${BUILD_TOPDIR}/conf/local.conf
    if [ ! -d ${BUILD_TOPDIR}/buildhistory/ ] ; then
        cd ${BUILD_TOPDIR}
        git clone git@github.com:webOS-ports/buildhistory.git
        cd buildhistory;
        git checkout -b luneos-${BUILD_VERSION} origin/luneos-${BUILD_VERSION} || git checkout -b luneos-${BUILD_VERSION} origin/webos-ports-setup
        cd ../..
    fi

    echo 'BUILDHISTORY_COMMIT ?= "1"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'BUILDHISTORY_COMMIT_AUTHOR ?= "Martin Jansa <Martin.Jansa@gmail.com>"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo "BUILDHISTORY_PUSH_REPO ?= \"origin luneos-${BUILD_VERSION}\"" >> ${BUILD_TOPDIR}/conf/local.conf

    echo 'IMAGE_FSTYPES_forcevariable = "tar.gz"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'IMAGE_FSTYPES_forcevariable_qemux86 = "tar.gz vmdk"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'IMAGE_FSTYPES_forcevariable_qemux86-64 = "tar.gz vmdk"' >> ${BUILD_TOPDIR}/conf/local.conf
}

function run_rsync {
    if [ "${BUILD_VERSION}" = "stable" ] ; then
        scripts/staging_sync.sh ${BUILD_TOPDIR}/tmp-glibc/deploy      jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}-staging/wip
    else
        scripts/staging_sync.sh ${BUILD_TOPDIR}/tmp-glibc/deploy      jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/
    fi

    rsync -avir --delete ${BUILD_TOPDIR}/sstate-cache                 jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/
    rsync -avir --no-links --exclude '*.done' --exclude git2 \
                           --exclude svn --exclude bzr downloads      jenkins@milla.nao:~/htdocs/sources/
}

function run_new-staging {
    . scripts/staging_header.sh

    DATE=`date +%s`
    CURRENT_STAGING_NUMBER=`echo ${CURRENT_STAGING} | sed 's/^0*//g'`

    wget "https://raw.github.com/webOS-ports/changelog/master/manifest.json?time=$DATE" -O manifest.json.${CURRENT_STAGING}

    # if ! grep -q "\"platformVersion\": ${CURRENT_STAGING_NUMBER},$" manifest.json.${CURRENT_STAGING}; then
    if ! grep -q "\"version\": ${CURRENT_STAGING_NUMBER},$" manifest.json.${CURRENT_STAGING}; then
        echo "ERROR: https://raw.github.com/webOS-ports/changelog/master/manifest.json doesn't have changelog for staging ${CURRENT_STAGING} yet, update it first and then re-execute this job"
        exit 1
    fi

    mv manifest.json.${CURRENT_STAGING} ${BUILD_TOPDIR}/tmp-glibc/deploy/
    ln -sf manifest.json.${CURRENT_STAGING} ${BUILD_TOPDIR}/tmp-glibc/deploy/manifest.json

    bash -x scripts/staging_new.sh jenkins@milla.nao
}

function run_sync-to-public {
    if [ -z "$FEED_NUMBERS" ]; then
        echo "ERROR: FEED_NUMBERS wasn't set"
    fi

    for FEED in $FEED_NUMBERS; do
        bash -x scripts/staging_sync_to_public_feed.sh jenkins@milla.nao $FEED
    done
}

function delete_unnecessary_images {
    rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/README_-_DO_NOT_DELETE_FILES_IN_THIS_DIRECTORY.txt
    case ${BUILD_MACHINE} in
        grouper|maguro|mako)
            # keep only *-package.zip
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/webos-ports-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/webos-ports-dev-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/zImage*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/modules-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/initramfs*
            ;;
        qemuarm|tenderloin|a500)
            # keep zImage and rootfs.tar.gz
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/initramfs*
            ;;
        qemux86|qemux86-64)
            # keep only image.zip
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/webos-ports-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/webos-ports-dev-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/bzImage*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/modules-*
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine: '${BUILD_MACHINE}', script doesn't know which images to build"
            exit 1
            ;;
    esac
}

function sanity_check_workspace {
    # BUILD_TOPDIR path should contain BUILD_VERSION, otherwise there is probably incorrect WORKSPACE in jenkins config
    if ! echo ${BUILD_TOPDIR} | grep -q "/luneos-${BUILD_VERSION}/" ; then
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} BUILD_TOPDIR: '${BUILD_TOPDIR}' path should contain luneos-${BUILD_VERSION} directory, is workspace set correctly in jenkins config?"
	exit 1
    fi
}

print_timestamp start
parse_job_name
sanity_check_workspace
set_images

echo "INFO: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Running: '${BUILD_TYPE}', machine: '${BUILD_MACHINE}', version: '${BUILD_VERSION}', images: '${BUILD_IMAGES}'"

case ${BUILD_TYPE} in
    cleanup)
        run_cleanup
        ;;
    compare-signatures)
        run_compare-signatures
        ;;
    prepare)
        run_prepare
        ;;
    rsync)
        run_rsync
        ;;
    new-staging)
        run_new-staging
        ;;
    sync-to-public)
        run_sync-to-public
        ;;
    build)
        run_build
        ;;
    *)
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized build type: '${BUILD_TYPE}', script doesn't know how to execute such job"
        exit 1
        ;;
esac
