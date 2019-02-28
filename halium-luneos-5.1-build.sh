#!/bin/bash

BUILD_VERSION="5.1"
BUILD_DIR=~/halium-luneos-${BUILD_VERSION}
RESULT_DIR=${BUILD_DIR}/results
CPU_CORES=6
BUILD_VERSION="`date +%Y%m%d`-${BUILD_NUMBER}"
BASE_ARCHIVE_NAME="halium-luneos-${BUILD_VERSION}-`date +%Y%m%d`-${BUILD_NUMBER}"

publish_archive() {
  archive=$1
  echo "Publishing archive '$archive' ..."
  mv $archive ${RESULT_DIR}
}

generate_checksums() {
  file=$1
  echo "Generating checksums for archive '$file' ..."
  md5sum $file > $file.md5sum
  sha256sum $file > $file.sha256sum
}

build_device() {
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
  echo "Build version: ${BUILD_VERSION}"
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
    [[ "${BUILD_VERSION}" = "5.1" ]] && tar cvjf ${DEBUG_ARCHIVE_NAME} symbols/
  cd ${BUILD_DIR}

  publish_archive ${OUTPUT_DIR}/${ARCHIVE_NAME}
  [[ "${BUILD_VERSION}" = "5.1" ]] && publish_archive ${OUTPUT_DIR}/${DEBUG_ARCHIVE_NAME}
  generate_checksums ${RESULT_DIR}/${ARCHIVE_NAME}

  # package kernel image and modules
  mkdir -p ${OUTPUT_DIR}/kernel-parts-${BUILD_VERSION}/modules
  cp ${OUTPUT_DIR}/system/lib/modules/* ${OUTPUT_DIR}/kernel-parts-${BUILD_VERSION}/modules/
  cp ${OUTPUT_DIR}/obj/KERNEL_OBJ/arch/arm/boot/uImage ${OUTPUT_DIR}/kernel-parts-${BUILD_VERSION}/
  [[ "${BUILD_VERSION}" = "5.1" ]] || cp ${OUTPUT_DIR}/obj/KERNEL_OBJ/arch/arm64/boot/Image ${OUTPUT_DIR}/kernel-parts-${BUILD_VERSION}/
  (cd ${OUTPUT_DIR} ; tar cjf ${OUTPUT_DIR}/${KERNEL_PARTS_ARCHIVE_NAME} kernel-parts-${BUILD_VERSION} )
  publish_archive ${OUTPUT_DIR}/${KERNEL_PARTS_ARCHIVE_NAME}
  generate_checksums ${RESULT_DIR}/${KERNEL_PARTS_ARCHIVE_NAME}
  
  # cleanup previous changes made by halium's device setup
  # again before switching to another device in the next job
  # which will fail to repo sync, because there will be left-over
  # local changes from previous jenkins job
  repo forall -vc "git reset --hard"
}

[[ -d ${BUILD_DIR} ]] || mkdir ${BUILD_DIR}
cd ${BUILD_DIR}
rm -rf .repo/local_manifests/
repo status

if [[ "${BUILD_VERSION}" = "5.1" ]] ; then
  repo init --depth=1 -u https://github.com/Halium/android.git -b halium-5.1
else
  repo init --depth=1 -u https://github.com/webos-ports/android.git -b luneos-halium-7.1
  (cd .repo/manifests ; git pull )

  rm .repo/local_manifests/override_halium_device.xml
  ### tofee: optional step to override Halium/halium-devices, when waiting for a PR merge there
  ###        see https://gist.github.com/Tofee/409f24ec551932890435602561c49ae7
  curl https://gist.githubusercontent.com/Tofee/409f24ec551932890435602561c49ae7/raw/a49fe1d45d4c41b2d3c8269a764992e0af7c92ba/override_halium_device.xml -o .repo/local_manifests/override_halium_device.xml
fi

repo sync -j16 --force-sync -d -c

rm -rf ${RESULT_DIR}
mkdir -p ${RESULT_DIR}

rm -rf ${BUILD_DIR}/out

if [[ "${BUILD_VERSION}" = "5.1" ]] ; then
  build_device tenderloin cm_tenderloin-userdebug
  build_device mako aosp_mako-userdebug
  build_device hammerhead aosp_hammerhead-userdebug
else
  build_device onyx lineage_onyx-userdebug
  build_device mido lineage_mido-userdebug
  build_device rosy lineage_rosy-userdebug
  build_device athene lineage_athene-userdebug
  build_device tissot lineage_tissot-userdebug
fi
