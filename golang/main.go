package main

import (
    "encoding/json"
    "log/slog"
    "net/http"
    "os"
    "strings"
    "time"
)

const upstreamName = "dotnet"

// logger emits standardized JSON: timestamp, level, service, message + extra fields.
var logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
        switch a.Key {
        case slog.TimeKey:
            a.Key = "timestamp"
        case slog.MessageKey:
            a.Key = "message"
        case slog.LevelKey:
            a.Key = "level"
            a.Value = slog.StringValue(strings.ToLower(a.Value.String()))
        }
        return a
    },
})).With("service", "golang")

// helloService handles /golang: greet + call the dotnet service, embedding its
// JSON response as a nested object in the envelope.
func helloService(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    logger.Info("request received", "method", r.Method, "path", r.URL.Path)

    dotnetURL := os.Getenv("DOTNET_SERVICE_URL")
    if dotnetURL == "" {
        dotnetURL = "http://localhost:4567"
    }

    client := &http.Client{Timeout: 3 * time.Second}
    logger.Info("calling upstream", "upstream", upstreamName)
    resp, err := client.Get(dotnetURL + "/dotnet")
    if err != nil {
        writeError(w, r, start, err.Error())
        return
    }
    defer resp.Body.Close()

    if resp.StatusCode >= 400 {
        writeError(w, r, start, "upstream returned status "+resp.Status)
        return
    }

    var upstream interface{}
    if err := json.NewDecoder(resp.Body).Decode(&upstream); err != nil {
        writeError(w, r, start, "failed to decode upstream JSON: "+err.Error())
        return
    }
    logger.Info("upstream responded", "upstream", upstreamName, "status_code", resp.StatusCode)

    body := map[string]interface{}{
        "service":   "golang",
        "message":   "Hello from golang",
        "status":    "ok",
        "timestamp": time.Now().UTC().Format(time.RFC3339Nano),
        "upstream":  upstream,
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(body)
    logger.Info("request completed",
        "method", r.Method, "path", r.URL.Path,
        "status_code", 200, "duration_ms", time.Since(start).Milliseconds())
}

func writeError(w http.ResponseWriter, r *http.Request, start time.Time, msg string) {
    logger.Error("upstream call failed", "upstream", upstreamName, "error", msg)
    body := map[string]interface{}{
        "service":   "golang",
        "message":   "Hello from golang",
        "status":    "error",
        "timestamp": time.Now().UTC().Format(time.RFC3339Nano),
        "upstream":  nil,
        "error":     msg,
    }
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusBadGateway)
    json.NewEncoder(w).Encode(body)
    logger.Info("request completed",
        "method", r.Method, "path", r.URL.Path,
        "status_code", 502, "duration_ms", time.Since(start).Milliseconds())
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8000"
    }

    mux := http.NewServeMux()
    mux.HandleFunc("/golang", helloService)

    logger.Info("server started", "port", port)
    if err := http.ListenAndServe(":"+port, mux); err != nil {
        logger.Error("server failed", "error", err.Error())
        os.Exit(1)
    }
}
