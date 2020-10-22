#!/bin/bash

BUILD_SCRIPT_VERSION="2.6.22"
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

FILESERVER=jenkins@milla.nao.TODO
FILESERVER_ROOT=/media/ra_build_share/
FILESERVER_BUILDS=${FILESERVER_ROOT}/wop-build
FILESERVER_SOURCES=${FILESERVER_ROOT}/wop-sources

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
        LuneOS/luneos-stable_*)
            BUILD_VERSION="stable"
            ;;
        LuneOS/luneos-testing_*)
            BUILD_VERSION="testing"
            ;;
        LuneOS/luneos-unstable_*)
            BUILD_VERSION="unstable"
            ;;
        webosose_*)
            BUILD_VERSION="webosose"
            ;;
        LuneOS/halium-luneos-5.1-build)
            BUILD_VERSION="5.1"
            ;;
        LuneOS/halium-luneos-7.1-build)
            BUILD_VERSION="7.1"
            ;;
        LuneOS/halium-luneos-rsync)
            BUILD_VERSION="all"
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
        *_mido)
            BUILD_MACHINE="mido"
            ;;
        *_onyx)
            BUILD_MACHINE="onyx"
            ;;
        *_pinephone)
            BUILD_MACHINE="pinephone"
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
        *_rosy)
            BUILD_MACHINE="rosy"
            ;;
        *_tenderloin)
            BUILD_MACHINE="tenderloin"
            ;;
        *_tissot)
            BUILD_MACHINE="tissot"
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
        *_raspberrypi4)
            BUILD_MACHINE="raspberrypi4"
            ;;
        *_raspberrypi4-64)
            BUILD_MACHINE="raspberrypi4-64"
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
        LuneOS/halium-luneos-*)
            # global job
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine in JOB_NAME: '${JOB_NAME}', it should end with '_a500', '_grouper', '_hammerhead', '_maguro', '_mako', '_mido', '_onyx', '_pinephone', '_qemuarm', '_qemux86', '_qemux86-64', '_rosy', '_tenderloin', '_tissot', '_raspberrypi2' or '_raspberrypi3' or '_raspberrypi3-64' or '_raspberrypi4' or '_raspberrypi4-64'"
            exit 1
            ;;
    esac

    if [ "${BUILD_VERSION}" = "webosose" ] ; then
        BUILD_TYPE="webosose"
        return
    fi
    case ${JOB_NAME} in
        *_workspace-sstate-cleanup)
            BUILD_TYPE="sstate-cleanup"
            ;;
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
        LuneOS/halium-luneos-*-build)
            BUILD_TYPE="halium"
            ;;
        LuneOS/halium-luneos-rsync)
            BUILD_TYPE="halium-rsync"
            ;;
        *)
            BUILD_TYPE="build"
            ;;
    esac
}

