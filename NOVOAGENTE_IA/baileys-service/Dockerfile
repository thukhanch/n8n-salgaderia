FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY index.js ./
VOLUME ["/app/auth"]
ENV AUTH_DIR=/app/auth
EXPOSE 3001
CMD ["node", "index.js"]
