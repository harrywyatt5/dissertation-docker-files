#!/bin/bash
set -e
source /opt/ros/jazzy/setup.bash
export OMNI_KIT_ALLOW_ROOT=1
export LANG=en_US.UTF-8
exec "$@"
