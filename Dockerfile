# This file describes the standard way to build Docker, using docker
#
# Usage:
#
# # Assemble the full dev environment. This is slow the first time.
# docker build -t docker .
# # Apparmor messes with privileged mode: disable it
# /etc/init.d/apparmor stop ; /etc/init.d/apparmor teardown
#
# # Mount your source in an interactive container for quick testing:
# docker run -v `pwd`:/go/src/github.com/dotcloud/docker -privileged -lxc-conf=lxc.aa_profile=unconfined -i -t docker bash
#
#
# # Run the test suite:
# docker run -privileged -lxc-conf=lxc.aa_profile=unconfined docker go test -v
#
# # Publish a release:
# docker run -privileged -lxc-conf=lxc.aa_profile=unconfined \
#  -e AWS_S3_BUCKET=baz \
#  -e AWS_ACCESS_KEY=foo \
#  -e AWS_SECRET_KEY=bar \
#  -e GPG_PASSPHRASE=gloubiboulga \
#  docker hack/release.sh
#

docker-version 0.6.1
from    ubuntu:12.10
maintainer      Solomon Hykes <solomon@dotcloud.com>

# Build dependencies
run     apt-get update
run     apt-get install -y -q curl
run     apt-get install -y -q git
run     apt-get install -y -q mercurial
run     apt-get install -y -q build-essential

# Install Go from source (for eventual cross-compiling)
run     curl -s https://go.googlecode.com/files/go1.2rc1.src.tar.gz | tar -v -C / -xz && mv /go /goroot
run     cd /goroot/src && ./make.bash
env     GOROOT  /goroot
env     PATH    $PATH:/goroot/bin
env     GOPATH  /go:/go/src/github.com/dotcloud/docker/vendor

# Create Go cache with tag netgo (for static compilation of Go while preserving CGO support)
run     go install -ldflags '-w -linkmode external -extldflags "-static -Wl,--unresolved-symbols=ignore-in-shared-libs"' -tags netgo -a std

# Get lvm2 source for compiling statically
run     git clone git://git.fedorahosted.org/git/lvm2.git /lvm2
run     cd /lvm2 && git checkout v2_02_102

# can't use git clone -b because it's not supported by git versions before 1.7.10
run	cd /lvm2 && ./configure --enable-static_link && make && make install_device-mapper
# see https://git.fedorahosted.org/cgit/lvm2.git/refs/tags for release tags

# Ubuntu stuff
run     apt-get install -y -q ruby1.9.3 rubygems libffi-dev
run     gem install --no-rdoc --no-ri fpm
run     apt-get install -y -q reprepro dpkg-sig

# Install s3cmd 1.0.1 (earlier versions don't support env variables in the config)
run     apt-get install -y -q python-pip
run     pip install s3cmd
run     pip install python-magic
run     /bin/echo -e '[default]\naccess_key=$AWS_ACCESS_KEY\nsecret_key=$AWS_SECRET_KEY\n' > /.s3cfg

# Runtime dependencies
run     apt-get install -y -q iptables
run     dpkg-divert --local --rename --add /sbin/initctl && \
        ln -s /bin/true /sbin/initctl && \
        apt-get install -y -q lxc

volume  /var/lib/docker
workdir /go/src/github.com/dotcloud/docker

# Wrap all commands in the "docker-in-docker" script to allow nested containers
entrypoint ["hack/dind"]

# Upload docker source
add     .		/go/src/github.com/dotcloud/docker

