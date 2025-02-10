# local: device in local
# remote: device not in local
ARG DEVICE_WHERE=local

FROM ubuntu:22.04 AS base

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# https://docs.docker.com/reference/dockerfile/#example-cache-apt-packages
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache


FROM base AS base-amd64
ARG ARCH=x86_64
RUN sed -i s@http://.*archive.ubuntu.com@http://repo.huaweicloud.com@g /etc/apt/sources.list \
    && sed -i s@http://.*security.ubuntu.com@http://repo.huaweicloud.com@g /etc/apt/sources.list


FROM base AS base-arm64
ARG ARCH=aarch64
RUN sed -i s@http://.*ports.ubuntu.com@http://mirrors4.tuna.tsinghua.edu.cn@g /etc/apt/sources.list


FROM base-${TARGETARCH} AS ascend-base

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,id="ascend/apt/cache",target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id="ascend/apt/lib",target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get --yes upgrade \
    && apt-get --yes install \
        build-essential \
        cmake \
        g++-aarch64-linux-gnu \
        libsqlite3-dev \
        zlib1g-dev \
        libssl-dev \
        libffi-dev \
        net-tools \
        pciutils \
        wget \
        curl \
        git \
        python3 \
        python3-dev \
        python3-pip \
        sudo

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

RUN pip config set global.index-url "https://mirrors.huaweicloud.com/repository/pypi/simple" \
    && pip config set global.trusted-host "mirrors.huaweicloud.com" \
    && python -m pip install --no-cache-dir --upgrade pip

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

WORKDIR /home/HwHiAiUser/
USER HwHiAiUser

FROM ascend-base AS ascend-cann-local
ARG ARCH
ARG TARGETOS
ARG CANN_VERSION="8.0.0"

ENV PATH=/home/HwHiAiUser/.local/bin:$PATH

# install python requirements for cann
ARG CANN_PYTHON_REQUIREMENTS="Ascend-cann-${CANN_VERSION}_requirements.txt"

RUN --mount=type=bind,target=/mnt/context \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    pip install --user -r /mnt/context/${CANN_PYTHON_REQUIREMENTS}

# install cann toolkit
ARG ASCEND_BASE=/home/HwHiAiUser/Ascend
ARG CANN_TOOLKIT_PKG="Ascend-cann-toolkit_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
RUN --mount=type=bind,target=/mnt/context,rw \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    sudo chmod +x /mnt/context/${ARCH}/${CANN_TOOLKIT_PKG} \
    && /mnt/context/${ARCH}/${CANN_TOOLKIT_PKG} --quiet --install --install-path=$ASCEND_BASE \
    && echo "source ${ASCEND_BASE}/ascend-toolkit/set_env.sh" >> ~/.bashrc

# install cann kernels
ARG ASCEND_CHIP_TYPE="310b"
ARG CANN_KERNELS_PKG="Ascend-cann-kernels-${ASCEND_CHIP_TYPE}_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
RUN --mount=type=bind,target=/mnt/context,rw \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    sudo chmod +x /mnt/context/${ARCH}/${CANN_KERNELS_PKG} \
    && /mnt/context/${ARCH}/${CANN_KERNELS_PKG} --quiet --install --install-path=$ASCEND_BASE

# install cann nnal
ARG CANN_NNAL_PKG="Ascend-cann-nnal_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
RUN --mount=type=bind,target=/mnt/context,rw \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    source ${ASCEND_BASE}/ascend-toolkit/set_env.sh \
    && sudo chmod +x /mnt/context/${ARCH}/${CANN_NNAL_PKG} \
    && /mnt/context/${ARCH}/${CANN_NNAL_PKG} --quiet --install --install-path=$ASCEND_BASE \
    && echo "source ${ASCEND_BASE}/nnal/atb/set_env.sh" >> ~/.bashrc

