FROM nvcr.io/nvidia/tensorrt:26.02-py3

# Required for supporting DISPLAY passthrough
ARG TARGET_CUDA_ARCH
ENV DISPLAY=:0
ENV DEBIAN_FRONTEND noninteractive
COPY --chmod=700 scripts/Entrypoint.sh /Entrypoint.sh

RUN apt update && apt upgrade -y && apt install -y build-essential python3-requests ca-certificates  \ 
                    curl software-properties-common git \
                    git-lfs gcc-11 g++-11 \
                    pkg-config libgtk-3-dev libavcodec-dev \
                    libavformat-dev libswscale-dev cmake \
                    libopencv-dev locales gdb \
                    libssl-dev wget libgtest-dev \
                    libboost-dev && apt clean
RUN git lfs install
# NVIDIA Isaac Sim doesn't support newer version of g++
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 200 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 200
# Required for ROS
RUN locale-gen en_US en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
# Ensure everything that set in our Entrypoint.sh is also set in the .bashrc
RUN echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc \
    echo 'export OMNI_KIT_ALLOW_ROOT=1' >> ~/.bashrc \
    echo 'export LANG=en_US.UTF-8' >> ~/.bashrc

# onnxruntime
COPY scripts/InstallOnnxRuntime.py /tmp/InstallOnnxRuntime.py
RUN python3 /tmp/InstallOnnxRuntime.py --owner microsoft --repo onnxruntime --dir /opt --tag latest --regex "^onnxruntime-linux-x64-gpu_cuda13-.+\\.tgz$" \
    && rm /tmp/InstallOnnxRuntime.py

# ROS2
RUN export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && apt update \
    && apt install -y ros-dev-tools ros-jazzy-desktop \
    && rm /tmp/ros2-apt-source.deb

# Isaac Sim
RUN git clone https://github.com/isaac-sim/IsaacSim.git --depth=1 /tmp/isaacsim \
    && cd /tmp/isaacsim \
    && git lfs pull \
    && touch .eula_accepted \
    && bash build.sh \
    && mkdir /opt/isaacsim
    && mv /isaacsim/_build/linux-x86_64/release /opt/isaacsim
    && rm -rf /tmp/isaacsim

# Install reachy model
WORKDIR /opt/isaacsim
RUN mkdir additional_resources \
    cd additional_resources \
    git clone https://github.com/harrywyatt5/reachy2-isaac-sim-with-cameras.git --depth=1 reachy2

# Install OpenCV with CUDA support
WORKDIR /workspace
RUN mkdir /opt/cudaopencv \
    && git clone https://github.com/opencv/opencv.git --depth=1 opencv \
    && git clone https://github.com/opencv/opencv_contrib.git --depth=1 opencv_contrib \
    && mkdir opencv/build \
    && cd /workspace/opencv/build \
    && cmake -D CMAKE_BUILD_TYPE=RELEASE \
            -D CMAKE_INSTALL_PREFIX=/opt/cudaopencv \
            -D WITH_CUDA=ON \
            -D WITH_CUDNN=ON \
            -D WITH_CUBLAS=ON \
            -D CUDA_ARCH_BIN=${TARGET_CUDA_ARCH} \
            -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
            -D CUDA_CUDA_LIBRARY=/usr/local/cuda/lib64/stubs/libcuda.so \
            -D OPENCV_DNN_CUDA=ON \
            -D BUILD_opencv_python3=ON \
            -D HAVE_opencv_python3=ON \
            -D INSTALL_PYTHON_EXAMPLES=OFF \
            -D INSTALL_C_EXAMPLES=OFF \
            -D BUILD_EXAMPLES=OFF .. \
    && make -j$(nproc) \
    && make install \
    && cd /workspace \
    && rm -rf opencv \
    && rm -rf opencv_contrib

# Install Eigen
ENV EIGEN_VERSION="3.3.9"
RUN mkdir -p /tmp/eigen && cd /tmp/eigen && \
    wget https://gitlab.com/libeigen/eigen/-/archive/3.3.9/eigen-3.3.9.zip && \
    unzip eigen-${EIGEN_VERSION}.zip -d . && \
    mkdir /tmp/eigen/eigen-${EIGEN_VERSION}/build && cd /tmp/eigen/eigen-${EIGEN_VERSION}/build/ && \
    cmake .. && \
    make install && \
    cd /tmp && rm -rf eigen

# Install bytetrack-cpp
WORKDIR /opt
RUN git clone https://github.com/harrywyatt5/ByteTrack-cpp.git --depth=1 ByteTrack-cpp \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make -j$(nproc)

ENTRYPOINT ["/Entrypoint.sh"]
CMD ["/bin/bash"]
