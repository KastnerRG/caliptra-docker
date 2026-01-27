# Base image
FROM rockylinux:8


# Install dependencies
RUN yum -y update && \
    yum -y install dnf-plugins-core && \
    yum config-manager --set-enabled powertools && \
    yum -y groupinstall "Development Tools" && \
    yum -y install redhat-lsb libXScrnSaver scl-utils dtc && \
    yum -y install gcc-toolset-11 && \
    yum clean all

RUN yum install -y \
       autoconf              \
       automake              \
       python3               \
       libmpc-devel            \
       mpfr-devel            \
       gmp-devel             \
       gawk                  \
       bison                 \
       flex                  \
       texinfo               \
       gcc                  \
       gcc-c++              \
       patchutils            \
       zlib-devel            \
       expat-devel           \
       libslirp-devel     \ 
       ncurses-devel         

ENV RISCV=/opt/riscv
ENV PATH=$PATH:$RISCV/bin

#ARG TOOLCHAIN_VERSION=2023.04.29

RUN yum install -y ca-certificates \
    && update-ca-trust force-enable
    #Updating CA certificates is necessary for git clone to work properly on binutils

RUN    git clone --recursive https://github.com/riscv/riscv-gnu-toolchain      \
    && cd riscv-gnu-toolchain                                                  \
    && ./configure --prefix=$RISCV                                             \
    && make                                                                    \
    && cd ..                                                                   \
    && rm -rf riscv-gnu-toolchain

ENV VCS_ARCH_OVERRIDE="linux"
ARG VCS_HOME
ENV PATH=$VCS_HOME/bin:$PATH 

# Enviromental fixes
RUN yum install -y \
    bc \
    time
    
# Additional dependencies required for yosys (not coverd by Dejavuzz repo)
RUN yum -y install epel-release

RUN yum install -y \
        tcl-devel \
        lld \
        clang \
        flex \
        libffi-devel \
        readline-devel \
        libconfig-devel \
        pkgconf \
        graphviz 

RUN yum -y install python3.11 python3.11-pip python3.11-devel && \
    # 1. Nuke existing links for clean slate
    rm -f /usr/bin/python /usr/bin/python3 /usr/bin/pip /usr/bin/pip3 && \
    # 2. Link EVERYTHING to 3.11
    ln -sf /usr/bin/python3.11 /usr/bin/python && \
    ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
    ln -sf /usr/bin/pip3.11 /usr/bin/pip && \
    ln -sf /usr/bin/pip3.11 /usr/bin/pip3

# 1. Install Java (JDK 11 is a safe default for modern sbt)
RUN yum -y install java-11-openjdk-devel

# 2. Add the official sbt RPM repository and install sbt
RUN rm -f /etc/yum.repos.d/bintray-rpm.repo && \
    curl -L https://www.scala-sbt.org/sbt-rpm.repo > sbt-rpm.repo && \
    mv sbt-rpm.repo /etc/yum.repos.d/ && \
    yum -y install sbt

# enable gcc-toolset-11 ...
# Permanently enable GCC 11 for all future commands and interactive shells
ENV PATH=/opt/rh/gcc-toolset-11/root/usr/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/rh/gcc-toolset-11/root/usr/lib64:$LD_LIBRARY_PATH
ENV PKG_CONFIG_PATH=/opt/rh/gcc-toolset-11/root/usr/lib64/pkgconfig:$PKG_CONFIG_PATH

# Step 3: Change to non-root user
ARG USERNAME=usr
ARG UID=1000
ARG GID=1000

RUN groupadd --gid ${GID} ${USERNAME} \
    && useradd --uid ${UID} --gid ${GID} -m ${USERNAME} \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} \
    && chown -R ${USERNAME}:${USERNAME} /opt/riscv

USER ${USERNAME}
WORKDIR /home/${USERNAME}

COPY ./ws/usr/DejaVuzz/requirements.txt /home/${USERNAME}/requirements.txt
RUN  pip3 install -r /home/${USERNAME}/requirements.txt  \
    && rm /home/${USERNAME}/requirements.txt

RUN force_color_prompt=yes
ENV PS1="\e[0;33m[\u@\h \W]\$ \e[m "
