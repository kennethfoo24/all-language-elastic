package com.example.springboot;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import static net.logstash.logback.argument.StructuredArguments.kv;

@RestController
public class HelloController {

    private static final Logger log = LoggerFactory.getLogger("java");
    private static final String UPSTREAM = "golang";

    @Value("${GOLANG_SERVICE_URL}")
    private String golangServiceUrl;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper mapper = new ObjectMapper();

    @GetMapping("/java")
    public ResponseEntity<Map<String, Object>> callService(HttpServletRequest request) {
        long start = System.currentTimeMillis();
        log.info("request received", kv("method", request.getMethod()), kv("path", request.getRequestURI()));

        String url = golangServiceUrl + "/golang";
        try {
            log.info("calling upstream", kv("upstream", UPSTREAM));
            ResponseEntity<String> resp = restTemplate.getForEntity(url, String.class);
            log.info("upstream responded", kv("upstream", UPSTREAM), kv("status_code", resp.getStatusCode().value()));

            JsonNode upstream = mapper.readTree(resp.getBody());

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("service", "java");
            body.put("message", "Hello from java");
            body.put("status", "ok");
            body.put("timestamp", Instant.now().toString());
            body.put("upstream", upstream);

            log.info("request completed",
                    kv("method", request.getMethod()), kv("path", request.getRequestURI()),
                    kv("status_code", 200), kv("duration_ms", System.currentTimeMillis() - start));
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            log.error("upstream call failed", kv("upstream", UPSTREAM), kv("error", e.getMessage()));

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("service", "java");
            body.put("message", "Hello from java");
            body.put("status", "error");
            body.put("timestamp", Instant.now().toString());
            body.put("upstream", null);
            body.put("error", e.getMessage());

            log.info("request completed",
                    kv("method", request.getMethod()), kv("path", request.getRequestURI()),
                    kv("status_code", 502), kv("duration_ms", System.currentTimeMillis() - start));
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(body);
        }
    }
}
