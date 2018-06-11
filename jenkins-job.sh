#!/bin/bash

BUILD_SCRIPT_VERSION="2.4.3"
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
        webosose_*)
            BUILD_VERSION="webosose"
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
        *_hammerhead)
            BUILD_MACHINE="hammerhead"
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
        *_raspberrypi2)
            BUILD_MACHINE="raspberrypi2"
            ;;
        *_raspberrypi3)
            BUILD_MACHINE="raspberrypi3"
            ;;
        *_raspberrypi3-64)
            BUILD_MACHINE="raspberrypi3-64"
            ;;
        *_workspace-*)
            # global jobs
            ;;
        *_feeds-*)
            # global jobs
            ;;
        *_update-manifest)
            # global jobs
            ;;
        *_release)
            # global job
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine in JOB_NAME: '${JOB_NAME}', it should end with '_a500', '_grouper', '_hammerhead', '_maguro', '_mako', '_qemuarm', '_qemux86', '_qemux86-64', '_tenderloin', '_raspberrypi2' or '_raspberrypi3' or '_raspberrypi3-64'"
            exit 1
            ;;
    esac

    if [ "${BUILD_VERSION}" = "webosose" ] ; then
        BUILD_TYPE="webosose"
        return
    fi
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
        *_workspace-kill-stalled)
            BUILD_TYPE="kill-stalled"
            ;;
        *_feeds-new-staging)
            BUILD_TYPE="new-staging"
            ;;
        *_feeds-sync-to-public)
            BUILD_TYPE="sync-to-public"
            ;;
        *_update-manifest)
            BUILD_TYPE="update-manifest"
            ;;
        *_release)
            BUILD_TYPE="release"
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
    if [ "${BUILD_VERSION}" = "webosose" ] ; then
        BUILD_IMAGES="webos-image"
        return
    fi
    case ${BUILD_MACHINE} in
        grouper|maguro|mako|hammerhead)
            BUILD_IMAGES="luneos-dev-package"
            ;;
        qemuarm|tenderloin|a500|raspberrypi2|raspberrypi3|raspberrypi3-64)
            BUILD_IMAGES="luneos-dev-image"
            ;;
        qemux86|qemux86-64)
            BUILD_IMAGES="luneos-dev-emulator-appliance"
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
    if [ "${BUILD_VERSION}" = "webosose" ] ; then
        TMPDIR=BUILD
    else
        TMPDIR=tmp-glibc
    fi
    # check that tmpfs is mounted and has enough space
    if ! mount | grep -q "${BUILD_TOPDIR}/${TMPDIR} type tmpfs"; then
        [ ! -d ${BUILD_TOPDIR}/${TMPDIR} ] && mkdir -p ${BUILD_TOPDIR}/${TMPDIR}
        mount ${BUILD_TOPDIR}/${TMPDIR}
    fi
    if ! mount | grep -q "${BUILD_TOPDIR}/${TMPDIR} type tmpfs"; then
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} tmpfs isn't mounted in ${BUILD_TOPDIR}/${TMPDIR}"
        exit 1
    fi
    local available_tmpfs=`df -BG ${BUILD_TOPDIR}/${TMPDIR} | grep ${BUILD_TOPDIR}/${TMPDIR} | awk '{print $4}' | sed 's/G$//g'`
    if [ "${available_tmpfs}" -lt 15 ] ; then
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} tmpfs mounted in ${BUILD_TOPDIR}/${TMPDIR} has less than 15G free"
        exit 1
    fi
    local tmpfs tmpfs_allocated_all=0
    for tmpfs in `mount | grep "${TMPDIR} type tmpfs" | awk '{print $3}'`; do
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
        ARCHS="armv7a-vfp-neon,armv5e,i586,arm,armv7a-neon,cortexa7hf-neon-vfpv4,armv7ahf-neon,core2-64,aarch64"
        DU1=`du -hs sstate-cache/`
        echo "$DU1"
        OPENSSL="find sstate-cache/ -name '*:openssl:*populate_sysroot*tgz'"
        ARCHIVES1=`sh -c "${OPENSSL}"`; echo "number of openssl archives: `echo "$ARCHIVES1" | wc -l`"; echo "$ARCHIVES1"
        openembedded-core/scripts/sstate-cache-management.sh -L --cache-dir=sstate-cache -y -d --extra-archs=${ARCHS// /,} || true
        DU2=`du -hs sstate-cache/`
        echo "$DU2"
        ARCHIVES2=`sh -c "${OPENSSL}"`; echo "number of openssl archives: `echo "$ARCHIVES2" | wc -l`"; echo "$ARCHIVES2"

        mkdir old || true
        umount tmp-glibc || true
        mv -f cache/bb_codeparser.dat* bitbake.lock pseudodone tmp-glibc* old || true
        rm -rf old

        echo "BEFORE:"
        echo "number of openssl archives: `echo "$ARCHIVES1" | wc -l`"; echo "$ARCHIVES1"
        echo "AFTER:"
        echo "number of openssl archives: `echo "$ARCHIVES2" | wc -l`"; echo "$ARCHIVES2"
        echo "BEFORE: $DU1, AFTER: $DU2"
    fi
    echo "Cleanup finished"
}

