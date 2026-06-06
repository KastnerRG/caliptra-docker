# Base image
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

ARG VERILATOR_VERSION=v5.044
ARG VCS_HOME=/tools/Synopsys/vcs/T-2022.06-SP2-10
ARG SNPSLMD_LICENSE_FILE=1705@its-flexlm-lnx4.ucsd.edu

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
       autoconf              \
       automake              \
       bash-completion       \
       bc                    \
       bison                 \
       build-essential       \
       ca-certificates       \
       curl                  \
       dc                    \
       debianutils           \
       expat                 \
       flex                  \
       fontconfig            \
       gawk                  \
       git                   \
       gtkwave               \
       help2man              \
       less                  \
       libexpat1-dev         \
       libelf1               \
       libfl-dev             \
       libfl2                \
       libgmp-dev            \
       libmpc-dev            \
       libmpfr-dev           \
       libslirp-dev          \
       libx11-dev            \
       libxft-dev            \
       libxrender-dev        \
       libxtst6              \
       patchutils            \
       perl                  \
       python-is-python3     \
       python3               \
       rsync                 \
       sudo                  \
       texinfo               \
       time                  \
       unzip                 \
       vim                   \
       wget                  \
       xauth                 \
       zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --single-branch --branch "${VERILATOR_VERSION}" https://github.com/verilator/verilator.git /tmp/verilator \
    && cd /tmp/verilator \
    && autoconf \
    && ./configure \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/verilator

ENV VCS_ARCH_OVERRIDE=linux \
    VCS_HOME=${VCS_HOME} \
    SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE}
ENV PATH=${VCS_HOME}/bin:${PATH}

ENV RISCV=/opt/riscv
ENV PATH=${PATH}:${RISCV}/bin

ARG TOOLCHAIN_VERSION=2023.04.29

RUN git clone --recursive https://github.com/riscv/riscv-gnu-toolchain -b ${TOOLCHAIN_VERSION} \
    && cd riscv-gnu-toolchain \
    && ./configure --enable-multilib --prefix=${RISCV} --with-multilib-generator="rv32imc-ilp32--a*zicsr*zifencei" \
    && make \
    && cd .. \
    && rm -rf riscv-gnu-toolchain

# Set Caliptra-related environment variables
# CALIPTRA_WORKSPACE is the root of the mounted repo (caliptra-docker/).
# Inside the container it is /home/usr/ws; subdirs are:
#   caliptra-rtl/   firebridge/   experiments/
ENV CALIPTRA_WORKSPACE=/home/usr/ws
ENV CALIPTRA_ROOT=${CALIPTRA_WORKSPACE}/caliptra-rtl
ENV ADAMSBRIDGE_ROOT=${CALIPTRA_ROOT}/submodules/adams-bridge
ENV CALIPTRA_AXI4PC_DIR=${CALIPTRA_ROOT}/src/integration/tb
ENV CALIPTRA_PRIM_ROOT=${CALIPTRA_ROOT}/src/caliptra_prim_generic
ENV CALIPTRA_PRIM_MODULE_PREFIX=caliptra_prim_generic

# VCS tool scripts use #!/bin/sh -h (a ksh/bash flag); dash rejects -h.
RUN ln -sf bash /bin/sh

# Change to non-root user
ARG USERNAME=usr
ARG UID=1000
ARG GID=1000

RUN groupadd --gid ${GID} ${USERNAME} \
    && useradd --uid ${UID} --gid ${GID} -m -s /bin/bash ${USERNAME} \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} \
    && chown -R ${USERNAME}:${USERNAME} /opt/riscv

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV USER=${USERNAME} \
    HOME=/home/${USERNAME}

RUN cat >> "/home/${USERNAME}/.bashrc" <<'EOF_BASHRC'
export PS1="\[\e[0;33m\][\u@\h \W]\$ \[\e[m\] "
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
EOF_BASHRC
