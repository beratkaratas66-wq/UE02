# --- Stage 1: Build ---
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Wir kopieren die Mod-Dateien explizit aus dem src-Ordner
COPY src/go.mod src/go.sum ./
RUN go mod download

# Den restlichen Quellcode aus src kopieren
COPY src/ .

# Statisch gelinktes Binary bauen 
RUN CGO_ENABLED=0 GOOS=linux go build -o /recipe-api main.go

# --- Stage 2: Final Runtime ---
# Distroless für minimale Angriffsfläche (keine Shell, keine Tools)
FROM gcr.io/distroless/static-debian12:latest

# Als Non-Root User ausführen (Sicherheits-Best-Practice)
USER 65532:65532

COPY --from=builder /recipe-api /recipe-api

EXPOSE 8080

ENTRYPOINT ["/recipe-api"]
CMD ["serve"]
