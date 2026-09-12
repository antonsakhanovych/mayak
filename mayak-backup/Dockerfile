# rcon-cli is lifted straight from the server image, so its architecture always
# matches the host and there is no version/URL to keep in sync.
FROM itzg/minecraft-server:latest AS mc

FROM alpine:3.20
RUN apk add --no-cache restic ca-certificates tini bash coreutils
COPY --from=mc /usr/local/bin/rcon-cli /usr/local/bin/rcon-cli
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
