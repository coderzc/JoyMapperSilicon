#!/bin/bash

# Set the number of git commits to Xcode build number
# The source code is based on https://leenarts.net/2020/02/11/git-based-build-number-in-xcode/

GIT=`sh /etc/profile; which git`

LATEST_TAG=`"${GIT}" describe --tags --abbrev=0 --match "v*.*.*" 2>/dev/null`
if [ "${LATEST_TAG}" == "" ]; then
  LATEST_TAG=`"${GIT}" describe --tags --abbrev=0 --match "v*" 2>/dev/null`
fi

if [ "${LATEST_TAG}" == "" ]; then
  VERSION="${MARKETING_VERSION:-1.0}"
  echo "warning: Version tag not found, fallback to ${VERSION}"
else
  VERSION=`echo "${LATEST_TAG}" | cut -c 2-`
fi

NUM_COMMITS=`"${GIT}" rev-list HEAD --count`

TARGET_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
DSYM_PLIST="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist"

for PLIST in "${TARGET_PLIST}" "${DSYM_PLIST}"; do
  if [ -f "${PLIST}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NUM_COMMITS}" "${PLIST}"
  fi
done

ROOT_PLIST="${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Settings.bundle/Root.plist"

if [ -f "${ROOT_PLIST}" ]; then
  SETTINGS_VERSION="${APP_MARKETING_VERSION} (${NUM_COMMITS})"
  /usr/libexec/PlistBuddy -c "Set :PreferenceSpecifiers:1:DefaultValue ${SETTINGS_VERSION}" "${ROOT_PLIST}"
else
  echo "Could not find: ${ROOT_PLIST}"
  exit 0
fi
