#!/bin/bash
# =============================================================================
# FIX FLINK KAFKA DEPENDENCIES
# =============================================================================
# This script downloads and installs missing Kafka JARs for Flink 1.18.1
# =============================================================================

source pipeline_config.env

echo "🔧 FIXING FLINK KAFKA DEPENDENCIES"
echo "=================================="

# Flink and Kafka versions
FLINK_VERSION="1.18.1"
KAFKA_VERSION="3.5.0"
SCALA_VERSION="2.12"

# Maven Central URLs
MAVEN_BASE="https://repo1.maven.org/maven2"

# Required JARs with their Maven coordinates
declare -A REQUIRED_JARS=(
    ["kafka-clients-${KAFKA_VERSION}.jar"]="org/apache/kafka/kafka-clients/${KAFKA_VERSION}/kafka-clients-${KAFKA_VERSION}.jar"
    ["kafka_${SCALA_VERSION}-${KAFKA_VERSION}.jar"]="org/apache/kafka/kafka_${SCALA_VERSION}/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.jar"
)

# Create temporary directory for downloads
TEMP_DIR="/tmp/flink_jars"
mkdir -p ${TEMP_DIR}

echo "📋 Checking current Flink JARs..."
echo "Current Kafka-related JARs in Flink:"
docker exec ${CONTAINER_FLINK_JM} ls -la /opt/flink/lib/ | grep -E "(kafka|json)" || echo "No Kafka JARs found"

echo ""
echo "🔍 Analyzing missing dependencies..."

# Function to check if JAR exists in Flink
check_jar_exists() {
    local jar_name=$1
    docker exec ${CONTAINER_FLINK_JM} ls /opt/flink/lib/${jar_name} > /dev/null 2>&1
    return $?
}

# Function to download JAR
download_jar() {
    local jar_name=$1
    local maven_path=$2
    local download_url="${MAVEN_BASE}/${maven_path}"
    
    echo "📥 Downloading ${jar_name}..."
    echo "   URL: ${download_url}"
    
    if curl -L -o "${TEMP_DIR}/${jar_name}" "${download_url}"; then
        echo "✅ Downloaded ${jar_name}"
        return 0
    else
        echo "❌ Failed to download ${jar_name}"
        return 1
    fi
}

# Function to install JAR to Flink
install_jar() {
    local jar_name=$1
    
    echo "📦 Installing ${jar_name} to Flink..."
    
    # Copy JAR to both JobManager and TaskManager
    if docker cp "${TEMP_DIR}/${jar_name}" "${CONTAINER_FLINK_JM}:/opt/flink/lib/${jar_name}" && \
       docker cp "${TEMP_DIR}/${jar_name}" "${CONTAINER_FLINK_TM}:/opt/flink/lib/${jar_name}"; then
        echo "✅ Installed ${jar_name}"
        return 0
    else
        echo "❌ Failed to install ${jar_name}"
        return 1
    fi
}

# Main installation process
echo "🚀 Starting JAR installation process..."
echo ""

DOWNLOAD_COUNT=0
INSTALL_COUNT=0
FAILED_COUNT=0

for jar_name in "${!REQUIRED_JARS[@]}"; do
    echo "Processing ${jar_name}..."
    
    if check_jar_exists "${jar_name}"; then
        echo "✅ ${jar_name} already exists, skipping"
        continue
    fi
    
    maven_path="${REQUIRED_JARS[$jar_name]}"
    
    if download_jar "${jar_name}" "${maven_path}"; then
        DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
        
        if install_jar "${jar_name}"; then
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    echo ""
done

# Alternative: Download kafka-clients only (most critical)
if [ $INSTALL_COUNT -eq 0 ]; then
    echo "🔄 Trying alternative approach - downloading kafka-clients only..."
    
    KAFKA_CLIENTS_JAR="kafka-clients-${KAFKA_VERSION}.jar"
    KAFKA_CLIENTS_URL="${MAVEN_BASE}/org/apache/kafka/kafka-clients/${KAFKA_VERSION}/${KAFKA_CLIENTS_JAR}"
    
    if curl -L -o "${TEMP_DIR}/${KAFKA_CLIENTS_JAR}" "${KAFKA_CLIENTS_URL}"; then
        echo "✅ Downloaded ${KAFKA_CLIENTS_JAR}"
        
        if docker cp "${TEMP_DIR}/${KAFKA_CLIENTS_JAR}" "${CONTAINER_FLINK_JM}:/opt/flink/lib/${KAFKA_CLIENTS_JAR}" && \
           docker cp "${TEMP_DIR}/${KAFKA_CLIENTS_JAR}" "${CONTAINER_FLINK_TM}:/opt/flink/lib/${KAFKA_CLIENTS_JAR}"; then
            echo "✅ Installed ${KAFKA_CLIENTS_JAR}"
            INSTALL_COUNT=1
        fi
    fi
fi

echo "📊 INSTALLATION SUMMARY"
echo "======================="
echo "Downloaded: ${DOWNLOAD_COUNT} JARs"
echo "Installed: ${INSTALL_COUNT} JARs"
echo "Failed: ${FAILED_COUNT} JARs"

if [ $INSTALL_COUNT -gt 0 ]; then
    echo ""
    echo "🔄 Restarting Flink services to load new JARs..."
    
    # Restart Flink containers
    docker restart ${CONTAINER_FLINK_JM} ${CONTAINER_FLINK_TM}
    
    echo "⏳ Waiting for Flink services to start..."
    sleep 15
    
    # Verify Flink is running
    if curl -s ${FLINK_JOBMANAGER_URL}/overview > /dev/null 2>&1; then
        echo "✅ Flink services restarted successfully"
        
        echo ""
        echo "📋 Updated JAR list:"
        docker exec ${CONTAINER_FLINK_JM} ls -la /opt/flink/lib/ | grep -E "(kafka|json)"
        
        echo ""
        echo "🧪 Testing Flink SQL Client connectivity..."
        if docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -e "SHOW TABLES;" > /dev/null 2>&1; then
            echo "✅ Flink SQL Client is working"
        else
            echo "⚠️  Flink SQL Client test failed, but services are running"
        fi
        
    else
        echo "❌ Flink services failed to start properly"
        echo "   Check logs: docker logs ${CONTAINER_FLINK_JM}"
    fi
else
    echo "❌ No JARs were installed successfully"
fi

# Cleanup
echo ""
echo "🧹 Cleaning up temporary files..."
rm -rf ${TEMP_DIR}

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
if [ $INSTALL_COUNT -gt 0 ]; then
    echo "1. ✅ Dependencies installed successfully"
    echo "2. 🧪 Test Flink job submission with: ./test_flink_kafka_job.sh"
    echo "3. 🔍 Monitor job execution in Flink Web UI: ${FLINK_JOBMANAGER_URL}"
else
    echo "1. ❌ Dependency installation failed"
    echo "2. 🔍 Check Flink logs for errors"
    echo "3. 🔄 Try manual JAR installation or alternative approach"
fi

echo ""
echo "🏁 Flink Kafka Dependencies Fix Complete!" 