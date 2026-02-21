# =============================================================================
# PRATHAMONE ACADEMY OS — FRONTEND DOCKERFILE
# Stage 1: Build
# =============================================================================
FROM node:20-slim AS build

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm install

# Copy source and build
COPY . .
ARG VITE_API_URL
RUN VITE_API_URL=$VITE_API_URL npm run build

# Stage 2: Serve
FROM nginx:stable-alpine

# Copy build artifacts to nginx
COPY --from=build /app/dist /usr/share/nginx/html

# Expose port 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
