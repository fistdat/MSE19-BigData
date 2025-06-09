FROM flink:latest

# Download and install Flink connectors with correct versions
RUN wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/ververica/flink-connector-postgres-cdc/2.4.2/flink-connector-postgres-cdc-2.4.2.jar && \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/apache/flink/flink-connector-jdbc/3.1.0-1.17/flink-connector-jdbc-3.1.0-1.17.jar && \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/postgresql/postgresql/42.6.0/postgresql-42.6.0.jar && \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.17/1.4.3/iceberg-flink-runtime-1.17-1.4.3.jar && \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar && \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.367/aws-java-sdk-bundle-1.12.367.jar

# Set up Flink configuration for Iceberg
COPY flink-conf.yaml /opt/flink/conf/flink-conf.yaml

# Expose necessary ports
EXPOSE 8081 6123 6122 