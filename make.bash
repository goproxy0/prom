#!/bin/bash

set -ex

REVSION=$(git rev-list --count HEAD)
LDFLAGS="-s -w -X main.version=r${REVSION}"

GOOS=${GOOS:-$(go env GOOS)}
GOARCH=${GOARCH:-$(go env GOARCH)}
CGO_ENABLED=${CGO_ENABLED:-$(go env CGO_ENABLED)}

REPO=$(git rev-parse --show-toplevel)
PACKAGE=$(basename ${REPO})
if [ "${CGO_ENABLED}" = "0" ]; then
    BUILDROOT=${REPO}/build/${GOOS}_${GOARCH}
else
    BUILDROOT=${REPO}/build/${GOOS}_${GOARCH}_cgo
fi
STAGEDIR=${BUILDROOT}/stage
OBJECTDIR=${BUILDROOT}/obj
DISTDIR=${BUILDROOT}/dist

if [ "${GOOS}" == "windows" ]; then
    PROM_EXE="${PACKAGE}.exe"
    PROM_STAGEDIR="${STAGEDIR}"
    PROM_DISTCMD="7za a -y -mx=9 -m0=lzma -mfb=128 -md=64m -ms=on"
    PROM_DISTEXT=".7z"
elif [ "${GOOS}" == "darwin" ]; then
    PROM_EXE="${PACKAGE}"
    PROM_STAGEDIR="${STAGEDIR}"
    PROM_DISTCMD="env BZIP=-9 tar cvjpf"
    PROM_DISTEXT=".tar.bz2"
elif [ "${GOARCH:0:3}" == "arm" ]; then
    PROM_EXE="${PACKAGE}"
    PROM_STAGEDIR="${STAGEDIR}"
    PROM_DISTCMD="env BZIP=-9 tar cvjpf"
    PROM_DISTEXT=".tar.bz2"
elif [ "${GOARCH:0:4}" == "mips" ]; then
    PROM_EXE="${PACKAGE}"
    PROM_STAGEDIR="${STAGEDIR}"
    PROM_DISTCMD="env GZIP=-9 tar cvzpf"
    PROM_DISTEXT=".tar.gz"
else
    PROM_EXE="${PACKAGE}"
    PROM_STAGEDIR="${STAGEDIR}/${PACKAGE}"
    PROM_DISTCMD="env XZ_OPT=-9 tar cvJpf"
    PROM_DISTEXT=".tar.xz"
fi

PROM_DIST=${DISTDIR}/${PACKAGE}_${GOOS}_${GOARCH}-r${REVSION}${PROM_DISTEXT}
if [ "${CGO_ENABLED}" = "1" ]; then
    PROM_DIST=${DISTDIR}/${PACKAGE}_${GOOS}_${GOARCH}_cgo-r${REVSION}${PROM_DISTEXT}
fi

PROM_GUI_EXE=${REPO}/assets/taskbar/${GOARCH}/promgui.exe
if [ ! -f "${PROM_GUI_EXE}" ]; then
    PROM_GUI_EXE=${REPO}/assets/packaging/promgui.exe
fi

OBJECTS=${OBJECTDIR}/${PROM_EXE}

SOURCES="${REPO}/README.md \
        ${REPO}/assets/packaging/gae.user.json.example \
        ${REPO}/httpproxy/filters/auth/auth.json \
        ${REPO}/httpproxy/filters/autoproxy/17monipdb.dat \
        ${REPO}/httpproxy/filters/autoproxy/autoproxy.json \
        ${REPO}/httpproxy/filters/autoproxy/gfwlist.txt \
        ${REPO}/httpproxy/filters/autoproxy/ip.html \
        ${REPO}/httpproxy/filters/autorange/autorange.json \
        ${REPO}/httpproxy/filters/direct/direct.json \
        ${REPO}/httpproxy/filters/gae/gae.json \
        ${REPO}/httpproxy/filters/php/php.json \
        ${REPO}/httpproxy/filters/rewrite/rewrite.json \
        ${REPO}/httpproxy/filters/stripssl/stripssl.json \
        ${REPO}/httpproxy/httpproxy.json"

if [ "${GOOS}" = "windows" ]; then
    SOURCES="${SOURCES} \
             ${PROM_GUI_EXE} \
             ${REPO}/assets/packaging/addto-startup.vbs \
             ${REPO}/assets/packaging/get-latest-prom.cmd"
elif [ "${GOOS}_${GOARCH}_${CGO_ENABLED}" = "linux_arm_0" ]; then
    SOURCES="${SOURCES} \
             ${REPO}/assets/packaging/prom.sh \
             ${REPO}/assets/packaging/get-latest-prom.sh"
    GOARM=${GORAM:-5}
elif [ "${GOOS}_${GOARCH}_${CGO_ENABLED}" = "linux_arm_1" ]; then
    SOURCES="${SOURCES} \
             ${REPO}/assets/packaging/prom.sh \
             ${REPO}/assets/packaging/get-latest-prom.sh"
    CC=${ARM_CC:-arm-linux-gnueabihf-gcc}
    GOARM=${GORAM:-5}
elif [ "${GOOS}" = "darwin" ]; then
    SOURCES="${SOURCES} \
             ${REPO}/assets/packaging/promgui.command \
             ${REPO}/assets/packaging/get-latest-prom.sh"
else
    SOURCES="${SOURCES} \
             ${REPO}/assets/packaging/get-latest-prom.sh \
             ${REPO}/assets/packaging/promgui.desktop \
             ${REPO}/assets/packaging/promgui.png \
             ${REPO}/assets/packaging/promgui.py \
             ${REPO}/assets/packaging/prom.sh"
fi

build () {
    mkdir -p ${OBJECTDIR}
    env GOOS=${GOOS} \
        GOARCH=${GOARCH} \
        GOARM=${GOARM} \
        CGO_ENABLED=${CGO_ENABLED} \
        CC=${CC} \
    go build -v -ldflags="${LDFLAGS}" -o ${OBJECTDIR}/${PROM_EXE} .
}

dist () {
    mkdir -p ${DISTDIR} ${STAGEDIR} ${PROM_STAGEDIR}
    cp ${OBJECTS} ${SOURCES} ${PROM_STAGEDIR}

    pushd ${STAGEDIR}
    ${PROM_DISTCMD} ${PROM_DIST} *
    popd
}

check () {
    PROM_WAIT_SECONDS=0 ${PROM_STAGEDIR}/${PROM_EXE}
}

clean () {
    rm -rf ${BUILDROOT}
}

case $1 in
    build)
        build
        ;;
    dist)
        dist
        ;;
    check)
        check
        ;;
    clean)
        clean
        ;;
    *)
        build
        dist
        ;;
esac
