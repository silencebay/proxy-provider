FROM --platform=$TARGETPLATFORM golang:alpine AS builder
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

WORKDIR /go

RUN <<EOF
    set -eux

    echo "**** builder: prepare locations ****"
    rootfs="/go/rootfs"
    mkdir -p "$rootfs/usr/local/bin"
    mkdir -p "$rootfs/config/xray"

    echo "**** builder: setup package source ****"
    if [ ${CHANGESOURCE} = true ]; then
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
    fi

    echo "**** builder: install packages ****"
    apk add --no-cache \
        curl \
        jq

    echo "**** builder: install naiveproxy ****"
    architecture=openwrt-x86_64
    case ${TARGETPLATFORM} in
        "linux/amd64")  architecture=openwrt-x86_64  ;;
        "linux/arm64")  architecture=openwrt-aarch64_generic ;;
        "linux/arm/v7") architecture=openwrt-arm_cortex-a15_neon-vfpv4 ;;
    esac

    repo_api="https://api.github.com/repos/klzgrad/naiveproxy/releases";
    asset_pattern="^naiveproxy-.*${architecture}";
    if [ -z "${NAIVEPROXY_TAGNAME}" ]; then
        if [ -z "${NAIVEPROXY_PRERELEASE}" ]; then
            download_url=$(curl -L "$repo_api?per_page=100" \
                | jq -r --arg asset "$asset_pattern" '
                [.[] | select(((.assets | length) > 0) and (.prerelease==false))]
                | first
                | .assets[]
                | select (.name | test($asset))
                | .browser_download_url' -)
        else
            download_url=$(curl -L "$repo_api?per_page=100" \
                | jq -r --arg asset "$asset_pattern" '
                [.[] | select((.assets | length) > 0)]
                | first
                | .assets[]
                | select (.name | test($asset))
                | .browser_download_url' -)
        fi
    else
        download_url=$(curl -L "$repo_api?per_page=100" \
            | jq -r --arg asset "$asset_pattern" --arg tag_name "${NAIVEPROXY_TAGNAME}" '
            [.[] | select(((.assets | length) > 0) and (.tag_name | test($tag_name)))]
            | first
            | .assets[]
            | select(.name | test($asset))
            | .browser_download_url' -)
    fi
    curl -L $download_url | tar x -Jvf -
    mv naiveproxy-*/naive "$rootfs/usr/local/bin/"
    mv naiveproxy-*/config.json "$rootfs/config/"
    rm -rf naiveproxy-*

    echo "**** builder: install xray ****"
    architecture=linux-64
    case ${TARGETPLATFORM} in
        "linux/amd64")                   architecture=linux-64  ;;
        "linux/arm64"|"linux/arm64/v8")  architecture=linux-arm64 ;;
        "linux/arm/v7")                  architecture=linux-arm32 ;;
    esac

    repo_api="https://api.github.com/repos/XTLS/Xray-core/releases"
    asset_pattern="^Xray-.*$architecture.*\.zip$"
    if [ -z "${XRAY_TAGNAME}" ]; then
        if [ -z "${XRAY_PRERELEASE}" ]; then
            download_url=$(curl -L "$repo_api?per_page=100" \
                | jq -r --arg asset "$asset_pattern" '
                [.[] | select(((.assets | length) > 0) and (.prerelease==false))]
                | first
                | .assets[]
                | select (.name | test($asset))
                | .browser_download_url' -)

        else
            download_url=$(curl -L "$repo_api?per_page=100" \
                | jq -r --arg asset "$asset_pattern" '
                [.[] | select((.assets | length) > 0)]
                | first
                | .assets[]
                | select (.name | test($asset))
                | .browser_download_url' -)
        fi
    else
        download_url=$(curl -L "$repo_api?per_page=100" \
            | jq -r --arg asset "$asset_pattern" '
            [.[] | select(((.assets | length) > 0) and (.tag_name | test($tag_name)))]
            | first
            | .assets[]
            | select(.name | test($asset))
            | .browser_download_url' -)
    fi
    curl -L $download_url -o temp.zip
    unzip temp.zip -d xray
    mv xray/xray "$rootfs/usr/local/bin/"
    mv xray/*.dat "$rootfs/config/xray/"
    rm -rf temp.zip xray
EOF

FROM lsiobase/alpine:3.18 as runtime

COPY --from=builder /go/rootfs/. /

RUN <<EOF
    set -eux

    echo "**** install packages ****"
    apk add --no-cache --virtual .run-deps \
        mawk \
        libgcc  # naiveproxy dependencies

    echo "**** runtime: fix permissions ****"
    chmod +x /usr/local/bin/*
    chown -R abc:abc /config
EOF