# Stage 1: Build the Hugo site
FROM ghcr.io/gohugoio/hugo:v0.140.2 AS builder

WORKDIR /src
COPY --chown=hugo:hugo . .
RUN hugo --minify

# Stage 2: Serve the site with NGINX
FROM nginx:alpine
LABEL org.opencontainers.image.source="https://github.com/HZ89/blog"
LABEL org.opencontainers.image.authors="Harrison Zhu(harrison@b1uepi.xyz)"

RUN rm -rf /usr/share/nginx/html/* && chown nginx:nginx /usr/share/nginx/html
COPY --chown=nginx:nginx --from=builder /src/public /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]