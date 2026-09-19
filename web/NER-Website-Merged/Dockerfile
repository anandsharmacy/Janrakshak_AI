# NER officer website: static Vite build served by nginx.
#
#   docker build -t ner-website \
#     --build-arg VITE_SUPABASE_URL=http://192.168.1.20:54321 \
#     --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_... .
#
# Vite bakes VITE_* into the bundle, so the Supabase URL must be one the viewer's
# browser can reach (a LAN IP for other devices). Only the publishable key ever
# goes in here — never the service-role key.
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_PUBLISHABLE_KEY
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL \
    VITE_SUPABASE_PUBLISHABLE_KEY=$VITE_SUPABASE_PUBLISHABLE_KEY
RUN npm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
