ARG BASE_IMAGE=hexchip/base:ubuntu-22.04
ARG DEVICE_WHERE=local


FROM ${BASE_IMAGE} AS ascend-base-amd64
ARG ARCH=x86_64

FROM ${BASE_IMAGE} AS ascend-base-arm64
ARG ARCH=aarch64

FROM ascend-base-${TARGETARCH} AS ascend-base
ARG DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VERSION=3.10

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get --yes upgrade && \
    apt-get --yes install \
        build-essential \
        cmake \
        libsqlite3-dev \
        zlib1g-dev \
        libssl-dev \
        libffi-dev \
        net-tools \
        pciutils \
        wget \
        curl \
        vim \
        git \
        sudo

# 推理程序需要使用到底层驱动，底层驱动的运行依赖HwHiAiUser，HwBaseUser，HwDmUser三个用户
# 创建运行推理应用的用户及组，HwHiAiUse，HwDmUser，HwBaseUser的UID与GID分别为1000，1101，1102为例
RUN groupadd  HwHiAiUser -g 1000 \
    && groupadd HwDmUser -g 1101 \
    && groupadd HwBaseUser -g 1102 \
    && useradd -u 1000 -g 1000 -G 1101,1102 -d /home/HwHiAiUser -m -s /bin/bash HwHiAiUser \
    && useradd -u 1101 -g 1101 -d /home/HwDmUser -m -s /bin/bash HwDmUser \
    && useradd -u 1102 -g 1102 -d /home/HwBaseUser  -m -s /bin/bash HwBaseUser \
    && usermod -aG sudo HwHiAiUser \
    && echo "HwHiAiUser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/HwHiAiUser \
    && chmod 0440 /etc/sudoers.d/HwHiAiUser

USER HwHiAiUser

WORKDIR /home/HwHiAiUser/

RUN conda create -n cann python=${PYTHON_VERSION} && \
    echo "conda activate cann" >> ~/.bashrc

SHELL ["conda", "run", "-n", "cann", "/bin/bash", "-o", "pipefail", "-c"]

RUN pip config set global.index-url "https://mirrors.huaweicloud.com/repository/pypi/simple" && \
    pip config set global.trusted-host "mirrors.huaweicloud.com"

FROM ascend-base AS ascend-cann-local
ARG ARCH
ARG TARGETOS
ARG CANN_VERSION="8.1.RC1"

# install python requirements for cann
ARG CANN_PYTHON_REQUIREMENTS="Ascend-cann-${CANN_VERSION}_requirements.txt"
RUN --mount=type=bind,source=cann/toolkit/requirements,target=/mnt/context \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    pip install -r /mnt/context/${CANN_PYTHON_REQUIREMENTS}

# install cann toolkit
ARG ASCEND_INSTALL_PATH=/home/HwHiAiUser/Ascend
ARG CANN_TOOLKIT_PKG="Ascend-cann-toolkit_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
RUN --mount=type=bind,source=cann/toolkit/package,target=/mnt/context \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    /mnt/context/${ARCH}/${CANN_TOOLKIT_PKG} --quiet --install --install-path=${ASCEND_INSTALL_PATH} && \
    echo "source ${ASCEND_INSTALL_PATH}/ascend-toolkit/set_env.sh" >> ~/.bashrc

# install cann kernels
ARG ASCEND_CHIP_TYPE="310b"
ARG CANN_KERNELS_PKG="Ascend-cann-kernels-${ASCEND_CHIP_TYPE}_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
RUN --mount=type=bind,source=cann/kernels/package,target=/mnt/context \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    /mnt/context/${ARCH}/${CANN_KERNELS_PKG} --quiet --install --install-path=$ASCEND_INSTALL_PATH

# install cann nnal
ARG CANN_NNAL_PKG="Ascend-cann-nnal_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
RUN --mount=type=bind,source=cann/nnal/package,target=/mnt/context \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    source ${ASCEND_INSTALL_PATH}/ascend-toolkit/set_env.sh && \
    /mnt/context/${ARCH}/${CANN_NNAL_PKG} --quiet --install --install-path=$ASCEND_INSTALL_PATH


