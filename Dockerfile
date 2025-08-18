# syntax=docker/dockerfile:1
FROM golang:1.22 AS build
WORKDIR /src
COPY app/go.mod ./
RUN go mod download
COPY app/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /bin/app

FROM alpine:3.20
RUN adduser -D -H -u 10001 appuser
USER 10001
EXPOSE 8080
ENV PORT=8080
COPY --from=build /bin/app /app
ENTRYPOINT ["/app"]
