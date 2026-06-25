FROM golang:1.23

WORKDIR /app

# Download Go modules
COPY golang/ .
RUN go mod download

# Build
RUN go build -o hello-world

EXPOSE 8000

# Run
CMD [ "./hello-world" ]
