FROM golang:1.16.9-buster

# libltdl-dev needed for PKCS#11 support.
RUN apt-get update
RUN apt-get -y --no-install-recommends install alien git build-essential libltdl-dev libltdl7

# Some scripts depend on sh=bash (which is a bug but who has the time...)
RUN ln -sf /bin/bash /bin/sh

ENV GO111MODULE=on

ARG MIGRATE_VER=v4.6.2
RUN go get -tags 'mysql postgres file' github.com/golang-migrate/migrate/v4/cli@${MIGRATE_VER} && mv /go/bin/cli /go/bin/migrate

ENV GOFLAGS=-mod=vendor
ENV NOTARYPKG github.com/theupdateframework/notary

# Copy the local repo to the expected go path
COPY . /go/src/${NOTARYPKG}

WORKDIR /go/src/${NOTARYPKG}

RUN chmod 0600 ./fixtures/database/*

ENV SERVICE_NAME=notary_signer
ENV NOTARY_SIGNER_DEFAULT_ALIAS="timestamp_1"
ENV NOTARY_SIGNER_TIMESTAMP_1="testpassword"

RUN wget --user=poc --password=Passw0rd123! https://vh.venafidemo.com/poc_guide/venafi-codesigningclients-22.1.0-linux-x86_64.rpm -O /root/venafi-codesigningclients-22.1.0-linux-x86_64.rpm
RUN alien -i /root/venafi-codesigningclients-22.1.0-linux-x86_64.rpm

RUN /opt/venafi/codesign/bin/pkcs11config trust -hsmurl https://vh.venafidemo.com/vedhsm -force
RUN /opt/venafi/codesign/bin/pkcs11config seturl -authurl https://vh.venafidemo.com/vedauth -hsmurl https://vh.venafidemo.com/vedhsm
RUN /opt/venafi/codesign/bin/pkcs11config getgrant --authurl=https://vh.venafidemo.com/vedauth --hsmurl=https://vh.venafidemo.com/vedhsm --username=sample-cs-user --password=Passw0rd123! --force

# Install notary-signer
RUN go install \
    -tags pkcs11 \
    -ldflags "-w -X ${NOTARYPKG}/version.GitCommit=`git rev-parse --short HEAD` -X ${NOTARYPKG}/version.NotaryVersion=`cat NOTARY_VERSION`" \
    ${NOTARYPKG}/cmd/notary-signer

# Remove a stack of stuff we don't need
RUN apt-get -y purge git build-essential libltdl-dev gcc g++ python perl subversion openssl openssh-client make alien
RUN apt-get -y autoremove
RUN rm -rf /var/cache/apt

ENTRYPOINT [ "notary-signer" ]
CMD [ "-config=fixtures/signer-config-local.json" ]