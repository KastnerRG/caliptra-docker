# Base image
FROM centos:7.3.1611

RUN sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|# baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo


# Install dependencies
RUN yum -y groupinstall "Development Tools" && \
    yum -y install \
    gcc gcc-c++ \
    make \
    glibc-devel \
    libX11-devel libXtst libXrender libXft fontconfig \
    wget curl which unzip \
    sudo \
    libstdc++-static \
    epel-release && \
    yum clean all

# Optional: Install GCC 9.2 and binutils 2.33.1
RUN yum -y install centos-release-scl 

RUN ls -l /etc/yum.repos.d

RUN echo "=== CentOS-SCLo-scl.repo ===" && \
    cat /etc/yum.repos.d/CentOS-SCLo-scl.repo

# Fix broken SCL repo files by pointing to vault
RUN sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-*.repo && \
    sed -i 's|# baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo && \
    sed -i 's|baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo
#RUN sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-SCLo-scl.repo && \
#    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-SCLo-scl.repo && \
#    sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo && \
#    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo

RUN yum -y install devtoolset-9 && \
    yum clean all

# Use GCC 9.2
ENV PATH=/opt/rh/devtoolset-9/root/usr/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/rh/devtoolset-9/root/usr/lib64:$LD_LIBRARY_PATH

ENV VCS_ARCH_OVERRIDE="linux"   \
    VCS_HOME="/tools/Synopsys/vcs/T-2022.06-SP2-10" \
    SNPSLMD_LICENSE_FILE="1705@its-flexlm-lnx4.ucsd.edu" 
ENV PATH=$VCS_HOME/bin:$PATH 

RUN yum install -y \
       autoconf              \
       automake              \
       python3               \
       python-is-python3     \
       libmpc-dev            \
       mpfr-devel            \
       gmp-devel             \
       gawk                  \
       bison                 \
       flex                  \
       texinfo               \
       patchutils            \
       zlib-devel            \
       expat-devel           \
       libslirp-devel

ENV RISCV=/opt/riscv
ENV PATH=$PATH:$RISCV/bin

ARG TOOLCHAIN_VERSION=2023.04.29

RUN yum install -y ca-certificates \
    && update-ca-trust force-enable
    #Updating CA certificates is necessary for git clone to work properly on binutils

RUN    git clone --recursive https://github.com/riscv/riscv-gnu-toolchain -b ${TOOLCHAIN_VERSION} \
    && cd riscv-gnu-toolchain                                                                     \
    && ./configure --enable-multilib --prefix=$RISCV --with-multilib-generator="rv32imc-ilp32--a*zicsr*zifencei"\
    && make                                                                                       \
    && cd ..                                                                                      \
    && rm -rf riscv-gnu-toolchain

# Set Caliptra-related environment variables
ENV CALIPTRA_WORKSPACE=/home/caliptra-vcs-usr/caliptra-workspace
ENV CALIPTRA_ROOT=$CALIPTRA_WORKSPACE/chipsalliance/caliptra-rtl
ENV ADAMSBRIDGE_ROOT=$CALIPTRA_ROOT/submodules/adams-bridge
ENV CALIPTRA_AXI4PC_DIR=$CALIPTRA_ROOT/src/integration/tb

# Enviromental fixes
RUN yum install -y \
    bc \
    time
    
# Step 3: Change to non-root user
ARG USERNAME=caliptra-vcs-usr
ARG USER_UID=1003
ARG USER_GID=1004

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} \
    && chown -R ${USERNAME}:${USERNAME} /opt/riscv

USER ${USERNAME}
WORKDIR /home/${USERNAME}
