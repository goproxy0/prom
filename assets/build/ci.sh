#!/bin/bash -xe

export GITHUB_USER=${GITHUB_USER:-phuslu}
export GITHUB_EMAIL=${GITHUB_EMAIL:-phuslu@hotmail.com}
export GITHUB_REPO=${GITHUB_REPO:-prom}
export GITHUB_CI_REPO=${GITHUB_CI_REPO:-promci}
export GITHUB_CI_BRANCH=${GITHUB_CI_BRANCH:-orphan}
export GITHUB_COMMIT_ID=${TRAVIS_COMMIT:-${COMMIT_ID:-master}}
export SOURCEFORGE_USER=${SOURCEFORGE_USER:-${GITHUB_USER}}
export SOURCEFORGE_REPO=${SOURCEFORGE_REPO:-${GITHUB_REPO}}
export WORKING_DIR=$(pwd)/${GITHUB_REPO}.${RANDOM:-$$}
export GOROOT_BOOTSTRAP=${WORKING_DIR}/goroot_bootstrap
export GOROOT=${WORKING_DIR}/go
export GOPATH=${WORKING_DIR}/gopath
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
export GOTIP_FOLLOW=${GOTIP_FOLLOW:-true}

if [ ${#GITHUB_TOKEN} -eq 0 ]; then
	echo "WARNING: \$GITHUB_TOKEN is not set!"
fi

if [ ${#SOURCEFORGE_PASSWORD} -eq 0 ]; then
	echo "WARNING: \$SOURCEFORGE_PASSWORD is not set!"
fi

if echo "${TRAVIS_BUILD_DIR}" | grep 'travis-runner'; then
	pushd "${TRAVIS_BUILD_DIR}"
	export GITHUB_COMMIT_ID=$(git log -1 --format="%s %b" | grep -oE '[0-9a-z]{40}')
	popd
fi

for CMD in curl awk git tar bzip2 xz 7za gcc sha1sum timeout grep
do
	if ! type -p ${CMD}; then
		echo -e "\e[1;31mtool ${CMD} is not installed, abort.\e[0m"
		exit 1
	fi
done

mkdir -p ${WORKING_DIR}

function rename() {
	for FILENAME in ${@:2}
	do
		local NEWNAME=$(echo ${FILENAME} | sed -r $1)
		if [ "${NEWNAME}" != "${FILENAME}" ]; then
			mv -f ${FILENAME} ${NEWNAME}
		fi
	done
}

function init_github() {
	pushd ${WORKING_DIR}

	git config --global user.name "${GITHUB_USER}"
	git config --global user.email "${GITHUB_EMAIL}"

	if ! grep -q 'machine github.com' ~/.netrc; then
		if [ ${#GITHUB_TOKEN} -gt 0 ]; then
			(set +x; echo "machine github.com login $GITHUB_USER password $GITHUB_TOKEN" >>~/.netrc)
		fi
	fi

	popd
}

function build_go() {
	pushd ${WORKING_DIR}

	curl -k https://storage.googleapis.com/golang/go1.4.3.linux-amd64.tar.gz | tar xz
	mv go goroot_bootstrap

	git clone --branch master https://github.com/phuslu/go
	cd go/src
	if [ "${GOTIP_FOLLOW}" = "true" ]; then
		git remote add -f upstream https://github.com/golang/go
		git rebase upstream/master
	fi
	bash ./make.bash
	grep -q 'machine github.com' ~/.netrc && git push -f origin master

	set +ex
	echo '================================================================================'
	cat /etc/issue
	uname -a
	lscpu
	echo
	go version
	go env
	echo
	env | grep -v GITHUB_TOKEN | grep -v SOURCEFORGE_PASSWORD
	echo '================================================================================'
	set -ex

	popd
}

function build_glog() {
	pushd ${WORKING_DIR}

	git clone https://github.com/phuslu/glog $GOPATH/src/github.com/phuslu/glog
	cd $GOPATH/src/github.com/phuslu/glog
	git remote add -f upstream https://github.com/golang/glog
	git rebase upstream/master
	go build -v
	grep -q 'machine github.com' ~/.netrc && git push -f origin master

	popd
}

function build_http2() {
	pushd ${WORKING_DIR}

	git clone https://github.com/phuslu/net $GOPATH/src/github.com/phuslu/net
	cd $GOPATH/src/github.com/phuslu/net/http2
	git remote add -f upstream https://github.com/golang/net
	git rebase upstream/master
	go get -x github.com/phuslu/net/http2
	grep -q 'machine github.com' ~/.netrc && git push -f origin master

	popd
}

function build_bogo() {
	pushd ${WORKING_DIR}

	git clone https://github.com/google/boringssl $GOPATH/src/github.com/google/boringssl
	cd $GOPATH/src/github.com/google/boringssl/ssl/test/runner
	sed -i -E 's#"./(curve25519|poly1305)"#"golang.org/x/crypto/\1"#g' *.go
	sed -i -E 's#"./(ed25519)"#"github.com/google/boringssl/ssl/test/runner/\1"#g' *.go
	sed -i -E 's#"./(internal/edwards25519)"#"github.com/google/boringssl/ssl/test/runner/ed25519/\1"#g' ed25519/*.go
	git commit -m "change imports" -s -a
	go get -x github.com/google/boringssl/ssl/test/runner

	popd
}

function build_quicgo() {
	pushd ${WORKING_DIR}

	git clone https://github.com/phuslu/quic-go $GOPATH/src/github.com/phuslu/quic-go
	cd $GOPATH/src/github.com/phuslu/quic-go
	git remote add -f upstream https://github.com/lucas-clemente/quic-go
	git rebase upstream/master
	go get -v github.com/phuslu/quic-go/h2quic
	grep -q 'machine github.com' ~/.netrc && git push -f origin master

	popd
}

function build_prom() {
	pushd ${WORKING_DIR}

	git clone https://github.com/${GITHUB_USER}/${GITHUB_REPO} ${GITHUB_REPO}
	cd ${GITHUB_REPO}

	if [ ${TRAVIS_PULL_REQUEST:-false} == "false" ]; then
		git cat-file -p ${GITHUB_COMMIT_ID} && git checkout -f ${GITHUB_COMMIT_ID}
	else
		git fetch origin pull/${TRAVIS_PULL_REQUEST}/head:pr
		git checkout -f pr
	fi

	export RELEASE=$(git rev-list --count HEAD)
	export RELEASE_DESCRIPTION=$(git log -1 --oneline --format="r${RELEASE}: [\`%h\`](https://github.com/${GITHUB_USER}/${GITHUB_REPO}/commit/%h) %s")
	if [ -n "${TRAVIS_BUILD_ID}" ]; then
		export RELEASE_DESCRIPTION=$(echo ${RELEASE_DESCRIPTION} | sed -E "s#^(r[0-9]+)#[\1](https://travis-ci.org/${GITHUB_USER}/${GITHUB_REPO}/builds/${TRAVIS_BUILD_ID})#g")
	fi

	if grep -lr $(printf '\r\n') * | grep '.go$' ; then
		echo -e "\e[1;31mPlease run dos2unix for go source files\e[0m"
		exit 1
	fi

	if [ "$(gofmt -l . | tee /dev/tty)" != "" ]; then
		echo -e "\e[1;31mPlease run 'gofmt -s -w .' for go source files\e[0m"
		exit 1
	fi

	awk 'match($1, /"((github\.com|golang\.org|gopkg\.in)\/.+)"/) {if (!seen[$1]++) {gsub("\"", "", $1); print $1}}' $(find . -name "*.go") | xargs -n1 -i go get -u -v {}

	go test -v ./httpproxy/helpers

	pushd ./assets/taskbar
	env GOARCH=amd64 ./make.bash
	env GOARCH=386 ./make.bash
	popd

	cat <<EOF |
GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 ./make.bash
GOOS=freebsd GOARCH=386 CGO_ENABLED=0 ./make.bash
GOOS=freebsd GOARCH=amd64 CGO_ENABLED=0 ./make.bash
GOOS=freebsd GOARCH=arm CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=386 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=arm CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=arm CGO_ENABLED=1 ./make.bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=mips CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=mips64 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=mips64le CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=mipsle CGO_ENABLED=0 ./make.bash
GOOS=windows GOARCH=386 CGO_ENABLED=0 ./make.bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 ./make.bash
EOF
	xargs --max-procs=5 -n1 -i bash -c {}

	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 ./make.bash check

	mkdir -p ${WORKING_DIR}/r${RELEASE}
	cp -r build/*/dist/* ${WORKING_DIR}/r${RELEASE}

	git archive --format=tar --prefix="prom-r${RELEASE}/" HEAD | xz > "${WORKING_DIR}/r${RELEASE}/source.tar.xz"

	cd ${WORKING_DIR}/r${RELEASE}
	rename 's/_darwin_(amd64|386)/_macos_\1/' *
	rename 's/_darwin_(arm64|arm)/_ios_\1/' *

	mkdir -p Prom.app/Contents/{MacOS,Resources}
	tar xvpf prom_macos_amd64-r${RELEASE}.tar.bz2 -C Prom.app/Contents/MacOS/
	cp ${WORKING_DIR}/${GITHUB_REPO}/assets/packaging/promgui.icns Prom.app/Contents/Resources/
	cat <<EOF > Prom.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>CFBundleExecutable</key>
        <string>promgui</string>
        <key>CFBundleGetInfoString</key>
        <string>Prom For macOS</string>
        <key>CFBundleIconFile</key>
        <string>promgui</string>
        <key>CFBundleName</key>
        <string>Prom</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
</dict>
</plist>
EOF
	cat <<EOF > Prom.app/Contents/MacOS/promgui
#!$(head -1 Prom.app/Contents/MacOS/promgui.command | tr -d '()' | awk '{print $1}')
import os
__file__ = os.path.join(os.path.dirname(__file__), 'promgui.command')
exec compile(open(__file__, 'rb').read().split('\n', 1)[1], __file__, 'exec')
EOF
	chmod +x Prom.app/Contents/MacOS/promgui
	export GAE_MACOS_REVSION=$(cd ${WORKING_DIR}/${GITHUB_REPO} && git log --oneline -- assets/packaging/promgui.command | wc -l | xargs)
	sed -i "s/r9999/r${GAE_MACOS_REVSION}/" Prom.app/Contents/MacOS/promgui.command
	BZIP=-9 tar cvjpf prom_macos_app-r${RELEASE}.tar.bz2 Prom.app
	rm -rf Prom.app

	for FILE in prom_windows_*.7z
	do
		cat ${WORKING_DIR}/${GITHUB_REPO}/assets/packaging/7zCon.sfx ${FILE} >${FILE}.exe
		/bin/mv ${FILE}.exe ${FILE}
	done

	ls -lht

	popd
}

function build_promgae() {
	pushd ${WORKING_DIR}/${GITHUB_REPO}

	git checkout -f promgae
	git fetch origin promgae
	git reset --hard origin/promgae
	git clean -dfx .

	for FILE in python27.exe python27.dll python27.zip
	do
		curl -LOJ https://raw.githubusercontent.com/phuslu/pybuild/master/${FILE}
	done

	echo -e '@echo off\n"%~dp0python27.exe" uploader.py || pause' >uploader.bat

	export GAE_RELEASE=$(git rev-list --count HEAD)
	sed -i "s/r9999/r${GAE_RELEASE}/" gae/gae.go
	tar cvJpf ${WORKING_DIR}/r${RELEASE}/promgae-r${GAE_RELEASE}.tar.xz *

	popd
}

function build_promphp() {
	pushd ${WORKING_DIR}/${GITHUB_REPO}

	git checkout -f promphp
	git fetch origin promphp
	git reset --hard origin/promphp
	git clean -dfx .

	export PHP_RELEASE=$(git rev-list --count HEAD)
	sed -i "s/r9999/r${PHP_RELEASE}/" *
	tar cvJpf ${WORKING_DIR}/r${RELEASE}/promphp-r${PHP_RELEASE}.tar.xz *

	popd
}

function build_promphpgo() {
	pushd ${WORKING_DIR}/${GITHUB_REPO}

	git checkout -f promphpgo
	git fetch origin promphpgo
	git reset --hard origin/promphpgo
	git clean -dfx .

	export PHPGO_RELEASE=$(git rev-list --count HEAD)
	sed -i "s/r9999/r${PHPGO_RELEASE}/" *.go
	tar cvJpf ${WORKING_DIR}/r${RELEASE}/promphpgo-r${PHPGO_RELEASE}.tar.xz *

	popd
}

function build_promvps() {
	pushd ${WORKING_DIR}/${GITHUB_REPO}

	git checkout -f promvps
	git fetch origin promvps
	git reset --hard origin/promvps
	git clean -dfx .

	git clone --branch master https://github.com/phuslu/prom $GOPATH/src/github.com/phuslu/prom
	awk 'match($1, /"((github\.com|golang\.org|gopkg\.in)\/.+)"/) {if (!seen[$1]++) {gsub("\"", "", $1); print $1}}' $(find . -name "*.go") | xargs -n1 -i go get -u -v {}

	cat <<EOF |
GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=386 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=arm CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 ./make.bash
GOOS=linux GOARCH=mipsle CGO_ENABLED=0 ./make.bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 ./make.bash
GOOS=windows GOARCH=386 CGO_ENABLED=0 ./make.bash
EOF
	xargs --max-procs=5 -n1 -i bash -c {}

	local files=$(find ./build -type f -name "*.gz" -or -name "*.bz2" -or -name "*.xz" -or -name "*.7z")
	cp ${files} ${WORKING_DIR}/r${RELEASE}

	cd ${WORKING_DIR}/r${RELEASE}
	rename 's/_darwin_(amd64|386)/_macos_\1/' *

	popd
}

function release_github() {
	pushd ${WORKING_DIR}

	RELEASE_TAG=prom
	RELEASE_DESCRIPTION='👀'

	if [ ${#GITHUB_TOKEN} -eq 0 ]; then
		echo -e "\e[1;31m\$GITHUB_TOKEN is not set, abort\e[0m"
		exit 1
	fi

	pushd ${WORKING_DIR}
	local GITHUB_RELEASE_URL=https://github.com/aktau/github-release/releases/download/v0.6.2/linux-amd64-github-release.tar.bz2
	local GITHUB_RELEASE_BIN=$(pwd)/$(curl -L ${GITHUB_RELEASE_URL} | tar xjpv | head -1)
	popd

	rm -rf ${GITHUB_CI_REPO}
	git clone --branch "${GITHUB_CI_BRANCH}" https://github.com/${GITHUB_USER}/${GITHUB_CI_REPO} ${GITHUB_CI_REPO}
	cd ${GITHUB_CI_REPO}

	${GITHUB_RELEASE_BIN} delete --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag ${RELEASE_TAG} || true

	env \
	GIT_AUTHOR_NAME='Travis CI' \
	GIT_COMMITTER_NAME='Travis CI' \
	GIT_AUTHOR_EMAIL='travis.ci.build@gmail.com' \
	GIT_COMMITTER_EMAIL='travis.ci.build@gmail.com' \
	GIT_AUTHOR_DATE='Sat Oct 10 12:57:38 CST 2015' \
	GIT_COMMITTER_DATE='Sat Oct 10 12:57:38 CST 2015' \
	git commit --allow-empty -m " 👀"
	git tag -d ${RELEASE_TAG} || true
	git tag ${RELEASE_TAG}
	git push -f origin ${RELEASE_TAG}

	cd ${WORKING_DIR}/r${RELEASE}/

	for i in $(seq 5)
	do
		if ! ${GITHUB_RELEASE_BIN} release --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag ${RELEASE_TAG} --name "${GITHUB_REPO}" --description "${RELEASE_DESCRIPTION}" ; then
			sleep 3
			${GITHUB_RELEASE_BIN} delete --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag ${RELEASE_TAG} >/dev/null 2>&1 || true
			sleep 3
			continue
		fi

		local allok="true"
		for FILE in *
		do
			if ! timeout -k60 60 ${GITHUB_RELEASE_BIN} upload --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag ${RELEASE_TAG} --name ${FILE} --file ${FILE} ; then
				allok="false"
				break
			fi
		done
		if [ "${allok}" == "true" ]; then
			break
		fi
	done

	local files=$(ls ${WORKING_DIR}/r${RELEASE}/ | wc -l)
	local uploads=$(${GITHUB_RELEASE_BIN} info --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag ${RELEASE_TAG} | grep -- '- artifact: ' | wc -l)
	test ${files} -eq ${uploads}

	popd
}

function release_sourceforge() {
	pushd ${WORKING_DIR}/

	if [ ${#SOURCEFORGE_PASSWORD} -eq 0 ]; then
		echo -e "\e[1;31m\$SOURCEFORGE_PASSWORD is not set, abort\e[0m"
		exit 1
	fi

	set +ex

	for i in $(seq 5)
	do
		echo Uploading r${RELEASE}/* to https://sourceforge.net/projects/prom/files/r${RELEASE}/
		if timeout -k60 60 lftp -u "${SOURCEFORGE_USER},${SOURCEFORGE_PASSWORD}" "sftp://frs.sourceforge.net/home/frs/project/${SOURCEFORGE_REPO}/" -e "set ftp:ssl-allow no; rm -rf r${RELEASE}; mkdir r${RELEASE}; mirror -R r${RELEASE} r${RELEASE}; bye"; then
			break
		fi
	done

	set -ex

	popd
}

function clean() {
	set +ex

	pushd ${WORKING_DIR}/r${RELEASE}/
	ls -lht
	echo
	echo 'sha1sum *'
	sha1sum * | xargs -n1 -i echo -e "\e[1;32m{}\e[0m"
	popd >/dev/null
	rm -rf ${WORKING_DIR}

	set -ex
}

init_github
build_go
build_glog
build_http2
build_bogo
build_quicgo
build_prom
if [ "x${TRAVIS_EVENT_TYPE}" == "xpush" ]; then
	build_promgae
	build_promphp
	build_promphpgo
	build_promvps
	release_github
	#release_sourceforge
	clean
fi
