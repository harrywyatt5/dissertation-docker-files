#!/bin/bash
set -e
source /opt/ros/humble/setup.bash
export OMNI_KIT_ALLOW_ROOT=1
exec "$@"
