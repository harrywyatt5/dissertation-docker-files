FROM nvcr.io/nvidia/tensorrt:26.01-py3

COPY scripts/Entrypoint.sh /Entrypoint.sh

RUN apt update && apt upgrade -y && apt install -y libopencv-dev \ 
                    build-essential python3-requests ca-certificates curl software-properties-common \
                    git git-lfs gcc-11 g++-11
COPY scripts/InstallOnnxRuntime.py /tmp/InstallOnnxRuntime.py
RUN python3 /tmp/InstallOnnxRuntime.py --owner microsoft --repo onnxruntime --dir /opt --tag latest --regex "^onnxruntime-linux-x64-gpu_cuda13.+\\.tgz$"
RUN rm /tmp/InstallOnnxRuntime.py

RUN export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb
RUN apt update && apt install -y ros-humble-desktop ros-dev-tools
RUN rm /tmp/ros2-apt-source.deb

RUN git lfs install
# NVIDIA Isaac Sim doesn't support newer version of g++
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 200 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 200
RUN git clone https://github.com/isaac-sim/IsaacSim.git /isaacsim
WORKDIR /isaacsim
RUN git lfs pull
# Force NVIDIA to think we've accepted the EULA, as we can't do that manually here...
RUN touch .eula_accepted
RUN bash build.sh
RUN ln -s /isaacsim/_build/linux-x86_64/release /opt/isaacsim

WORKDIR /workspace
ENTRYPOINT ["/Entrypoint.sh"]
CMD ["/bin/bash"]
