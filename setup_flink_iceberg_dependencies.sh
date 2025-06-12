#!/bin/bash
# =============================================================================
# SETUP FLINK ICEBERG DEPENDENCIES
# =============================================================================
# This script downloads and installs Iceberg dependencies for Flink 1.18.1
# Similar approach to the successful Kafka dependencies fix
# =============================================================================

source pipeline_config.env

echo "🧊 SETTING UP FLINK ICEBERG DEPENDENCIES"
echo "========================================"

# Flink and Iceberg versions
FLINK_VERSION="1.18.1"
ICEBERG_VERSION="1.4.3"
HADOOP_VERSION="3.4.1"
AWS_SDK_VERSION="1.12.565"

# Maven Central URLs
MAVEN_BASE="https://repo1.maven.org/maven2"

# Required JARs with their Maven coordinates
declare -A ICEBERG_JARS=(
    ["flink-iceberg-${FLINK_VERSION}.jar"]="org/apache/iceberg/iceberg-flink-runtime-${FLINK_VERSION}/${ICEBERG_VERSION}/iceberg-flink-runtime-${FLINK_VERSION}-${ICEBERG_VERSION}.jar"
    ["iceberg-core-${ICEBERG_VERSION}.jar"]="org/apache/iceberg/iceberg-core/${ICEBERG_VERSION}/iceberg-core-${ICEBERG_VERSION}.jar"
    ["iceberg-aws-${ICEBERG_VERSION}.jar"]="org/apache/iceberg/iceberg-aws/${ICEBERG_VERSION}/iceberg-aws-${ICEBERG_VERSION}.jar"
    ["iceberg-nessie-${ICEBERG_VERSION}.jar"]="org/apache/iceberg/iceberg-nessie/${ICEBERG_VERSION}/iceberg-nessie-${ICEBERG_VERSION}.jar"
    ["hadoop-aws-${HADOOP_VERSION}.jar"]="org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar"
    ["aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"]="com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"
)

# Create temporary directory for downloads
TEMP_DIR="/tmp/iceberg_jars"
mkdir -p ${TEMP_DIR}

echo "📋 Checking current Flink JARs..."
echo "Current Iceberg-related JARs in Flink:"
docker exec ${CONTAINER_FLINK_JM} ls -la /opt/flink/lib/ | grep -E "(iceberg|aws|hadoop)" || echo "No Iceberg JARs found"

echo ""
echo "🔍 Analyzing missing Iceberg dependencies..."

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
echo "🚀 Starting Iceberg JAR installation process..."
echo ""

DOWNLOAD_COUNT=0
INSTALL_COUNT=0
FAILED_COUNT=0

for jar_name in "${!ICEBERG_JARS[@]}"; do
    echo "Processing ${jar_name}..."
    
    if check_jar_exists "${jar_name}"; then
        echo "✅ ${jar_name} already exists, skipping"
        continue
    fi
    
    maven_path="${ICEBERG_JARS[$jar_name]}"
    
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

# Alternative: Download core Iceberg JARs only if full installation fails
if [ $INSTALL_COUNT -eq 0 ]; then
    echo "🔄 Trying alternative approach - downloading core Iceberg JARs only..."
    
    CORE_JARS=(
        "iceberg-flink-runtime-${FLINK_VERSION}-${ICEBERG_VERSION}.jar:org/apache/iceberg/iceberg-flink-runtime-${FLINK_VERSION}/${ICEBERG_VERSION}/iceberg-flink-runtime-${FLINK_VERSION}-${ICEBERG_VERSION}.jar"
        "hadoop-aws-${HADOOP_VERSION}.jar:org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar"
    )
    
    for jar_info in "${CORE_JARS[@]}"; do
        IFS=':' read -r jar_name maven_path <<< "$jar_info"
        download_url="${MAVEN_BASE}/${maven_path}"
        
        if curl -L -o "${TEMP_DIR}/${jar_name}" "${download_url}"; then
            echo "✅ Downloaded ${jar_name}"
            
            if docker cp "${TEMP_DIR}/${jar_name}" "${CONTAINER_FLINK_JM}:/opt/flink/lib/${jar_name}" && \
               docker cp "${TEMP_DIR}/${jar_name}" "${CONTAINER_FLINK_TM}:/opt/flink/lib/${jar_name}"; then
                echo "✅ Installed ${jar_name}"
                INSTALL_COUNT=$((INSTALL_COUNT + 1))
            fi
        fi
    done
fi

echo "📊 INSTALLATION SUMMARY"
echo "======================="
echo "Downloaded: ${DOWNLOAD_COUNT} JARs"
echo "Installed: ${INSTALL_COUNT} JARs"
echo "Failed: ${FAILED_COUNT} JARs"

if [ $INSTALL_COUNT -gt 0 ]; then
    echo ""
    echo "🔄 Restarting Flink services to load new Iceberg JARs..."
    
    # Restart Flink containers
    docker restart ${CONTAINER_FLINK_JM} ${CONTAINER_FLINK_TM}
    
    echo "⏳ Waiting for Flink services to start..."
    sleep 20
    
    # Verify Flink is running
    if curl -s ${FLINK_JOBMANAGER_URL}/overview > /dev/null 2>&1; then
        echo "✅ Flink services restarted successfully"
        
        echo ""
        echo "📋 Updated JAR list:"
        docker exec ${CONTAINER_FLINK_JM} ls -la /opt/flink/lib/ | grep -E "(iceberg|aws|hadoop)"
        
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
    echo "❌ No Iceberg JARs were installed successfully"
fi

# Cleanup
echo ""
echo "🧹 Cleaning up temporary files..."
rm -rf ${TEMP_DIR}

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
if [ $INSTALL_COUNT -gt 0 ]; then
    echo "1. ✅ Iceberg dependencies installed successfully"
    echo "2. 🧪 Test Nessie catalog connectivity"
    echo "3. 🔧 Configure S3A properties for MinIO"
    echo "4. 🚀 Create Iceberg sink Flink job"
    echo "5. 🔍 Monitor lakehouse data ingestion"
else
    echo "1. ❌ Iceberg dependency installation failed"
    echo "2. 🔍 Check Flink logs for errors"
    echo "3. 🔄 Try manual JAR installation"
    echo "4. 📞 Consider alternative Iceberg setup approach"
fi

echo ""
echo "🏁 Flink Iceberg Dependencies Setup Complete!" 