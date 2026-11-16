# Build the jar. Tests are run by CI, not here: they need SWI-Prolog.
FROM eclipse-temurin:25-jdk AS build
WORKDIR /src
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline
COPY src src
RUN ./mvnw -B -q -DskipTests package && cp target/seplans2-*.jar /app.jar

# Run it: a Java runtime plus SWI-Prolog, as an unprivileged user.
FROM eclipse-temurin:25-jre
RUN apt-get update \
    && apt-get install -y --no-install-recommends swi-prolog-nox \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home seplans
USER seplans
WORKDIR /home/seplans
COPY --from=build /app.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
