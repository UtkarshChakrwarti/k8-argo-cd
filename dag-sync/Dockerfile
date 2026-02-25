FROM alpine:3.19

# Install rsync and inotify-tools for watching file changes
RUN apk add --no-cache rsync inotify-tools bash

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Source: mounted hostPath from Kind node (local dags/ folder)
# Dest  : mounted emptyDir shared with Airflow containers
ENV SRC_DIR=/dags-source
ENV DEST_DIR=/dags-dest
ENV SYNC_INTERVAL=10

ENTRYPOINT ["/entrypoint.sh"]