function run_compare-signatures {
    cd ${BUILD_TOPDIR}
    . ./setup-env
    openembedded-core/scripts/sstate-diff-machines.sh --targets=luneos-dev-image --tmpdir=tmp-glibc/ --analyze --machines="hammerhead mako qemux86" | tee log.compare-signatures
    openembedded-core/scripts/sstate-diff-machines.sh --targets=luneos-dev-image --tmpdir=tmp-glibc/ --analyze --machines="raspberrypi2 raspberrypi3 mako" | tee -a log.compare-signatures
    if [ ! -d sstate-diff ]; then mkdir sstate-diff; fi
    mv tmp-glibc/sstate-diff/* sstate-diff
    mv log.compare-signatures sstate-diff

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
    if [ "${BUILD_VERSION}" = "unstable" ] ; then
      echo 'IMAGE_FSTYPES_forcevariable_qemux86 = "tar.gz wic.vmdk"' >> ${BUILD_TOPDIR}/conf/local.conf
      echo 'IMAGE_FSTYPES_forcevariable_qemux86-64 = "tar.gz wic.vmdk"' >> ${BUILD_TOPDIR}/conf/local.conf
    else
      echo 'IMAGE_FSTYPES_forcevariable_qemux86 = "tar.gz vmdk"' >> ${BUILD_TOPDIR}/conf/local.conf
      echo 'IMAGE_FSTYPES_forcevariable_qemux86-64 = "tar.gz vmdk"' >> ${BUILD_TOPDIR}/conf/local.conf
    fi
    echo 'IMAGE_FSTYPES_forcevariable_raspberrypi2 = "rpi-sdimg"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'IMAGE_FSTYPES_forcevariable_raspberrypi3 = "rpi-sdimg"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'IMAGE_FSTYPES_forcevariable_raspberrypi3-64 = "rpi-sdimg"' >> ${BUILD_TOPDIR}/conf/local.conf

    cat >> ${BUILD_TOPDIR}/conf/local.conf << EOF
BB_DISKMON_DIRS = "\
    STOPTASKS,${TMPDIR},1G,100K \
    STOPTASKS,${DL_DIR},1G,100K \
    STOPTASKS,${SSTATE_DIR},1G,100K \
    STOPTASKS,/tmp,100M,100K \
    ABORT,${TMPDIR},100M,1K \
    ABORT,${DL_DIR},100M,1K \
    ABORT,${SSTATE_DIR},100M,1K \
    ABORT,/tmp,10M,1K"
EOF
}

function run_rsync {
    if [ "${BUILD_VERSION}" = "stable" ] ; then
        scripts/staging_sync.sh ${BUILD_TOPDIR}/tmp-glibc/deploy      jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}-staging/wip
    else
        scripts/staging_sync.sh ${BUILD_TOPDIR}/tmp-glibc/deploy      jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/
    fi

    rsync -avir --delete ${BUILD_TOPDIR}/sstate-cache/                jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/sstate-cache/
    rsync -avir --no-links --exclude '*.done' --exclude git2 \
                           --exclude svn --exclude bzr downloads      jenkins@milla.nao:~/htdocs/sources/
}

function run_update-manifest() {
    echo "BUILD_VERSION = $BUILD_VERSION"
    echo "BUILD_ID = $BUILD_ID"
    echo "SUPPORTED_MACHINES = $SUPPORTED_MACHINES"

    if [ "${BUILD_VERSION}" = "testing" ] ; then
        # Cleanup any left over artifacts
        rm -vf manifest.json device-images.json

        echo "Updating change manifest for testing"
        wget http://build.webos-ports.org/luneos-testing/manifest.json -O manifest.json
        scripts/update-manifest.py -n ${BUILD_ID} -r luneos-testing-${BUILD_ID} manifest.json

        echo "Updating device image manifest for testing for machines ${SUPPORTED_MACHINES}"
        wget http://build.webos-ports.org/luneos-testing/device-images.json -O device-images.json
        for machine in ${SUPPORTED_MACHINES} ; do
            image_path=`ssh jenkins@milla.nao find /home2/jenkins/htdocs/builds/luneos-testing/images/$machine -type f -name 'luneos-dev-package-$machine*' ! -name 'luneos-dev-package-$machine.zip' ! -name '*.md5' | sort -r | head -n 1`
            if [ -z "$image_path" ] ; then
                echo "Couldn't find image for machine $machine"
                exit 1
            fi

            image=`basename $image_path`
            image_url="http://build.webos-ports.org/luneos-testing/images/$machine/$image"

            # Extract image md5 checksum
            wget ${image_url}.md5 -O ${image}.md5
            image_md5=`cat ${image}.md5 | cut -d' ' -f1`

            scripts/update-manifest.py -d -v ${BUILD_ID} -m $machine --image=$image_url --image-md5=$image_md5 device-images.json
            if [ ! $? -eq 0 ] ; then
                echo "Failed to update device image manifest!"
                exit 1
            fi
            rm -vf ${image}.md5
        done

        # Sync everything to the public server
        scp manifest.json jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/
        scp device-images.json jenkins@milla.nao:~/htdocs/builds/luneos-${BUILD_VERSION}/
        rm -vf manifest.json device-images.json
    fi
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
        exit 1
    fi

    for FEED in $FEED_NUMBERS; do
        bash -x scripts/staging_sync_to_public_feed.sh jenkins@milla.nao $FEED
    done
}

function run_release {
    if [ -z "${FEED_NUMBER}" -o -z "${RELEASE_NAME}" ]; then
        echo "ERROR: FEED_NUMBER, RELEASE_NAME cannot be empty"
        exit 1
    fi
    ssh jenkins@milla.nao "mkdir ~/htdocs/builds/releases/${RELEASE_NAME}"
    ssh jenkins@milla.nao "cp -ra ~/htdocs/builds/luneos-stable-staging/${FEED_NUMBER}/* ~/htdocs/builds/releases/${RELEASE_NAME}"
    ssh jenkins@milla.nao "rm -rf ~/htdocs/builds/releases/${RELEASE_NAME}/ipk"
    if [ -n "${UNSUPPORTED_MACHINES}" ] ; then
        ssh jenkins@milla.nao "for UNSUPPORTED_MACHINE in ${UNSUPPORTED_MACHINES}; do rm -rf ~/htdocs/builds/releases/${RELEASE_NAME}/images/\${UNSUPPORTED_MACHINE}; done"
    fi
}

function delete_unnecessary_images {
    rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/README_-_DO_NOT_DELETE_FILES_IN_THIS_DIRECTORY.txt
    case ${BUILD_MACHINE} in
        grouper|maguro|mako|hammerhead)
            # keep only *-package.zip
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-dev-image-*
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
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-dev-image-*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/bzImage*
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/modules-*
            ;;
        raspberrypi2|raspberrypi3|raspberrypi3-64)
            # keep only luneos-dev-image-raspberrypiX.rpi-sdimg
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-image-*.tar.gz
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-image-*.ext3
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-image-*.manifest
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-dev-image-*.tar.gz
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-dev-image-*.ext3
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/luneos-dev-image-*.manifest
            rm -rfv tmp-glibc/deploy/images/${BUILD_MACHINE}/modules-*
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine: '${BUILD_MACHINE}', script doesn't know which images to build"
            exit 1
            ;;
    esac
}
function delete_unnecessary_images_webosose {
    rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/README_-_DO_NOT_DELETE_FILES_IN_THIS_DIRECTORY.txt
    case ${BUILD_MACHINE} in
        qemux86|qemux86-64)
            # keep only vmdk
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.rootfs.*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ext3
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.manifest
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.tar.gz
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/bzImage*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/modules-*
            ;;
        raspberrypi3)
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/Image*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/modules-*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/bcm2835-bootfiles
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.rootfs.*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ext3
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.manifest
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.tar.gz
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
    if ps aux | grep "${BUILD_TOPDIR}/bitbake/bin/[b]itbake"; then
        if [ "${BUILD_TYPE}" = "kill-stalled" ] ; then
            echo "WARN: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} There is some bitbake process already running from '${BUILD_TOPDIR}', maybe some stalled process from aborted job?"
        else
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} There is some bitbake process already running from '${BUILD_TOPDIR}', maybe some stalled process from aborted job?"
            exit 1
        fi
    fi
}

function kill_stalled_bitbake_processes {
    if ps aux | grep "${BUILD_TOPDIR}/bitbake/bin/[b]itbake" ; then
        local BITBAKE_PIDS=`ps aux | grep "${BUILD_TOPDIR}/bitbake/bin/[b]itbake" | awk '{print $2}' | xargs`
        [ -n "${BITBAKE_PIDS}" ] && kill ${BITBAKE_PIDS}
        sleep 10
        ps aux | grep "${BUILD_TOPDIR}/bitbake/bin/[b]itbake"
        local BITBAKE_PIDS=`ps aux | grep "${BUILD_TOPDIR}/bitbake/bin/[b]itbake" | awk '{print $2}' | xargs`
        [ -n "${BITBAKE_PIDS}" ] && kill -9 ${BITBAKE_PIDS}
        ps aux | grep "${BUILD_TOPDIR}/bitbake/bin/[b]itbake"
    fi
}

function run_webosose {
    # don't use webos-ports as a ${BUILD_DIR}
    BUILD_TOPDIR="${BUILD_WORKSPACE}"
    BUILD_TIME_LOG=${BUILD_TOPDIR}/time.txt

    declare -i RESULT=0
    sanity-check
    if [ "${BUILD_MACHINE}" = "qemux86" ] ; then
        # work around the issues in webOS OSE and allow to build for qemux86
        sed -i "s#Machines = ['raspberrypi3']#Machines = ['raspberrypi3','qemux86']#g" weboslayers.py
    fi
    ./mcf ${BUILD_MACHINE}
    ./mcf --command update --clean
    if [ "${BUILD_MACHINE}" = "qemux86" ] ; then
        # work around the issues in webOS OSE and allow to build for qemux86
        sed -i 's#PACKAGECONFIG ??= "avoutputd"#PACKAGECONFIG_rpi = "avoutputd"#g' meta-webosose/meta-webos/recipes-webos/umediaserver/umediaserver.bb
        # undo the weboslayers.py change so that jenkins github plugin can do clean update in the next build
        git checkout weboslayers.py
    fi
    . ./oe-init-build-env
    export MACHINE="${BUILD_MACHINE}"

    /usr/bin/time -f "${BUILD_TIME_STR}" \
        bitbake -k ${BUILD_IMAGES} 2>&1 | tee /dev/stderr | grep '^TIME:' >> ${BUILD_TIME_LOG}
    RESULT+=${PIPESTATUS[0]}

    delete_unnecessary_images_webosose

    rsync -avir ${BUILD_TOPDIR}/BUILD/deploy/images/${BUILD_MACHINE}/               jenkins@milla.nao:~/htdocs/builds/webosose/${BUILD_MACHINE}/
    rsync -avir --no-links --exclude '*.done' --exclude git2 \
                --exclude svn --exclude bzr ${BUILD_TOPDIR}/downloads/              jenkins@milla.nao:~/htdocs/builds/webosose/sources/

    umount ${BUILD_TOPDIR}/BUILD
    exit ${RESULT}
}

print_timestamp start
parse_job_name
sanity_check_workspace
set_images

echo "INFO: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Running: '${BUILD_TYPE}', machine: '${BUILD_MACHINE}', version: '${BUILD_VERSION}', images: '${BUILD_IMAGES}'"

# restrict it to 15GB to prevent triggering OOM killer on our jenkins server (which can kill some other
# process instead of the build itself)
ulimit -v 15728640
ulimit -m 15728640

case ${BUILD_TYPE} in
    webosose)
        run_webosose
        ;;
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
    release)
        run_release
        ;;
    new-staging)
        run_new-staging
        ;;
    sync-to-public)
        run_sync-to-public
        ;;
    kill-stalled)
        kill_stalled_bitbake_processes
        ;;
    build)
        run_build
        ;;
    update-manifest)
        run_update-manifest
        ;;
    *)
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized build type: '${BUILD_TYPE}', script doesn't know how to execute such job"
        exit 1
        ;;
esac
