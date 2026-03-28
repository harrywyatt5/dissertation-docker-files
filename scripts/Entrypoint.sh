#!/bin/bash
set -e
source /opt/ros/jazzy/setup.bash
# If needed, source nitros packages
if [[ -d /opt/isaac_ros ]]; then
    source /opt/isaac_ros/install/local_setup.bash
fi
export OMNI_KIT_ALLOW_ROOT=1
export LANG=en_US.UTF-8
exec "$@"