# install cann amct
ARG CANN_AMCT_PKG="Ascend-cann-amct_${CANN_VERSION}_${TARGETOS}-${ARCH}.tar.gz"
ARG AMCT_ONNX_RUNTIME_OP_INCLUDE="amct-onnx_runtime_v1.16.0-op-include"
RUN --mount=type=bind,target=/mnt/context \
    tar -zxf /mnt/context/${ARCH}/${CANN_AMCT_PKG} \
    && pip install --user --no-cache-dir amct/amct_onnx/*.whl \
    && tar -zxf amct/amct_onnx/amct_onnx_op.tar.gz -C amct/amct_onnx/\
    && cp /mnt/context/${AMCT_ONNX_RUNTIME_OP_INCLUDE}/* amct/amct_onnx/amct_onnx_op/inc/ \
    && python3 amct/amct_onnx/amct_onnx_op/setup.py build \
    && rm -rf amct build amct_log

FROM ascend-cann-local AS ascend-cann-remote
ARG ARCH
ARG ASCEND_BASE
ENV LD_LIBRARY_PATH=${ASCEND_BASE}/ascend-toolkit/latest/${ARCH}-linux/devlib


FROM ascend-cann-${DEVICE_WHERE} AS ascend-pytorch-base
ARG TORCH_VERSION="2.1.0"
RUN --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    pip install --user torch==${TORCH_VERSION} \
        --index-url https://download.pytorch.org/whl/cpu


FROM ascend-pytorch-base AS ascend-apex-builder

USER root

RUN --mount=type=cache,id="ascend/apt/cache",target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id="ascend/apt/lib",target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get --yes install \
        llvm \
        patch \
        libbz2-dev \
        libreadline-dev \
        libncurses5-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        liblzma-dev \
        m4 \
        dos2unix \
        libopenblas-dev

# bug of ascend apex，in npu.patch
RUN ln -s /usr/local/lib/python3.10/dist-packages/ /usr/lib/python3.10/site-packages \
    && ln -s /home/HwHiAiUser/.local/lib/python3.10/site-packages/* /usr/lib/python3.10/site-packages

USER HwHiAiUser

RUN git clone -b master https://gitee.com/ascend/apex.git \
    && chmod +x apex/scripts/build.sh \
    && apex/scripts/build.sh --python=3.10


FROM ascend-pytorch-base AS ascend-pytorch
# install Ascend Extension for PyTorch
ARG TORCH_VERSION
ARG TORCH_NPU_VERSION=${TORCH_VERSION}.post10

ARG ASCEND_TORCH_NPU_PYTHON_REQUIREMENTS="Ascend-torch_npu-${TORCH_NPU_VERSION}_requirements.txt"

RUN --mount=type=bind,target=/mnt/context \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    pip install --user -r /mnt/context/${ASCEND_TORCH_NPU_PYTHON_REQUIREMENTS} \
    && pip install --user torch-npu==${TORCH_NPU_VERSION}

# install other package about pytorch
RUN --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
pip install --user \
    'huggingface_hub[cli,torch]' \
    transformers

# install Ascend APEX
RUN --mount=type=bind,from=ascend-apex-builder,target=/mnt/apex-builder \
    pip install --user --no-cache-dir --upgrade /mnt/apex-builder/apex/apex/dist/apex-*.whl


FROM ascend-pytorch AS ascend-mindie
ARG TARGETOS
ARG ARCH
ARG ASCEND_BASE
ARG TORCH_VERSION
ARG MINDIE_VERSION="1.0.0"
ARG TORCH_ABI_VERSION="abi0"

# install ATB models
ARG ATB_MODELS_PKG="Ascend-mindie-atb-models_${MINDIE_VERSION}_${TARGETOS}-${ARCH}_py310_torch${TORCH_VERSION}-${TORCH_ABI_VERSION}.tar.gz"
ARG ATB_MODELS_INSTALL_PATH="${ASCEND_BASE}/MindIE-LLM/atb-models"
RUN --mount=type=bind,target=/mnt/context \
    mkdir -p ${ATB_MODELS_INSTALL_PATH} \
    && tar -zxf /mnt/context/${ARCH}/${ATB_MODELS_PKG} -C ${ATB_MODELS_INSTALL_PATH} \
    && pip install --user --no-cache-dir ${ATB_MODELS_INSTALL_PATH}/atb_llm-*-py3-none-any.whl \
    && echo "source ${ATB_MODELS_INSTALL_PATH}/set_env.sh" >> ~/.bashrc

# install python requirements for MindIE
ARG MINDIE_PYTHON_REQUIREMENTS="Ascend-MindIE_${MINDIE_VERSION}_requirements.txt"

RUN --mount=type=bind,target=/mnt/context \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    pip install --user -U -r /mnt/context/${MINDIE_PYTHON_REQUIREMENTS}

# install MindIE
ARG MINDIE_PKG="Ascend-mindie_${MINDIE_VERSION}_${TARGETOS}-${ARCH}.run"
# TODO diff abi logic. default abi0
RUN --mount=type=bind,target=/mnt/context,rw \
    --mount=type=cache,id=ascend/pip,target=/root/.cache/pip \
    source ${ASCEND_BASE}/ascend-toolkit/set_env.sh \
    && sudo chmod +x /mnt/context/${ARCH}/${MINDIE_PKG} \
    && /mnt/context/${ARCH}/${MINDIE_PKG} --quiet --install --install-path=$ASCEND_BASE \
    && echo "source ${ASCEND_BASE}/mindie/set_env.sh" >> ~/.bashrc


FROM ascend-mindie AS ascend-a200ia2

USER root

RUN ln -sf /lib /lib64 \
    && mkdir /var/dmp \
    && mkdir /usr/slog \
    && chown HwHiAiUser:HwHiAiUser /usr/slog \
    && chown HwHiAiUser:HwHiAiUser /var/dmp

USER HwHiAiUser

ENV LD_LIBRARY_PATH=/lib64:/usr/lib64:/usr/local/Ascend/driver/lib64

COPY --chown=HwHiAiUser:HwHiAiUser --chmod=754 entrypoint.sh /home/HwHiAiUser/entrypoint.sh
ENTRYPOINT ["/home/HwHiAiUser/entrypoint.sh"]
CMD ["bash"]
