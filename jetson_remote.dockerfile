FROM nvcr.io/nvidia/isaac/ros:aarch64-ros2_humble_4c0c55dddd2bbcc3e8d5f9753bee634c

# Required for supporting DISPLAY passthrough
ARG TARGET_CUDA_ARCH
ARG NUM_COMPILE_THREADS=1
ARG NUM_CUDA_COMPILE_THREADS=1
ENV DISPLAY=:0
ENV LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/nvidia:$LD_LIBRARY_PATH 
COPY --chmod=700 scripts/Entrypoint.sh /Entrypoint.sh

# The difference with the remote package is we deploy some stub shared objects so
# it can build on a platform which is not Jetson
ADD nvidia_libs.tar.gz /

# Clean up base image :))
RUN rm -rf /ffmpeg-4.4.2.tar.bz2 \
    /usr/local/lib/cmake/protobuf \
    /usr/local/lib/cmake/absl \
    /usr/local/include/google/protobuf \
    /usr/local/lib/libprotobuf* \
    /usr/local/lib/libabsl*

RUN add-apt-repository ppa:ubuntu-toolchain-r/test -y \
    && apt update \
    && apt install -y build-essential python3-requests ca-certificates  \ 
            curl software-properties-common git \
            git-lfs gcc-11 g++-11 \
            pkg-config libgtk-3-dev libavcodec-dev \
            libavformat-dev libswscale-dev python3-pip \
            libopencv-dev locales gdb \
            libssl-dev wget libgtest-dev \
            libgmock-dev libboost-dev libcudnn9-dev-cuda-12 \
            libcudnn9-cuda-12 libcudnn9-headers-cuda-12 gcc-13 \
            g++-13 \
    && apt clean \
    && git lfs install \
    && locale-gen en_US en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 13 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 13 \
    && update-alternatives --set gcc /usr/bin/gcc-13 \
    && update-alternatives --set g++ /usr/bin/g++-13 \
    && pip3 install --upgrade --break-system-package "cmake<4.0" && pip3 install --break-system-package psutil

# onnxruntime
WORKDIR /workspace
RUN mkdir /opt/onnx-built \ 
    && git clone --recursive --branch v1.24.4 --depth=1 https://github.com/Microsoft/onnxruntime.git \
    && cd onnxruntime \
    && ./build.sh --allow_running_as_root --config Release --build_shared_lib --parallel ${NUM_COMPILE_THREADS} --nvcc_threads ${NUM_CUDA_COMPILE_THREADS} \
        --compile_no_warning_as_error --skip_submodule_sync \
        --cmake_extra_defines "CMAKE_CUDA_ARCHITECTURES=$(echo ${TARGET_CUDA_ARCH} | sed 's/\.//g')" --cmake_extra_defines CMAKE_INSTALL_PREFIX=/opt/onnx-built \
        --cudnn_home /usr --cuda_home /usr/local/cuda --use_cuda --use_tensorrt --tensorrt_home /usr --skip_tests --cmake_extra_defines CMAKE_CXX_STANDARD=20 \
        --cmake_extra_defines onnxruntime_USE_PREINSTALLED_PROTOBUF=OFF --cmake_extra_defines CMAKE_PREFIX_PATH="" \
    && cd build/Linux/Release \
    && make install \
    && cd /workspace \
    && rm -rf onnxruntime \
    # We have to move the headers up a layer to be consistent with the prebuilt versions
    && cd /opt/onnx-built/include/onnxruntime \
    && mv * .. \
    && cd .. \
    && rm -rf onnxruntime

# Isaac Ros extras 
# We have to refresh the ROS key uff
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key  | gpg --dearmor | tee /usr/share/keyrings/ros-archive-keyring.gpg >/dev/null \
    && apt update \
    && apt install -y \
        ros-humble-isaac-ros-nitros \
        ros-humble-isaac-ros-nitros-image-type \
        ros-humble-isaac-ros-nitros-camera-info-type \
        ros-humble-isaac-ros-common \
        ros-humble-isaac-ros-managed-nitros

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
            -D WITH_MPI=OFF \
            -D BUILD_opencv_sfm=OFF \ 
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
RUN mkdir -p /tmp/eigen \
    && cd /tmp/eigen \
    && wget https://gitlab.com/libeigen/eigen/-/archive/3.3.9/eigen-3.3.9.zip \
    && unzip eigen-3.3.9.zip -d . \
    && mkdir /tmp/eigen/eigen-3.3.9/build && cd /tmp/eigen/eigen-3.3.9/build/ \
    && cmake .. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
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

WORKDIR /workspace
ENTRYPOINT ["/Entrypoint.sh"]
CMD ["/bin/bash"]
