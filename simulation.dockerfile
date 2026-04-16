FROM nvcr.io/nvidia/tensorrt:26.02-py3

# Required for supporting DISPLAY passthrough
ARG TARGET_CUDA_ARCH
ENV DISPLAY=:0
ENV DEBIAN_FRONTEND=noninteractive
COPY --chmod=700 scripts/Entrypoint.sh /Entrypoint.sh
COPY scripts/fastRTPS_fix.xml /workspace/fastRTPS_fix.xml

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
    && echo 'export OMNI_KIT_ALLOW_ROOT=1' >> ~/.bashrc \
    && echo 'export LANG=en_US.UTF-8' >> ~/.bashrc \
    && echo 'source /workspace/ros_packages/install/local_setup.bash' >> ~/.bashrc \
    && echo 'export FASTRTPS_DEFAULT_PROFILES_FILE=/workspace/fastRTPS_fix.xml' >> ~/.bashrc

# onnxruntime
COPY scripts/InstallOnnxRuntime.py /tmp/InstallOnnxRuntime.py
RUN python3 /tmp/InstallOnnxRuntime.py --owner microsoft --repo onnxruntime --dir /opt --tag latest --regex "^onnxruntime-linux-x64-gpu_cuda13-.+\\.tgz$" \
    && rm /tmp/InstallOnnxRuntime.py

# ROS2 and NVIDIA Nitros
RUN export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && apt update \
    && apt install -y ros-dev-tools ros-jazzy-desktop \
    && rm /tmp/ros2-apt-source.deb \
    && k="/usr/share/keyrings/nvidia-isaac-ros.gpg" \
    && curl -fsSL https://isaac.download.nvidia.com/isaac-ros/repos.key | gpg --dearmor | tee -a $k > /dev/null \
    && f="/etc/apt/sources.list.d/nvidia-isaac-ros.list" \
    && touch $f \
    && s="deb [signed-by=$k] https://isaac.download.nvidia.com/isaac-ros/release-4.3 noble main" \
    && grep -qxF "$s" $f || echo "$s" | tee -a $f \
    && apt update \
    && apt install -y isaac-ros-cli \
    && apt-key adv --fetch-key https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    && echo 'deb https://repo.download.nvidia.com/jetson/x86_64/noble r38.4 main' | tee /etc/apt/sources.list.d/nvidia-jetson-apt-source.list \
    && apt update \
    && rosdep init \
    && curl -o /etc/ros/rosdep/sources.list.d/nvidia-isaac.yaml https://raw.githubusercontent.com/NVIDIA-ISAAC-ROS/isaac-ros-cli/release-4.3/docker/rosdep/extra_rosdeps.yaml \
    && echo "yaml file:///etc/ros/rosdep/sources.list.d/nvidia-isaac.yaml" | tee /etc/ros/rosdep/sources.list.d/00-nvidia-isaac.list \
    && rosdep update \
    && isaac-ros init baremetal --yes \
    && apt install -y --allow-downgrades ros-jazzy-isaac-ros-common ros-jazzy-isaac-ros-nitros ros-jazzy-isaac-ros-managed-nitros ros-jazzy-isaac-ros-nitros-image-type \
    && apt clean

# Isaac Sim
RUN git clone https://github.com/isaac-sim/IsaacSim.git --depth=1 /opt/isaacsim \
    && cd /opt/isaacsim \
    && git lfs pull \
    && touch .eula_accepted \
    && bash build.sh \
    && ln -s /opt/isaacsim/_build/linux-x86_64/release /opt/isaacsim_interface

# Install reachy model
WORKDIR /opt/isaacsim_interface
RUN mkdir additional_resources \
    && cd additional_resources \
    && git clone https://github.com/harrywyatt5/reachy2-isaac-sim-with-cameras.git --depth=1 reachy2

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

# Install llama.cpp (we pick a specific commit because they always seem to introduce breaking changes...)
RUN cd /opt \
    && git clone --depth 1 -b b8815 https://github.com/ggml-org/llama.cpp.git \
    && cd llama.cpp \
    && mkdir build \
    && cd build \
    && ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
    && export LIBRARY_PATH=/usr/local/cuda/lib64/stubs:$LIBRARY_PATH \
    && cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$(echo ${TARGET_CUDA_ARCH} | sed 's/\.//g')" -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=/usr \
    && cmake --build . --config Release -j $(nproc) \
    && cmake --install . \
    && ldconfig \
    && rm /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
    && rm -rf /opt/llama.cpp

# Install our packages
RUN cd /workspace \
    && mkdir ros_packages \
    && cd ros_packages \
    && mkdir src \
    && git clone --depth 1 -b share-cuda-stream https://github.com/harrywyatt5/detecting-humans-computer-vision.git \
    && cd detecting-humans-computer-vision \
    && mkdir sam3-onnx \
    && cd sam3-onnx \
    && wget https://github.com/harrywyatt5/detecting-humans-computer-vision/releases/download/model-release/decoder-static.onnx \
    && wget https://github.com/harrywyatt5/detecting-humans-computer-vision/releases/download/model-release/text-encoder-static.onnx \
    && wget https://github.com/harrywyatt5/detecting-humans-computer-vision/releases/download/model-release/vision-encoder-static.onnx \
    && cd ../.. \
    && git clone --depth 1 https://github.com/harrywyatt5/detecting-groups.git \
    && cd detecting-groups \
    && cd gemma-model \
    && wget https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \
    && wget https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/mmproj-F16.gguf \
    && cd ../.. \
    && git clone --depth 1 https://github.com/harrywyatt5/detecting-groups-custom-msg.git \
    && source /opt/ros/jazzy/setup.bash \
    && ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
    && colcon build --symlink-install --cmake-args -DCMAKE_CUDA_ARCHITECTURES="$(echo ${TARGET_CUDA_ARCH} | sed 's/\.//g')" -DCMAKE_BUILD_TYPE=Release \
    && rm /usr/lib/x86_64-linux-gnu/libcuda.so.1 

WORKDIR /workspace
ENTRYPOINT ["/Entrypoint.sh"]
CMD ["/bin/bash"]
