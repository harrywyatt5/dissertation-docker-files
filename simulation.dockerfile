FROM nvcr.io/nvidia/tensorrt:23.12-py3

# Required for supporting DISPLAY passthrough
ARG TARGET_CUDA_ARCH
ENV DISPLAY=:0
COPY --chmod=777 scripts/Entrypoint.sh /Entrypoint.sh

RUN apt update && apt upgrade -y && apt install -y build-essential python3-requests ca-certificates  \ 
                    curl software-properties-common git \
                    git-lfs gcc-11 g++-11 \
                    pkg-config libgtk-3-dev libavcodec-dev \
                    libavformat-dev libswscale-dev cmake
COPY scripts/InstallOnnxRuntime.py /tmp/InstallOnnxRuntime.py
RUN python3 /tmp/InstallOnnxRuntime.py --owner microsoft --repo onnxruntime --dir /opt --tag latest --regex "^onnxruntime-linux-x64-gpu-.+\\.tgz$"
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

# Install OpenCV with CUDA support
WORKDIR /workspace
RUN git clone https://github.com/opencv/opencv.git opencv
RUN git clone https://github.com/opencv/opencv_contrib.git opencv_contrib
RUN mkdir opencv/build
WORKDIR /workspace/opencv/build
RUN cmake -D CMAKE_BUILD_TYPE=RELEASE \
            -D CMAKE_INSTALL_PREFIX=/usr/local \
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
            -D BUILD_EXAMPLES=OFF ..
RUN make -j$(nproc)
RUN make install
RUN ldconfig
WORKDIR /workspace
RUN rm -rf opencv
RUN rm -rf opencv_contrib

ENTRYPOINT ["/Entrypoint.sh"]
CMD ["/bin/bash"]
