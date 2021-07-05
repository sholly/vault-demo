FROM centos

RUN yum -y update && yum -y install epel-release && yum -y install jq wget curl unzip

RUN groupadd vault && \
    adduser -g vault vault && \
    mkdir /vault && \
    chown -R vault:vault /vault && \
    chmod -R 777 /vault


WORKDIR /vault

COPY oc-4.6.36-linux.tar.gz /vault 

RUN tar zxvf oc-4.6.36-linux.tar.gz 

RUN wget https://releases.hashicorp.com/vault/1.7.2/vault_1.7.2_linux_amd64.zip && \
    unzip vault_1.7.2_linux_amd64.zip && ls -ltr


ADD getsecrets.sh /vault

USER vault

CMD ["./getsecrets.sh"]
