# Peepeechess relay: one dependency-free Node file. Build: docker build -t peepeechess-relay tools/relay
# Run:   docker run -p 8080:8080 -e TRUST_PROXY=1 peepeechess-relay   (put wss:// termination in front: PaaS edge, Caddy, nginx)
FROM node:22-alpine
WORKDIR /app
COPY relay.mjs ./relay.mjs
ENV PORT=8080 HOST=0.0.0.0
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "relay.mjs"]
