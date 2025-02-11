# 华为昇腾开发环境

基于ubuntu:22.04，安装了python3.10与昇腾开发所需软件与其依赖。  
支持多平台构建。

## 快速开始

执行如下命令拉取镜像：

    docker pull hexchip/ascend-dev:cann8.0.0-310b-pytorch2.1.0-mindie1.0.0

如果不能访问dockerhub，执行如下命令拉取镜像：

    # arm64
    docker pull registry.cn-hangzhou.aliyuncs.com/hexchip/ascend-dev:arm64-cann8.0.0-310b-pytorch2.1.0-mindie1.0.0
    # amd64
    docker pull registry.cn-hangzhou.aliyuncs.com/hexchip/ascend-dev:amd64-cann8.0.0-310b-pytorch2.1.0-mindie1.0.0

### 如果容器运行在拥有昇腾设备的主机上

1. 需要安装[Ascend Docker Runtime](https://www.hiascend.com/document/detail/zh/mindx-dl/)
2. 通过命令 `ls /dev` 查看 `/dev/davinciX` 可挂载芯片，确定**挂载芯片参数**`ASCEND_VISIBLE_DEVICES`的值

### 启动容器

```
docker run -it --rm \
-e ASCEND_VISIBLE_DEVICES=0 \
-e ASCEND_ALLOW_LINK=True \
-v .:/workspace
-v ~/.cache/huggingface:/home/HwHiAiUser/.cache/huggingface \
hexchip/ascend-dev:cann8.0.0-310b-pytorch2.1.0-mindie1.0.0
```

注：  
- `-e ASCEND_VISIBLE_DEVICES=0` 仅容器运行在拥有昇腾设备的主机上时需要。
- `-e ASCEND_ALLOW_LINK=True` 仅 **Atlas 200I/500 A2**系列的昇腾设备 需要
- `-v .:/home/HwHiAiUser/workspace` 挂载当前目录。
- `-v ~/.cache/huggingface:/home/HwHiAiUser/.cache/huggingface` 挂载huggingface缓存

## 目前包括的列昇腾软件列表：

- CANN
    - toolkit
    - kernels
    - amct
        - onnx
    - nnal
- Ascend Extension for PyTorch
- Ascend APEX
- MindIE
    - atb-models

## 构建参数

### 设备位置

    ARG DEVICE_WHERE=remote

如果你的容器运行在没有昇腾设备的主机上，请设置为`remote`，否则设置为`local`。默认为`local`。

### 版本

可以通过下列构建参数指定版本，下列为各参数与其默认值。

    ARG CANN_VERSION="8.0.0"
    ARG ASCEND_CHIP_TYPE="310b"
    ARG TORCH_VERSION="2.1.0"
    ARG TORCH_NPU_VERSION=${TORCH_VERSION}.post10
    ARG MINDIE_VERSION="1.0.0"
    ARG TORCH_ABI_VERSION="abi0"

需要自行下载对应版本的软件安装包，将其按约定的目录结构放置。

### 安装包

官方安装包的命名规则如下：

    ARG CANN_TOOLKIT_PKG="Ascend-cann-toolkit_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
    ARG CANN_KERNELS_PKG="Ascend-cann-kernels-${ASCEND_CHIP_TYPE}_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
    ARG CANN_AMCT_PKG="Ascend-cann-amct_${CANN_VERSION}_${TARGETOS}-${ARCH}.tar.gz"
    ARG CANN_NNAL_PKG="Ascend-cann-nnal_${CANN_VERSION}_${TARGETOS}-${ARCH}.run"
    ARG ATB_MODELS_PKG="Ascend-mindie-atb-models_${MINDIE_VERSION}_${TARGETOS}-${ARCH}_py310_torch${TORCH_VERSION}-${TORCH_ABI_VERSION}.tar.gz"
    ARG MINDIE_PKG="Ascend-mindie_${MINDIE_VERSION}_${TARGETOS}-${ARCH}.run"

注：一般指定版本参数即可，包名参数依据命名规则由版本参数与其他参数构成。

构成包名的其他参数目前包括：

- TARGETOS  
  这是预定义的构建参数，由 `docker build` 的 `--platform` 指定。  
  例如 `docker build --platform linux/amd64,linux/arm64`。  
  其中的`linux`就是`TARGETOS`， `amd64或者arm64`就是`TARGETARCH`
- ARCH  
  这是自定义的构建参数，由预定义参数`TARGETARCH`决定。  
  当`TARGETARCH`为`amd64`，则ARCH为`x86_64`  
  当`TARGETARCH`为`arm64`，则ARCH为`aarch64`

注：请勿直接指定`TARGETOS`和`ARCH`的值，应该由`--platform`指定。  
当没有指定`--platform`时，`--platform`默认为当前执行`docker build`的platform的信息。  
例如你的系统是Linux，cpu架构为amd64. 则等价于指定`--platform=linux/amd64`。
如欲了解更多平台构建的信息，请参考[docker docs](https://docs.docker.com/build/building/multi-platform/)。

### python requirements

各软件包都有其对应的python依赖，使用requirements.txt文件来表示。

当前支持的参数如下：

    ARG CANN_PYTHON_REQUIREMENTS="Ascend-cann-${CANN_VERSION}_requirements.txt"
    ARG ASCEND_TORCH_NPU_PYTHON_REQUIREMENTS="Ascend-torch_npu-${TORCH_NPU_VERSION}_requirements.txt"
    ARG MINDIE_PYTHON_REQUIREMENTS="Ascend-MindIE_${MINDIE_VERSION}_requirements.txt"

注：`TORCH_NPU_VERSION`的命名规则请参考 https://gitee.com/ascend/pytorch

### 其他参数

    ARG AMCT_ONNX_RUNTIME_OP_INCLUDE="amct-onnx_runtime_v1.16.0-op-include"

- AMCT_ONNX_RUNTIME_OP_INCLUDE  
  构建**amct_onnx_op**所需的头文件目录  
  具体信息请参考：[昇腾社区文档](https://www.hiascend.com/document/detail/zh/CANNCommunityEdition)
  ->开发工具
  ->模型压缩AMCT工具
  ->工具安装
  ->安装后处理
  ->AMCT(ONNX)
  ->编译并安装自定义包

## 示例目录结构

```
.
├── Ascend-MindIE_1.0.0_requirements.txt
├── Ascend-cann-8.0.0_requirements.txt
├── Ascend-torch_npu-2.1.0.post10_requirements.txt
├── Dockerfile
├── README.md
├── aarch64
│   ├── Ascend-cann-amct_8.0.0_linux-aarch64.tar.gz
│   ├── Ascend-cann-kernels-310b_8.0.0_linux-aarch64.run
│   ├── Ascend-cann-nnal_8.0.0_linux-aarch64.run
│   ├── Ascend-cann-toolkit_8.0.0_linux-aarch64.run
│   ├── Ascend-mindie-atb-models_1.0.0_linux-aarch64_py310_torch2.1.0-abi0.tar.gz
│   └── Ascend-mindie_1.0.0_linux-aarch64.run
├── amct-onnx_runtime_v1.16.0-op-include
│   ├── environment.h
│   ├── experimental_onnxruntime_cxx_api.h
│   ├── experimental_onnxruntime_cxx_inline.h
│   ├── onnxruntime_c_api.h
│   ├── onnxruntime_cxx_api.h
│   ├── onnxruntime_cxx_inline.h
│   ├── onnxruntime_float16.h
│   ├── onnxruntime_lite_custom_op.h
│   ├── onnxruntime_run_options_config_keys.h
│   └── onnxruntime_session_options_config_keys.h
└── x86_64
    ├── Ascend-cann-amct_8.0.0_linux-x86_64.tar.gz
    ├── Ascend-cann-kernels-310b_8.0.0_linux-x86_64.run
    ├── Ascend-cann-nnal_8.0.0_linux-x86_64.run
    ├── Ascend-cann-toolkit_8.0.0_linux-x86_64.run
    ├── Ascend-mindie-atb-models_1.0.0_linux-x86_64_py310_torch2.1.0-abi0.tar.gz
    └── Ascend-mindie_1.0.0_linux-x86_64.run
```