#!/bin/bash -e
################################################################################
##  File:  java-tools.sh
##  Desc:  Installs Java and related tooling (Ant, Gradle, Maven)
################################################################################

source $HELPER_SCRIPTS/install.sh
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/etc-environment.sh

JAVA_VERSIONS_LIST=$(get_toolset_value '.java.versions | .[]')
DEFAULT_JDK_VERSION=$(get_toolset_value '.java.default')
JAVA_TOOLCACHE_PATH="$AGENT_TOOLSDIRECTORY/Java_Adopt_jdk"

# Install GPG Key for Adopt Open JDK. See https://adoptopenjdk.net/installation.html
wget -qO - "https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public" | apt-key add -
add-apt-repository --yes https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/

if isUbuntu18 ; then
    # Install GPG Key for Azul Open JDK. See https://www.azul.com/downloads/azure-only/zulu/
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xB1998361219BD9C9
    apt-add-repository "deb https://repos.azul.com/azure-only/zulu/apt stable main"
fi

apt-get update

for JAVA_VERSION in ${JAVA_VERSIONS_LIST[@]}; do
    apt-get -y install adoptopenjdk-$JAVA_VERSION-hotspot=\*
    javaVersionPath="/usr/lib/jvm/adoptopenjdk-${JAVA_VERSION}-hotspot-amd64"
    echo "JAVA_HOME_${JAVA_VERSION}_X64=$javaVersionPath" | tee -a /etc/environment
    fullJavaVersion=$(cat "$javaVersionPath/release" | grep "^SEMANTIC" | cut -d "=" -f 2 | tr -d "\"" | tr "+" "-")

    # If there is no semver in java release, then extract java version from -fullversion
    if [[ -z $fullJavaVersion ]]; then
        fullJavaVersion=$(java -fullversion 2>&1 | tr -d "\"" | tr "+" "-" | awk '{print $4}')
    fi
    
    javaToolcacheVersionPath="$JAVA_TOOLCACHE_PATH/$fullJavaVersion"
    mkdir -p "$javaToolcacheVersionPath"

    # Create a complete file
    touch "$javaToolcacheVersionPath/x64.complete"

    # Create symlink for Java
    ln -s $javaVersionPath "$javaToolcacheVersionPath/x64"
done

# Set Default Java version
update-java-alternatives -s /usr/lib/jvm/adoptopenjdk-${DEFAULT_JDK_VERSION}-hotspot-amd64

echo "JAVA_HOME=/usr/lib/jvm/adoptopenjdk-${DEFAULT_JDK_VERSION}-hotspot-amd64" | tee -a /etc/environment

# add extra permissions to be able execute command without sudo
chmod -R 777 /usr/lib/jvm
# Install Ant
apt-fast install -y --no-install-recommends ant ant-optional
echo "ANT_HOME=/usr/share/ant" | tee -a /etc/environment

# Install Maven
json=$(curl -s "https://api.github.com/repos/apache/maven/tags")
latestMavenVersion=$(echo $json | jq -r '.[] | select(.name | match("^(maven-[0-9.]*)$")) | .name' | head -1 | cut -d- -f2)
mavenDownloadUrl="https://www-eu.apache.org/dist/maven/maven-3/${latestMavenVersion}/binaries/apache-maven-${latestMavenVersion}-bin.zip"
download_with_retries $mavenDownloadUrl "/tmp" "maven.zip"
unzip -qq -d /usr/share /tmp/maven.zip
ln -s /usr/share/apache-maven-${latestMavenVersion}/bin/mvn /usr/bin/mvn

# Install Gradle
# This script founds the latest gradle release from https://services.gradle.org/versions/all
# The release is downloaded, extracted, a symlink is created that points to it, and GRADLE_HOME is set.
gradleJson=$(curl -s https://services.gradle.org/versions/all)
gradleLatestVersion=$(echo $gradleJson | jq -r '.[] | select(.version | contains("-") | not).version' | sort -V | tail -n1)
gradleDownloadUrl=$(echo $gradleJson | jq -r ".[] | select(.version==\"$gradleLatestVersion\") | .downloadUrl")
echo "gradleUrl=$gradleDownloadUrl"
echo "gradleVersion=$gradleLatestVersion"
download_with_retries $gradleDownloadUrl "/tmp" "gradleLatest.zip"
unzip -qq -d /usr/share /tmp/gradleLatest.zip
ln -s /usr/share/gradle-"${gradleLatestVersion}"/bin/gradle /usr/bin/gradle
echo "GRADLE_HOME=$(find /usr/share -depth -maxdepth 1 -name "gradle*")" | tee -a /etc/environment

reloadEtcEnvironment
invoke_tests "Java"
