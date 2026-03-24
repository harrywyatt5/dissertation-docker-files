FROM nvcr.io/nvidia/tensorrt:26.02-py3-igpu

# Required for supporting DISPLAY passthrough
ARG TARGET_CUDA_ARCH
ARG TARGETARCH
ARG NUM_COMPILE_THREADS=1
ARG NUM_CUDA_COMPILE_THREADS=1
ENV DISPLAY=:0
COPY --chmod=700 scripts/Entrypoint.sh /Entrypoint.sh

RUN apt update && apt upgrade -y && apt install -y build-essential python3-requests ca-certificates  \ 
                    curl software-properties-common git \
                    git-lfs gcc-11 g++-11 \
                    pkg-config libgtk-3-dev libavcodec-dev \
                    libavformat-dev libswscale-dev python3-pip \
                    libopencv-dev locales
RUN git lfs install
# Required for ROS
RUN locale-gen en_US en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
# Load latest cmake and psutil for building onnxruntime
RUN pip3 install --upgrade cmake && pip3 install psutil

# onnxruntime
# Set arch info
WORKDIR /workspace
RUN case "${TARGETARCH}" in \
        "amd64") GNU_FOLDER="x86_64-linux-gnu" ;; \
        "arm64") GNU_FOLDER="aarch64-linux-gnu" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && mkdir /opt/onnx-built \ 
    && git clone --recursive https://github.com/Microsoft/onnxruntime.git \
    && cd onnxruntime \
    && ./build.sh --allow_running_as_root --config Release --build_shared_lib --parallel ${NUM_COMPILE_THREADS} --nvcc_threads ${NUM_CUDA_COMPILE_THREADS} \
        --compile_no_warning_as_error --skip_submodule_sync \
        --cmake_extra_defines "CMAKE_CUDA_ARCHITECTURES=$(echo ${TARGET_CUDA_ARCH} | sed 's/\.//g')" --cmake_extra_defines CMAKE_INSTALL_PREFIX=/opt/onnx-built \
        --cudnn_home "/usr/include/${GNU_FOLDER}" --cuda_home /usr/local/cuda --use_cuda --use_tensorrt --tensorrt_home /opt/tensorrt --skip_tests \
    && cd build/Linux/Release \
    && make install \
    && cd /workspace \
    && rm -rf onnxruntime \
    # We have to move the headers up a layer to be consistent with the prebuilt versions
    && cd /opt/onnx-built/include/onnxruntime \
    && mv * .. \
    && cd .. \
    && rm -rf onnxruntime

# ROS2
RUN export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && apt update \
    && apt install -y ros-dev-tools ros-jazzy-ros-base ros-jazzy-rviz2 \
    && rm /tmp/ros2-apt-source.deb

# Install OpenCV with CUDA support
WORKDIR /workspace
RUN mkdir /opt/cudaopencv \
    && git clone https://github.com/opencv/opencv.git opencv \
    && git clone https://github.com/opencv/opencv_contrib.git opencv_contrib \
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
RUN mkdir -p /tmp/eigen \
    && cd /tmp/eigen \
    && wget https://gitlab.com/libeigen/eigen/-/archive/3.3.9/eigen-3.3.9.zip \
    && unzip eigen-${EIGEN_VERSION}.zip -d . \
    && mkdir /tmp/eigen/eigen-${EIGEN_VERSION}/build && cd /tmp/eigen/eigen-${EIGEN_VERSION}/build/ \
    && cmake .. \
    && make install \
    && cd /tmp \
    && rm -rf eigen

# Install bytetrack-cpp
WORKDIR /opt
RUN git clone https://github.com/harrywyatt5/ByteTrack-cpp.git --depth=1 ByteTrack-cpp \
    && cd ByteTrack-cpp \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make -j$(nproc)

ENTRYPOINT ["/Entrypoint.sh"]
CMD ["/bin/bash"]