function set_images {
    if [ "${BUILD_TYPE}" != "build" -a "${BUILD_TYPE}" != "webosose" ] ; then
        return
    fi
    if [ "${BUILD_VERSION}" = "webosose" ] ; then
        BUILD_IMAGES="webos-image webos-image-devel"
        return
    fi
    case ${BUILD_MACHINE} in
        grouper|maguro|mako|hammerhead|mido|onyx|rosy|tissot)
            BUILD_IMAGES="luneos-dev-package"
            ;;
        qemuarm|tenderloin|a500|pinephone|raspberrypi2|raspberrypi3|raspberrypi3-64|raspberrypi4|raspberrypi4-64)
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
        bitbake -k ${BUILD_IMAGES} 2>&1 | tee /dev/stderr | tee bitbake.log | grep '^TIME:' >> ${BUILD_TIME_LOG}
    BITBAKE_RETURN=${PIPESTATUS[0]}
    if [ "${BITBAKE_RETURN}" -ne 0 ] ; then
        # Unfortunately the changes from:
        # https://patchwork.openembedded.org/patch/143430/
        # https://patchwork.openembedded.org/patch/143431/
        # aren't going to be merged, so we need to deal with this mess :(
        #
        # grep if all ERRORS are of this kind which is safe to ignore in our infra where fileserver sometimes drops connection when fetching sstate archive
        # ERROR: bluez5-5.50-r0 do_package_setscene: Fetcher failure: Unable to find file file://17/sstate:bluez5:core2-32-webos-linux:5.50:r0:core2-32:3:172ab064092514ef7c29f1ee396880790b698e18d3d8bd513c7cd2c0eef39a85_package.tgz;downloadfilename=17/sstate:bluez5:core2-32-webos-linux:5.50:r0:core2-32:3:172ab064092514ef7c29f1ee396880790b698e18d3d8bd513c7cd2c0eef39a85_package.tgz anywhere. The paths that were searched were:
        #  /home/jenkins/workspace/luneos-testing/webos-ports/sstate-cache
        #  /home/jenkins/workspace/luneos-testing/webos-ports/sstate-cache
        # ERROR: bluez5-5.50-r0 do_package_setscene: No suitable staging package found
        # ERROR: Logfile of failure stored in: /home/jenkins/workspace/luneos-testing/webos-ports/tmp-glibc/work/core2-32-webos-linux/bluez5/5.50-r0/temp/log.do_package_setscene.547
        if grep -q "Summary: There were .* ERROR messages shown, returning a non-zero exit code." bitbake.log; then
            ERRORS_FOUND=`grep "Summary: There were .* ERROR messages shown, returning a non-zero exit code." bitbake.log | sed 's/Summary: There were \(.*\) ERROR messages shown, returning a non-zero exit code./\1/g'`
            ERRORS_SETSCENE=`grep -c "^ERROR: .* do_.*_setscene: Fetcher failure: Unable to find file" bitbake.log`
            ERRORS_SETSCENE2=`grep -c "^ERROR: .* do_.*_setscene: No suitable staging package found" bitbake.log`
            echo "There were ${ERRORS_FOUND} ERROR messages in bitbake log, from that ${ERRORS_SETSCENE} 'do_.*_setscene: Fetcher failures: ' and ${ERRORS_SETSCENE2} 'do_.*_setscene: No suitable staging package found' messages"
            if [ ${ERRORS_FOUND} -ne `expr ${ERRORS_SETSCENE} + ${ERRORS_SETSCENE2}` ] ; then
                echo "There were some other kinds of ERROR messages will respect the return code from bitbake:"
                grep ERROR: bitbake.log | grep -v "^ERROR: .* do_.*_setscene: Fetcher failure: Unable to find file" | grep -v "^ERROR: .* do_.*_setscene: No suitable staging package found"
                RESULT+=${BITBAKE_RETURN}
            else
                echo "All reported errors were about setscene failing to fetch sstate, we're going to ignore bitbake return code"
                echo "It's relatively safe to ignore these error messages (the real task was executed instead, so the build finished OK and image was created correctly). It usually happens when e.g. our fileserver first shows that the sstate exists (over http) and then when bitbake is fetching the archive fileserver is temporarily unreachable or drops the connection. More details in https://patchwork.openembedded.org/patch/143431/ https://patchwork.openembedded.org/patch/143430/ which weren't applied, see why in: https://marc.info/?l=openembedded-core&m=150408018331252&w=2 https://marc.info/?l=openembedded-core&m=150407969131099&w=2"
            fi
        else
            RESULT+=${BITBAKE_RETURN}
        fi
    fi
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
        mkdir old || true
        umount tmp-glibc || true
        mv -f cache/bb_codeparser.dat* bitbake.lock pseudodone tmp-glibc* sstate-diff* old || true
        rm -rf old
    fi
    echo "Cleanup finished"
}

