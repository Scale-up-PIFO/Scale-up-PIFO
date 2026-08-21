#!/bin/bash
P4_NAME="scaleup"
SRC_NAME="scaleup"

P4FILE_PATH="$(pwd)/src/${SRC_NAME}.p4"
BUILD_DIR="build"

if [ -d "$BUILD_DIR" ]; then
  echo "Directory $BUILD_DIR exists. Deleting..."
  sudo rm -rf "$BUILD_DIR"
else
  echo "Directory $BUILD_DIR does not exist."
fi

mkdir "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$SDE/p4studio/" -DCMAKE_INSTALL_PREFIX="$SDE/install" -DCMAKE_MODULE_PATH="$SDE/cmake" -DP4_NAME="$P4_NAME" -DP4_PATH="$P4FILE_PATH"
make $P4_NAME
make install
