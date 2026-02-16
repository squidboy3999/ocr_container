# Speed up dnf a bit, then install tools:
# - ocrmypdf + deps (qpdf, ghostscript, unpaper, pngquant) 
# - tesseract + English pack
# - inotify-tools for event-based watching, parallel for future expansion
# - tini for sane PID 1
RUN dnf -y update && \
    dnf -y install \
      ocrmypdf \
      tesseract \
      tesseract-langpack-eng \
      tesseract-osd \
      qpdf ghostscript unpaper pngquant \
      inotify-tools parallel \
      tini \
      which findutils coreutils \
    && dnf clean all


# Create service user & directories
#RUN useradd -m -u 10001 ocr && \
#    mkdir -p /data/in /data/out /data/done /data/fail && \
#    chown -R ocr:ocr /data

# Add watcher script
COPY watcher.sh /usr/local/bin/watcher.sh
RUN chmod +x /usr/local/bin/watcher.sh

#USER ocr
WORKDIR /data

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/watcher.sh"]