function run_sstate-cleanup {
    if [ -d ${BUILD_TOPDIR} ] ; then
        cd ${BUILD_TOPDIR};
        # jenkins@bonaire:~/workspace$ find luneos-shared/sstate-cache/ ! -type d  | sed 's/.*sstate:[^:]*://g' | sed 's/-webos-linux.*$//g' | grep -v ^: | grep -v ^x86_64-linux: | sort -u  | xargs  | sed 's/ /,/g'
        # aarch64,aarch64-halium,aarch64-rpi,all,core2-64,cortexa7t2hf-neon-vfpv4,cortexa8t2hf-neon-halium,hammerhead,i586,mako,mido,onyx,pinephone,qemux86,qemux86_64,raspberrypi2,raspberrypi3,raspberrypi3_64,raspberrypi4,raspberrypi4_64,rosy,tenderloin,tissot,x86_64
        # unstable uses core2-32 instead of i586
        # jenkins@bonaire:~/workspace$ find luneos-unstable/webos-ports/sstate-cache/ ! -type d  | sed 's/.*sstate:[^:]*://g' | sed 's/-webos-linux.*$//g' | grep -v ^: | grep -v ^x86_64-linux: | sort -u  | xargs  | sed 's/ /,/g'
        # aarch64,aarch64-halium,aarch64-rpi,all,core2-32,core2-64,cortexa7t2hf-neon-vfpv4,cortexa8t2hf-neon-halium,hammerhead,mako,mido,onyx,pinephone,qemux86,qemux86_64,raspberrypi2,raspberrypi3,raspberrypi3_64,raspberrypi4,raspberrypi4_64,rosy,tenderloin,tissot,x86_64
        # find luneos-shared/sstate-cache/ luneos-unstable/webos-ports/sstate-cache/ ! -type d  | sed 's/.*sstate:[^:]*://g' | sed 's/-webos-linux.*$//g' | grep -v ^: | grep -v ^x86_64-linux: | sort -u  | xargs  | sed 's/ /,/g'
        # aarch64,aarch64-halium,aarch64-rpi,all,core2-32,core2-64,cortexa7t2hf-neon-vfpv4,cortexa8t2hf-neon-halium,hammerhead,i586,mako,mido,onyx,pinephone,qemux86,qemux86_64,raspberrypi2,raspberrypi3,raspberrypi3_64,raspberrypi4,raspberrypi4_64,rosy,tenderloin,tissot,x86_64
        ARCHS="aarch64,aarch64-halium,aarch64-rpi,all,core2-32,core2-64,cortexa7t2hf-neon-vfpv4,cortexa8t2hf-neon-halium,hammerhead,i586,mako,mido,onyx,pinephone,qemux86,qemux86_64,raspberrypi2,raspberrypi3,raspberrypi3_64,raspberrypi4,raspberrypi4_64,rosy,tenderloin,tissot,x86_64"
        DU1=`du -hs sstate-cache/`
        echo "$DU1"
        OPENSSL="find sstate-cache/ -name '*:openssl:*populate_sysroot*tgz'"
        ARCHIVES1=`sh -c "${OPENSSL}"`; echo "number of openssl archives: `echo "$ARCHIVES1" | wc -l`"; echo "$ARCHIVES1"
        openembedded-core/scripts/sstate-cache-management.sh -L --cache-dir=sstate-cache -y -d --extra-archs=${ARCHS// /,} || true
        DU2=`du -hs sstate-cache/`
        echo "$DU2"
        ARCHIVES2=`sh -c "${OPENSSL}"`; echo "number of openssl archives: `echo "$ARCHIVES2" | wc -l`"; echo "$ARCHIVES2"

        echo "BEFORE:"
        echo "number of openssl archives: `echo "$ARCHIVES1" | wc -l`"; echo "$ARCHIVES1"
        echo "AFTER:"
        echo "number of openssl archives: `echo "$ARCHIVES2" | wc -l`"; echo "$ARCHIVES2"
        echo "BEFORE: $DU1, AFTER: $DU2"
    fi
    echo "Cleanup finished"
}

function run_compare-signatures {
    declare -i RESULT=0
    sanity-check
    cd ${BUILD_TOPDIR}
    . ./setup-env
    openembedded-core/scripts/sstate-diff-machines.sh --targets=world --tmpdir=tmp-glibc/ --analyze --machines="hammerhead mako qemux86" | tee log.compare-signatures
    RESULT+=${PIPESTATUS[0]}
    openembedded-core/scripts/sstate-diff-machines.sh --targets=world --tmpdir=tmp-glibc/ --analyze --machines="raspberrypi2 raspberrypi3 mako" | tee -a log.compare-signatures
    RESULT+=${PIPESTATUS[0]}
    openembedded-core/scripts/sstate-diff-machines.sh --targets=world --tmpdir=tmp-glibc/ --analyze --machines="tissot mido raspberrypi3-64" | tee -a log.compare-signatures
    RESULT+=${PIPESTATUS[0]}
    if [ ! -d sstate-diff-${BUILD_NUMBER} ]; then mkdir sstate-diff-${BUILD_NUMBER}; fi
    mv tmp-glibc/sstate-diff/* sstate-diff-${BUILD_NUMBER}
    mv log.compare-signatures sstate-diff-${BUILD_NUMBER}
    tar cjf sstate-diff-${BUILD_NUMBER}.tar.bz2 sstate-diff-${BUILD_NUMBER}
    # it's a lot of small files, get rid of it
    rm -rf sstate-diff-${BUILD_NUMBER}

    rsync -avir sstate-diff-${BUILD_NUMBER}.tar.bz2 ${FILESERVER_BUILDS}/luneos-${BUILD_VERSION}/
    RESULT+=$?

    exit ${RESULT}
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

    cat >> ${BUILD_TOPDIR}/conf/local.conf << EOF

# Additions from jenkins-job.sh

# keep the number of bitbake threads low, the default
# meta/conf/bitbake.conf:BB_NUMBER_THREADS ?= "\${@oe.utils.cpu_count()}"
# is way too much for our VM
BB_NUMBER_THREADS = "4"

# we're using tmpfs we need to save as much space in WORKDIRs as possible
INHERIT += "rm_work"

DISTRO_FEED_PREFIX = "luneos-${BUILD_VERSION}"
DISTRO_FEED_URI = "http://build.webos-ports.org/luneos-${BUILD_VERSION}/ipk/"

BB_GENERATE_MIRROR_TARBALLS = "1"

CONNECTIVITY_CHECK_URIS = ""

BUILDHISTORY_COMMIT ?= "1"
BUILDHISTORY_COMMIT_AUTHOR ?= "Martin Jansa <Martin.Jansa@gmail.com>"
BUILDHISTORY_PUSH_REPO ?= "origin luneos-${BUILD_VERSION}"

IMAGE_FSTYPES_forcevariable = "tar.gz"
IMAGE_FSTYPES_forcevariable_qemux86 = "tar.gz wic.vmdk"
IMAGE_FSTYPES_forcevariable_qemux86-64 = "tar.gz wic.vmdk"
IMAGE_FSTYPES_forcevariable_raspberrypi2 = "rpi-sdimg.gz"
IMAGE_FSTYPES_forcevariable_raspberrypi3 = "rpi-sdimg.gz"
IMAGE_FSTYPES_forcevariable_raspberrypi3-64 = "rpi-sdimg.gz"
IMAGE_FSTYPES_forcevariable_raspberrypi4 = "rpi-sdimg.gz"
IMAGE_FSTYPES_forcevariable_raspberrypi4-64 = "rpi-sdimg.gz"
IMAGE_FSTYPES_forcevariable_pinephone = "wic.gz wic.bmap"
EOF

    if [ ! -d ${BUILD_TOPDIR}/buildhistory/ ] ; then
        git clone git@github.com:webOS-ports/buildhistory.git --branch luneos-${BUILD_VERSION} --single-branch --depth 1 ${BUILD_TOPDIR}/buildhistory
    fi
}

function run_rsync {
    delete_unnecessary_images
    RESULT+=$?

    if [ -d ${BUILD_TOPDIR}/tmp-glibc/deploy ] ; then
        if [ "${BUILD_VERSION}" = "stable" ] ; then
            scripts/staging_sync.sh ${BUILD_TOPDIR}/tmp-glibc/deploy      ${FILESERVER_BUILDS}/luneos-${BUILD_VERSION}-staging/wip
            RESULT+=$?
        else
            scripts/staging_sync.sh ${BUILD_TOPDIR}/tmp-glibc/deploy      ${FILESERVER_BUILDS}/luneos-${BUILD_VERSION}/
            RESULT+=$?
        fi
    else
        echo "Nothing in ${BUILD_TOPDIR}/tmp-glibc/deploy to rsync"
    fi

    rsync -avir --no-links --exclude '*.done' --exclude '*_bad-checksum_*' --exclude git2 \
                           --exclude svn --exclude bzr downloads/      #{FILESERVER_SOURCES}/
    RESULT+=$?
    exit ${RESULT}
}

function run_halium-rsync {
    [[ -d ${BUILD_WORKSPACE}/../halium-luneos-5.1-build/halium-luneos-5.1/results/ ]] && rsync -avir ${BUILD_WORKSPACE}/../halium-luneos-5.1-build/halium-luneos-5.1/results/ ${FILESERVER_BUILDS}/halium-luneos-5.1/
    [[ -d ${BUILD_WORKSPACE}/../halium-luneos-7.1-build/halium-luneos-7.1/results/ ]] && rsync -avir ${BUILD_WORKSPACE}/../halium-luneos-7.1-build/halium-luneos-7.1/results/ ${FILESERVER_BUILDS}/halium-luneos-7.1/
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
            image_path=`find ${FILESERVER_BUILDS}/luneos-testing/images/$machine -type f \
                -name 'luneos-dev-emulator*.tar.gz' -o \
                -name 'luneos-dev-package*.zip' -o \
                -name 'luneos-dev-image*.zip' -o \
                -name 'luneos-dev-image*.rpi-sdimg.gz' -o \
                -name 'luneos-dev-image*.wic.gz' -o \
                -name 'luneos-dev-image*.rootfs.tar.gz' |\
                sort -r | head -n 1`
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
        scp manifest.json ${FILESERVER_BUILDS}/luneos-${BUILD_VERSION}/
        scp device-images.json ${FILESERVER_BUILDS}/luneos-${BUILD_VERSION}/
        rm -vf manifest.json device-images.json
    fi
}

function run_new-staging {
    . scripts/staging_header.sh
    echo "ERROR: needs to be updated for new fileserver"
    exit 1

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

    bash -x scripts/staging_new.sh ${FILESERVER}
}

function run_sync-to-public {
    if [ -z "$FEED_NUMBERS" ]; then
        echo "ERROR: FEED_NUMBERS wasn't set"
        exit 1
    fi
    echo "ERROR: needs to be updated for new fileserver"
    exit 1

    for FEED in $FEED_NUMBERS; do
        bash -x scripts/staging_sync_to_public_feed.sh ${FILESERVER} $FEED
    done
}

function run_release {
    if [ -z "${FEED_NUMBER}" -o -z "${RELEASE_NAME}" ]; then
        echo "ERROR: FEED_NUMBER, RELEASE_NAME cannot be empty"
        exit 1
    fi
    echo "ERROR: needs to be updated for new fileserver"
    exit 1
    ssh ${FILESERVER} "mkdir ~/htdocs/builds/releases/${RELEASE_NAME}"
    ssh ${FILESERVER} "cp -rav ~/htdocs/builds/luneos-stable-staging/${FEED_NUMBER}/* ~/htdocs/builds/releases/${RELEASE_NAME}"
    ssh ${FILESERVER} "rm -rf ~/htdocs/builds/releases/${RELEASE_NAME}/ipk"
    if [ -n "${UNSUPPORTED_MACHINES}" ] ; then
        ssh ${FILESERVER} "for UNSUPPORTED_MACHINE in ${UNSUPPORTED_MACHINES}; do rm -rf ~/htdocs/builds/releases/${RELEASE_NAME}/images/\${UNSUPPORTED_MACHINE}; done"
    fi
}

function run_halium {
    BUILD_DIR=${BUILD_WORKSPACE}/halium-luneos-${BUILD_VERSION}
    RESULT_DIR=${BUILD_DIR}/results
    CPU_CORES=6
    HALIUM_BUILD_VERSION="`date +%Y%m%d`-${BUILD_NUMBER}"
    BASE_ARCHIVE_NAME="halium-luneos-${BUILD_VERSION}-`date +%Y%m%d`-${BUILD_NUMBER}"

    [[ -d ${BUILD_DIR} ]] || mkdir ${BUILD_DIR}
    cd ${BUILD_DIR}

    rm -rf .repo/local_manifests/
    mkdir -p .repo/local_manifests/

    repo status

    # reset all git repositories, not only those included in the manifest (where repo forall works fine)
    for G in `find . -name .git`; do cd `dirname $G`; echo -n "$G: "; git reset --hard; cd - >/dev/null; done

    if [[ "${BUILD_VERSION}" = "5.1" ]] ; then
        repo init --depth=1 -u https://github.com/Halium/android.git -b halium-5.1
    else
        repo init --depth=1 -u https://github.com/webos-ports/android.git -b luneos-halium-7.1
        (cd .repo/manifests ; git pull )
    fi

    repo sync -j16 --force-sync -d -c

    rm -rf ${RESULT_DIR}
    mkdir -p ${RESULT_DIR}

    rm -rf ${BUILD_DIR}/out

    if [[ "${BUILD_VERSION}" = "5.1" ]] ; then
        halium_build_device tenderloin cm_tenderloin-userdebug
        halium_build_device mako aosp_mako-userdebug
        halium_build_device hammerhead aosp_hammerhead-userdebug
    else
        halium_build_device onyx lineage_onyx-userdebug
        halium_build_device mido lineage_mido-userdebug
        halium_build_device rosy lineage_rosy-userdebug
        halium_build_device tissot lineage_tissot-userdebug
    fi
}

halium_publish_archive() {
    archive=$1
    echo "Publishing archive '$archive' ..."
    mv $archive ${RESULT_DIR}
}

halium_generate_checksums() {
    file=$1
    echo "Generating checksums for archive '$file' ..."
    md5sum $file > $file.md5sum
    sha256sum $file > $file.sha256sum
}

halium_build_device() {
    MACHINE=$1
    BUILD_TARGET=$2
    BUILD_CMD=lunch
    [[ "${BUILD_VERSION}" = "7.1" ]] && BUILD_CMD=breakfast
    OUTPUT_DIR=${BUILD_DIR}/out/target/product/${MACHINE}
    ARCHIVE_NAME="${BASE_ARCHIVE_NAME}-${MACHINE}.tar.bz2"
    DEBUG_ARCHIVE_NAME="${BASE_ARCHIVE_NAME}-${MACHINE}-dbg.tar.bz2"
    KERNEL_PARTS_ARCHIVE_NAME="${BASE_ARCHIVE_NAME}-kernel-parts-${MACHINE}.tar.bz2"

    echo "==============================================================="
    echo "Machine: ${MACHINE}"
    echo "Build version: ${HALIUM_BUILD_VERSION}"
    echo "Build dir: ${BUILD_DIR}"
    echo "Result dir: ${RESULT_DIR}"
    echo "Output dir: ${OUTPUT_DIR}"
    echo "Archive name: ${ARCHIVE_NAME}"
    echo "==============================================================="

    git config --global user.name "Jenkins"
    git config --global user.email "jenkins@nas-admin.org"

    [[ "${BUILD_VERSION}" = "5.1" ]] || mkdir -p ${BUILD_DIR}/out/host/linux-x86/framework/

    cd ${BUILD_DIR}

    # cleanup previous changes made by halium's device setup
    repo forall -vc "git reset --hard"
    # retrieve device's manifest
    ./halium/devices/setup $MACHINE --force-sync

    source build/envsetup.sh

    #For Ubuntu 18.04 we will need to use either of below:
    [[ "${BUILD_VERSION}" = "5.1" ]] || export LC_ALL=C
    [[ "${BUILD_VERSION}" = "5.1" ]] && export USE_HOST_LEX=yes

    export USE_CCACHE=1
    #make clobber

    ${BUILD_CMD} ${BUILD_TARGET}
    mka systemimage
    if [ $? != 0 ]; then
        echo "Build of Halium ${BUILD_VERSION} for $MACHINE failed"
        exit 1
    fi

    # Package result
    cd ${OUTPUT_DIR}
        #touch filesystem_config.txt
        #cp ramdisk-android.img android-ramdisk.img
        #tar cvjf ${ARCHIVE_NAME} system android-ramdisk.img filesystem_config.txt system.img
        tar cvjf ${ARCHIVE_NAME} system.img
        tar cvjf ${DEBUG_ARCHIVE_NAME} symbols/
    cd ${BUILD_DIR}

    halium_publish_archive ${OUTPUT_DIR}/${ARCHIVE_NAME}
    halium_publish_archive ${OUTPUT_DIR}/${DEBUG_ARCHIVE_NAME}
    halium_generate_checksums ${RESULT_DIR}/${ARCHIVE_NAME}

    # package kernel image and modules
    mkdir -p ${OUTPUT_DIR}/kernel-parts-${HALIUM_BUILD_VERSION}/modules
    cp ${OUTPUT_DIR}/system/lib/modules/* ${OUTPUT_DIR}/kernel-parts-${HALIUM_BUILD_VERSION}/modules/
    cp ${OUTPUT_DIR}/obj/KERNEL_OBJ/arch/arm/boot/uImage ${OUTPUT_DIR}/kernel-parts-${HALIUM_BUILD_VERSION}/
    [[ "${BUILD_VERSION}" = "5.1" ]] || cp ${OUTPUT_DIR}/obj/KERNEL_OBJ/arch/arm64/boot/Image ${OUTPUT_DIR}/kernel-parts-${HALIUM_BUILD_VERSION}/
    (cd ${OUTPUT_DIR} ; tar cjf ${OUTPUT_DIR}/${KERNEL_PARTS_ARCHIVE_NAME} kernel-parts-${HALIUM_BUILD_VERSION} )
    halium_publish_archive ${OUTPUT_DIR}/${KERNEL_PARTS_ARCHIVE_NAME}
    halium_generate_checksums ${RESULT_DIR}/${KERNEL_PARTS_ARCHIVE_NAME}

    # cleanup previous changes made by halium's device setup
    # again before switching to another device in the next job
    # which will fail to repo sync, because there will be left-over
    # local changes from previous jenkins job
    repo forall -vc "git reset --hard"
}

function delete_unnecessary_images {
    MACHINES=`ls ${BUILD_TOPDIR}/tmp-glibc/deploy/images/`
    if [ -z "${MACHINES}" ] ; then
        echo "No MACHINEs with built images in ${BUILD_TOPDIR}/tmp-glibc/deploy/images/"
        return
    fi

    for M in ${MACHINES}; do
        rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/README_-_DO_NOT_DELETE_FILES_IN_THIS_DIRECTORY.txt
        case ${M} in
            grouper|maguro|mako|hammerhead|mido|onyx|rosy|tissot)
                # keep only *-package.zip
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/zImage*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/Image.gz*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/modules-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/initramfs*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/busybox-static
                ;;
            qemuarm|tenderloin|a500)
                # keep uImage and rootfs.tar.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/initramfs*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/modules-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*testdata.json
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*.manifest
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-${M}.tar.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/uImage-${M}.bin
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/uImage
                ;;
            qemux86|qemux86-64)
                # keep only image.zip
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image.env
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image.env
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/bzImage*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/modules-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/grub-efi-bootx64.efi
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/grub-efi-bootia32.efi
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/systemd-bootx64.efi
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/systemd-bootia32.efi
                ;;
            raspberrypi2|raspberrypi3|raspberrypi3-64|raspberrypi4|raspberrypi4-64)
                # keep only luneos-dev-image-raspberrypiX.rpi-sdimg
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image-*.tar.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image-*.ext3
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-*.tar.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-*.ext3
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-${M}.rpi-sdimg.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*.manifest
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/modules-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/zImage*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/Image*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/bcm2835-bootfiles
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*testdata.json
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*.dtbo
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*.dtb
                ;;
            pinephone)
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image.env
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image.env
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image-${M}.wic.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-${M}.wic.gz
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-image-${M}.wic.bmap
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/luneos-dev-image-${M}.wic.bmap
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/Image*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*.manifest
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/modules-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/initramfs-uboot-image-*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/bl31*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/boot*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/u-boot*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/sunxi*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/sun50i*
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*testdata.json
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/*.dtb
                rm -rfv ${BUILD_TOPDIR}/tmp-glibc/deploy/images/${M}/scp-${M}.*
                ;;
            *)
                echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine: '${M}', script doesn't know which images to delete"
                exit 1
                ;;
         esac
 done
}
function delete_unnecessary_images_webosose {
    rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/README_-_DO_NOT_DELETE_FILES_IN_THIS_DIRECTORY.txt
    case ${BUILD_MACHINE} in
        qemux86|qemux86-64)
            # unfortunately vmdk.zip in IMAGE_FSTYPES doesn't work with the old Yocto used by webOS OSE
            for i in BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.vmdk; do zip -j $i.zip $i; done
            for i in BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.vmdk; do zip -j $i.zip $i; done
            # keep only wic.vmdk.zip
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.rootfs.*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.hdddirect
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.qemuboot.conf
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.vmdk
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ext3
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ext4
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.manifest
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.tar.gz
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.qemuboot.conf
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.hdddirect
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.vmdk

            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}.rootfs.*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}.hdddirect
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}.qemuboot.conf
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}.vmdk
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.ext3
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.ext4
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.manifest
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.tar.gz
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.qemuboot.conf
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.hdddirect
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.vmdk
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/bzImage*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/modules-*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/*.testdata.json
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/*.efi
            ;;
        raspberrypi3|raspberrypi4)
            # unfortunately rpi-sdimg.zip in IMAGE_FSTYPES doesn't work, because how the webOS OSE handles the hardlinks in deploy, this will stay a symlink to the file which we remove later
            for i in BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.wic; do zip -j $i.zip $i; done
            for i in BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.wic; do zip -j $i.zip $i; done
            # keep only wic.zip
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/boot.scr
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/initramfs*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/ostree_repo
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/u-boot*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/uImage*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/Image*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/zImage*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/modules-*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/bcm2835-bootfiles
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.vfat
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}.rootfs.*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ext3
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ext4
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.manifest
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.tar.gz
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.tar.bz2
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.rpi-sdimg
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.wic
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-${BUILD_MACHINE}-*.ota-ext4
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}.vfat
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}.rootfs.*
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.ext4
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.manifest
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.tar.gz
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.tar.bz2
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.rpi-sdimg
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.wic
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/webos-image-devel-${BUILD_MACHINE}-*.ota-ext4
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/*.testdata.json
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/*.dtb
            rm -rfv BUILD/deploy/images/${BUILD_MACHINE}/*.dtbo
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine: '${BUILD_MACHINE}', script doesn't know which images to build"
            exit 1
            ;;
    esac
}

function sanity_check_workspace {
    if [ "${BUILD_TYPE}" = "halium" -o "${BUILD_TYPE}" = "halium-rsync" ] ; then
        # known to be insane
        mkdir -p ${BUILD_TOPDIR} # just for BUILD_TIME_LOG
    elif [ "${BUILD_VERSION}" = "webosose" ] ; then
        # don't use webos-ports as a ${BUILD_DIR}
        BUILD_TOPDIR="${BUILD_WORKSPACE}"
        BUILD_TIME_LOG=${BUILD_TOPDIR}/time.txt
        return
        # BUILD_TOPDIR path should contain BUILD_VERSION, otherwise there is probably incorrect WORKSPACE in jenkins config
        if ! echo ${BUILD_TOPDIR} | grep -q "/${BUILD_VERSION}/" ; then
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} BUILD_TOPDIR: '${BUILD_TOPDIR}' path should contain ${BUILD_VERSION} directory, is workspace set correctly in jenkins config?"
            exit 1
        fi
    else
        # BUILD_TOPDIR path should contain BUILD_VERSION, otherwise there is probably incorrect WORKSPACE in jenkins config
        if ! echo ${BUILD_TOPDIR} | grep -q "/luneos-${BUILD_VERSION}/" ; then
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} BUILD_TOPDIR: '${BUILD_TOPDIR}' path should contain luneos-${BUILD_VERSION} directory, is workspace set correctly in jenkins config?"
            exit 1
        fi
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
    ./mcf --enable-generate-mirror-tarballs ${BUILD_MACHINE}
    ./mcf --command update --clean

    cat > webos-local.conf << EOF
INHERIT += "rm_work"
IMAGE_FSTYPES_raspberrypi3_pn-webos-image = "ota-ext4 wic"
IMAGE_FSTYPES_raspberrypi3_pn-webos-image-devel = "ota-ext4 wic"
IMAGE_FSTYPES_raspberrypi4_pn-webos-image = "ota-ext4 wic"
IMAGE_FSTYPES_raspberrypi4_pn-webos-image-devel = "ota-ext4 wic"
IMAGE_FSTYPES_qemux86_pn-webos-image = "wic.vmdk"
IMAGE_FSTYPES_qemux86_pn-webos-image-devel = "wic.vmdk"
EOF


    . ./oe-init-build-env
    export MACHINE="${BUILD_MACHINE}"

    /usr/bin/time -f "${BUILD_TIME_STR}" \
        bitbake -k ${BUILD_IMAGES} 2>&1 | tee /dev/stderr | grep '^TIME:' >> ${BUILD_TIME_LOG}
    RESULT+=${PIPESTATUS[0]}

    delete_unnecessary_images_webosose

    rsync -avir ${BUILD_TOPDIR}/BUILD/deploy/images/${BUILD_MACHINE}/               ${FILESERVER_BUILDS}/webosose/${BUILD_MACHINE}/
    RESULT+=$?
    rsync -avir --no-links --exclude '*.done' --exclude '*_bad-checksum_*' --exclude git2 \
                --exclude svn --exclude bzr ${BUILD_TOPDIR}/downloads/              ${FILESERVER_BUILDS}/webosose/sources/
    RESULT+=$?

    sleep 10 # wait a bit for pseudo processes to finish before trying to umount it
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
    sstate-cleanup)
        run_sstate-cleanup
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
    halium)
        run_halium
        ;;
    halium-rsync)
        run_halium-rsync
        ;;
    *)
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized build type: '${BUILD_TYPE}', script doesn't know how to execute such job"
        exit 1
        ;;
esac
