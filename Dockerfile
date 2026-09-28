FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

COPY script.sh /usr/local/bin/script.sh

RUN chmod +x /usr/local/bin/script.sh

WORKDIR /root

CMD ["/bin/bash", "-c", "/usr/local/bin/script.sh demo-user && exec python3 -m http.server 8080"]
