# Этап 1: Сборка бинарника
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Установка корневых сертификатов для исходящих HTTPS-запросов к OSRM
RUN apk add --no-cache ca-certificates git

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/server cmd/api/main.go

# Этап 2: Минимальный рабочий контейнер
FROM alpine:3.19

WORKDIR /app
RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /app/server /app/server

EXPOSE 8000

CMD ["/app/server"]