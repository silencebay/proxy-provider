FROM golang:alpine AS builder
ARG TARGETPLATFORM
ARG NAIVEPROXY_PRERELEASE
ARG XRAY_PRERELEASE
ARG NAIVEPROXY_TAGNAME
ARG XRAY_TAGNAME
ARG CHANGESOURCE=false
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64} \
    NAIVEPROXY_PRERELEASE=${NAIVEPROXY_PRERELEASE:-''} \
    XRAY_PRERELEASE=${XRAY_PRERELEASE:-''} \
    NAIVEPROXY_TAGNAME=${NAIVEPROXY_TAGNAME:-''} \
    XRAY_TAGNAME=${XRAY_TAGNAME:-''}

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache curl jq

WORKDIR /go/artifact
RUN set -eux; \
    \
    echo "**** builder: setup package source ****"; \
    if [ ${CHANGESOURCE} = true ]; then \
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories; \
    fi; \
    \
    echo "**** builder: install packages ****"; \
    apk add --no-cache \
        curl \
        jq \
    ; \
    \
    echo "**** builder: install naiveproxy ****"; \
    architecture=openwrt-x86_64; \
    case ${TARGETPLATFORM} in \
        "linux/amd64")  architecture=openwrt-x86_64  ;; \
        "linux/arm64")  architecture=openwrt-aarch64_generic ;; \
        "linux/arm/v7") architecture=openwrt-arm_cortex-a15_neon-vfpv4 ;; \
    esac; \
    \
    if [ -z "${NAIVEPROXY_TAGNAME}" ]; then \
        if [ -z "${NAIVEPROXY_PRERELEASE}" ]; then \
            download_url=$(curl -L "https://api.github.com/repos/klzgrad/naiveproxy/releases/latest?per_page=1" | jq -r --arg asset "^naiveproxy-.*${architecture}" '.assets[] | select (.name | test($asset))| .browser_download_url' -); \
        else \
            download_url=$(curl -L "https://api.github.com/repos/klzgrad/naiveproxy/releases?per_page=1" | jq -r --arg asset "^naiveproxy-.*${architecture}" '.[].assets[] | select (.name | test($asset))| .browser_download_url' -); \
        \
        fi; \
    else \
        download_url=$(curl -L "https://api.github.com/repos/klzgrad/naiveproxy/releases?per_page=100" | jq -r --arg asset "^naiveproxy-.*${architecture}" --arg tag_name "${NAIVEPROXY_TAGNAME}" '.[].assets[] | select(.name | test($asset)) and select(.tag_name | test($tag_name)) | .browser_download_url' -); \
    fi; \
    curl -L $download_url | tar x -Jvf -; \
    mv naiveproxy-* naiveproxy; \
    \
    echo "**** builder: install xray ****"; \
    architecture=linux-64; \
    case ${TARGETPLATFORM} in \
        "linux/amd64")                 architecture=linux-64  ;; \
        "linux/arm64"|"linux/arm64/v8")  architecture=linux-arm64 ;; \
        "linux/arm/v7")                architecture=linux-arm32 ;; \
    esac; \
    \
    if [ -z "${XRAY_TAGNAME}" ]; then \
        if [ -z "${XRAY_PRERELEASE}" ]; then \
            download_url=$(curl -L "https://api.github.com/repos/XTLS/Xray-core/releases/latest?per_page=1" | jq -r --arg asset "^Xray-.*$architecture.*\.zip$" '.assets[] | select (.name | test($asset))| .browser_download_url' -); \
        else \
            download_url=$(curl -L "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=1" | jq -r --arg asset "^Xray-.*$architecture.*\.zip$" '.[].assets[] | select (.name | test($asset))| .browser_download_url' -); \
        \
        fi; \
    else \
        download_url=$(curl -L "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r --arg asset "^Xray-.*$architecture.*\.zip$" '.[].assets[] | select(.name | test($asset)) and select(.tag_name | test($tag_name)) | .browser_download_url' -); \
    fi; \
    curl -L $download_url -o temp.zip; \
    unzip temp.zip -d xray; \
    rm temp.zip;


FROM ghcr.io/linuxserver/baseimage-alpine:3.17 as runtime

COPY --from=builder /go/artifact/. /artifact/

RUN set -eux; \
    \
    echo "**** install packages ****"; \
    apk add --no-cache --virtual .run-deps \
        mawk \
        # naiveproxy dependencies
        libgcc \
    ; \
    \
    echo "**** runtime: place the artifact ****"; \
    mkdir -p /config/naiveproxy; \
    mkdir -p /config/xray; \
    mv /artifact/naiveproxy/naive /usr/local/bin; \
    mv /artifact/naiveproxy/config.json /config; \
    mv /artifact/xray/xray /usr/local/bin; \
    mv /artifact/xray/*.dat /config/xray/; \
    rm /artifact -rf; \
    \
    chmod +x /usr/local/bin/*; \
    chown -R abc:abc /config;