FROM nvcr.io/nvidia/isaac/ros:noble-ros2_jazzy_d3e84470d576702a380478a513fb3fc6-arm64

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

RUN apt update && apt upgrade -y && apt install -y build-essential python3-requests ca-certificates  \ 
                    curl software-properties-common git \
                    git-lfs gcc-11 g++-11 \
                    pkg-config libgtk-3-dev libavcodec-dev \
                    libavformat-dev libswscale-dev python3-pip \
                    libopencv-dev locales gdb \
                    libssl-dev wget libgtest-dev \
                    libgmock-dev libboost-dev \
                    && apt clean \
                    && git lfs install \
                    && locale-gen en_US en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
                    && pip3 install --upgrade cmake && pip3 install psutil

# onnxruntime
# Set arch info
WORKDIR /workspace
RUN mkdir /opt/onnx-built \ 
    && git clone --recursive --depth=1 https://github.com/Microsoft/onnxruntime.git \
    && cd onnxruntime \
    && ./build.sh --allow_running_as_root --config Release --build_shared_lib --parallel ${NUM_COMPILE_THREADS} --nvcc_threads ${NUM_CUDA_COMPILE_THREADS} \
        --compile_no_warning_as_error --skip_submodule_sync \
        --cmake_extra_defines "CMAKE_CUDA_ARCHITECTURES=$(echo ${TARGET_CUDA_ARCH} | sed 's/\.//g')" --cmake_extra_defines CMAKE_INSTALL_PREFIX=/opt/onnx-built \
        --cudnn_home "/usr/include/aarch64-linux-gnu" --cuda_home /usr/local/cuda --use_cuda --use_tensorrt --tensorrt_home /opt/tensorrt --skip_tests \
    && cd build/Linux/Release \
    && make install \
    && cd /workspace \
    && rm -rf onnxruntime \
    # We have to move the headers up a layer to be consistent with the prebuilt versions
    && cd /opt/onnx-built/include/onnxruntime \
    && mv * .. \
    && cd .. \
    && rm -rf onnxruntime

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
RUN mkdir -p /tmp/eigen \
    && cd /tmp/eigen \
    && wget https://gitlab.com/libeigen/eigen/-/archive/3.3.9/eigen-3.3.9.zip \
    && unzip eigen-3.3.9.zip -d . \
    && mkdir /tmp/eigen/eigen-3.3.9/build && cd /tmp/eigen/eigen-3.3.9/build/ \
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
