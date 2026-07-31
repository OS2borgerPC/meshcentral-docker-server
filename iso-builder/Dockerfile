FROM fedora-minimal:42

RUN microdnf install -y \
        butane \
        coreos-installer \
        jq \
    && microdnf clean all

COPY watcher.sh /usr/local/bin/watcher.sh
RUN chmod +x /usr/local/bin/watcher.sh

CMD ["/usr/local/bin/watcher.sh"]