# install python requirements for cann amct onnx
ARG CANN_AMCT_PYTHON_REQUIREMENTS="Ascend-cann-amct_${CANN_VERSION}_requirements.txt"
RUN --mount=type=bind,source=cann/amct/onnx/requirements,target=/mnt/context \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    pip install -r /mnt/context/${CANN_AMCT_PYTHON_REQUIREMENTS}

# # install cann amct
ARG CANN_AMCT_PKG="Ascend-cann-amct_${CANN_VERSION}_${TARGETOS}-${ARCH}.tar.gz"
ARG AMCT_ONNX_RUNTIME_OP_INCLUDE="amct-onnx_runtime_v1.16.0-op-include"
RUN --mount=type=bind,source=cann/amct/package,target=/mnt/context/package \
    --mount=type=bind,source=cann/amct/onnx/src,target=/mnt/context/onnx/src \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    source ${ASCEND_INSTALL_PATH}/ascend-toolkit/set_env.sh && \
    tar -zxf /mnt/context/package/${ARCH}/${CANN_AMCT_PKG} && \
    pip install amct/amct_onnx/*.whl && \
    tar -zxf amct/amct_onnx/amct_onnx_op.tar.gz -C amct/amct_onnx/ && \
    cp /mnt/context/onnx/src/${AMCT_ONNX_RUNTIME_OP_INCLUDE}/* amct/amct_onnx/amct_onnx_op/inc/ && \
    python amct/amct_onnx/amct_onnx_op/setup.py build && \
    rm -rf amct build amct_log

FROM ascend-cann-local AS ascend-cann-remote
ARG ARCH
ARG ASCEND_INSTALL_PATH
ENV LD_LIBRARY_PATH=${ASCEND_INSTALL_PATH}/ascend-toolkit/latest/${ARCH}-linux/devlib


FROM ascend-cann-${DEVICE_WHERE} AS ascend-pytorch
ARG TORCH_VERSION="2.1.0"

RUN --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    pip install torch==${TORCH_VERSION} \
        --index-url https://download.pytorch.org/whl/cpu

# install Ascend Extension for PyTorch
ARG TORCH_NPU_VERSION=${TORCH_VERSION}.post12
ARG ASCEND_TORCH_NPU_PYTHON_REQUIREMENTS="Ascend-torch_npu-${TORCH_NPU_VERSION}_requirements.txt"

RUN --mount=type=bind,source=cann/torch_npu/requirements,target=/mnt/context \
    --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    pip install -r /mnt/context/${ASCEND_TORCH_NPU_PYTHON_REQUIREMENTS} \
    && pip install torch-npu==${TORCH_NPU_VERSION}

# install other package about pytorch
RUN --mount=type=cache,target=/home/HwHiAiUser/.cache/pip,uid=1000,gid=1000 \
    pip install \
        'huggingface_hub[cli]' \
        transformers

FROM ascend-pytorch AS ascend-310b
ARG DEVICE_WHERE
ENV HEXCHIP_ASCEND_DEVICE_WHERE=${DEVICE_WHERE}

ARG ASCEND_INSTALL_PATH
ENV HEXCHIP_ASCEND_HOME=${ASCEND_INSTALL_PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

RUN ln -sf /lib /lib64 \
    && mkdir /var/dmp \
    && mkdir /usr/slog \
    && chown HwHiAiUser:HwHiAiUser /usr/slog \
    && chown HwHiAiUser:HwHiAiUser /var/dmp

USER HwHiAiUser

ENV LD_LIBRARY_PATH=/lib64:/usr/lib64:/usr/lib64/aicpu_kernels:/usr/local/Ascend/driver/lib64

COPY --chown=HwHiAiUser:HwHiAiUser --chmod=754 entrypoint.sh /home/HwHiAiUser/entrypoint.sh
ENTRYPOINT ["/home/HwHiAiUser/entrypoint.sh"]
CMD ["bash"]
