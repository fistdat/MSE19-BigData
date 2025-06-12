#!/bin/bash
# =============================================================================
# SETUP NESSIE FLINK DEPENDENCIES
# =============================================================================
# This script downloads Nessie-specific dependencies based on Dremio blog
# Reference: https://www.dremio.com/blog/using-flink-with-apache-iceberg-and-nessie/
# =============================================================================

source pipeline_config.env

echo "🗄️ SETTING UP NESSIE FLINK DEPENDENCIES"
echo "========================================"

# Flink and dependency versions for Nessie compatibility
FLINK_VERSION="1.18"
ICEBERG_VERSION="1.4.3"
AWS_SDK_VERSION="1.12.565"
HADOOP_VERSION="3.4.1"

# Maven Central URLs
MAVEN_BASE="https://repo1.maven.org/maven2"

# Required JARs for Nessie catalog support
declare -A NESSIE_JARS=(
    ["iceberg-nessie-${ICEBERG_VERSION}.jar"]="org/apache/iceberg/iceberg-nessie/${ICEBERG_VERSION}/iceberg-nessie-${ICEBERG_VERSION}.jar"
    ["aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"]="com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"
    ["iceberg-aws-${ICEBERG_VERSION}.jar"]="org/apache/iceberg/iceberg-aws/${ICEBERG_VERSION}/iceberg-aws-${ICEBERG_VERSION}.jar"
)

# Create temporary directory for downloads  
TEMP_DIR="/tmp/nessie_jars"
mkdir -p ${TEMP_DIR}

echo "📋 Checking current Flink JARs for Nessie support..."
echo "Current Nessie-related JARs in Flink:"
docker exec ${CONTAINER_FLINK_JM} ls -la /opt/flink/lib/ | grep -E "(nessie|aws-java-sdk)" || echo "No Nessie JARs found"

echo ""
echo "🔍 Analyzing missing Nessie dependencies..."

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
echo "🚀 Starting Nessie JAR installation process..."
echo ""

DOWNLOAD_COUNT=0
INSTALL_COUNT=0
FAILED_COUNT=0

for jar_name in "${!NESSIE_JARS[@]}"; do
    echo "Processing ${jar_name}..."
    
    if check_jar_exists "${jar_name}"; then
        echo "✅ ${jar_name} already exists, skipping"
        continue
    fi
    
    maven_path="${NESSIE_JARS[$jar_name]}"
    
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

echo "📊 NESSIE DEPENDENCIES INSTALLATION SUMMARY"
echo "==========================================="
echo "Downloaded: ${DOWNLOAD_COUNT} JARs"
echo "Installed: ${INSTALL_COUNT} JARs"  
echo "Failed: ${FAILED_COUNT} JARs"

if [ $INSTALL_COUNT -gt 0 ]; then
    echo ""
    echo "🔄 Restarting Flink services to load new Nessie JARs..."
    
    # Restart Flink containers
    docker restart ${CONTAINER_FLINK_JM} ${CONTAINER_FLINK_TM}
    
    echo "⏳ Waiting for Flink services to start..."
    sleep 20
    
    # Verify Flink is running
    if curl -s ${FLINK_JOBMANAGER_URL}/overview > /dev/null 2>&1; then
        echo "✅ Flink services restarted successfully"
        
        echo ""
        echo "📋 Updated JAR list:"
        docker exec ${CONTAINER_FLINK_JM} ls -la /opt/flink/lib/ | grep -E "(nessie|aws-java-sdk|iceberg)"
        
        echo ""
        echo "🧪 Testing Flink SQL Client connectivity..."
        if docker exec ${CONTAINER_FLINK_JM} /opt/flink/bin/sql-client.sh -e "SHOW CATALOGS;" > /dev/null 2>&1; then
            echo "✅ Flink SQL Client is working"
        else
            echo "⚠️  Flink SQL Client test failed, but services are running"
        fi
        
    else
        echo "❌ Flink services failed to start properly"
        echo "   Check logs: docker logs ${CONTAINER_FLINK_JM}"
    fi
else
    echo "❌ No Nessie JARs were installed successfully"
fi

# Cleanup
echo ""
echo "🧹 Cleaning up temporary files..."
rm -rf ${TEMP_DIR}

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
if [ $INSTALL_COUNT -gt 0 ]; then
    echo "1. ✅ Nessie dependencies installed successfully"
    echo "2. 🧪 Test Nessie catalog connectivity"
    echo "3. 🔧 Configure catalog with catalog-impl parameter"
    echo "4. 🚀 Create Nessie-backed Iceberg tables"
    echo "5. 🔍 Monitor Git-like versioning features"
else
    echo "1. ❌ Nessie dependency installation failed"
    echo "2. 🔍 Check Flink logs for errors"
    echo "3. 🔄 Try manual JAR installation"
    echo "4. 📞 Consider network connectivity issues"
fi

echo ""
echo "🏁 Nessie Flink Dependencies Setup Complete!" 