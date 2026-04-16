#!/bin/bash
set -e
# Source based on what ROS2 is installed
if [[ -d /opt/ros/jazzy ]]; then
    source /opt/ros/jazzy/setup.bash
fi
if [[ -d /opt/ros/humble ]]; then
    source /opt/ros/humble/setup.bash
fi
source /workspace/ros_packages/install/local_setup.bash
export FASTRTPS_DEFAULT_PROFILES_FILE=/workspace/fastRTPS_fix.xml
export OMNI_KIT_ALLOW_ROOT=1
export LANG=en_US.UTF-8
exec "$@"
