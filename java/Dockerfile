FROM openjdk:17-jdk-slim
WORKDIR /app

# Copy the JAR produced by the *previous* Maven step
COPY java/app/target/spring-boot-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
