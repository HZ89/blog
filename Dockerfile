# Stage 1: Build the Hugo site
FROM ghcr.io/gohugoio/hugo:latest AS builder

WORKDIR /src
COPY --chown=hugo:hugo . .
RUN hugo --minify

# Stage 2: Serve the site with NGINX
FROM nginx:alpine
LABEL org.opencontainers.image.source="https://github.com/HZ89/blog"
LABEL org.opencontainers.image.authors="Harrison Zhu(harrison@b1uepi.xyz)"

RUN rm -rf /usr/share/nginx/html/*
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]