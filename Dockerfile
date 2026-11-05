FROM node:24-bookworm-slim AS packages
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

FROM dart:3.13.5 AS engine
WORKDIR /source/engine
COPY engine/ ./
RUN dart pub get && dart compile exe worker.dart -o /source/nfinit-engine

# Keep the Dart runtime/SDK base compatible with its compiled engine. Node is
# copied from the official Node image; no Flutter SDK or image assets are needed.
FROM dart:3.13.5
WORKDIR /app
COPY --from=packages /usr/local/bin/node /usr/local/bin/node
COPY --from=packages /app/node_modules/ ./node_modules/
COPY --from=engine /source/nfinit-engine ./build/nfinit-engine
COPY package.json ./
COPY src/ ./src/
RUN groupadd --gid 10001 nfinit && useradd --uid 10001 --gid nfinit --no-create-home nfinit
USER 10001:10001
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8081 ENGINE_BIN=/app/build/nfinit-engine
EXPOSE 8081
CMD ["node", "src/index.js"]
