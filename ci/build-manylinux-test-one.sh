#!/bin/bash

if [ -z "${VIRTUAL_ENV}" ] && [ -z "${GITHUB_WORKSPACE}" ] ; then
	echo "Required: use of a virtual environment."
	exit 1
fi

if [ -z "${POLICY}" ] ; then
    POLICY=manylinux2010
fi
if [ -z "${PLATFORM}" ] ; then
    PLATFORM=x86_64
fi
if [ -z "${COMMIT_SHA}" ] ; then
    COMMIT_SHA=latest
fi

if [ -z "$1" ] ; then
	echo "Usage: $0 sample-name"
	echo "Where:"
	echo "  sample-name is the name in samples directory (e.g. cryptography)"
	exit 1
fi
TEST_SAMPLE=$1

set -e -u -x

# Get script directory
CI_DIR=$(dirname "${BASH_SOURCE[0]}")
TOP_DIR=${CI_DIR}/..
# Get the real path in a compatible way (do not use realpath)
pushd $TOP_DIR
TOP_DIR=$(pwd)
popd

# Generate the script to build and run the test
SAMPLE_DIR=${TOP_DIR}/cx_Freeze/samples/${TEST_SAMPLE}
mkdir -p ${SAMPLE_DIR}/build
cat <<EOF >${SAMPLE_DIR}/build/build-test-${TEST_SAMPLE}.sh
#!/bin/bash
cd /io/cx_Freeze/samples/${TEST_SAMPLE}
for PYBIN in /opt/python/cp*36m/bin ; do
    echo "Freeze sample: ${TEST_SAMPLE}"
    echo "Python from: \${PYBIN}"
    echo "Platform: manylinux2010_${PLATFORM}"
    PY_COMMAND="import sysconfig as s; print(s.get_python_version())"
    PY_VERSION=$(\${PYBIN}/python -c "\${PY_COMMAND}")
    echo "Python version: \${PY_VERSION}"
    BUILD_ENV=build/venv.\${PY_VERSION}
    "\${PYBIN}/python" -m venv --system-site-packages \${BUILD_ENV}
    source \${BUILD_ENV}/bin/activate
    /io/ci/build-test-one.sh ${TEST_SAMPLE}
    deactivate || true
done
chown -R \$USER_ID:\$GROUP_ID build/exe.linux-${PLATFORM}-*
EOF
chmod +x ${SAMPLE_DIR}/build/build-test-${TEST_SAMPLE}.sh

# Build and run the test in the manylinux2010 container
docker run --rm -e PLAT=${POLICY}_${PLATFORM} \
	-e USER_ID=$(id -u) -e GROUP_ID=$(id -g) \
	-v ${TOP_DIR}:/io \
	${POLICY}_${PLATFORM}:${COMMIT_SHA} \
	/io/cx_Freeze/samples/${TEST_SAMPLE}/build/build-test-${TEST_SAMPLE}.sh

# The built test in manylinux2010 container should run in a different container
echo "Run sample isolated in a docker: ${TEST_SAMPLE}"
echo "Platform: ubuntu:16.04 ${PLATFORM}"
PY_PLATFORM=$(python -c "import sysconfig; print(sysconfig.get_platform())")
PY_VERSION=3.6
BUILD_DIR="${SAMPLE_DIR}/build/exe.${PY_PLATFORM}-${PY_VERSION}"
count=0
TEST_NAME=$(python ${CI_DIR}/build-test-json.py ${TEST_SAMPLE} ${count})
until [ -z "${TEST_NAME}" ] ; do
    if [[ ${TEST_NAME} == gui:* ]] || [[ ${TEST_NAME} == svc:* ]] ; then
        TEST_NAME=${TEST_NAME:4}
    fi
    if [ -f ${BUILD_DIR}/${TEST_NAME} ] ; then
        docker run --rm \
            -v ${BUILD_DIR}:/frozen \
            ubuntu:16.04 /frozen/${TEST_NAME}
        if [ "${TEST_SAMPLE}" == "simple" ] ; then
            echo "test - rename the executable"
            cp ${BUILD_DIR}/hello ${BUILD_DIR}/Test_Hello
            docker run --rm \
                -v ${BUILD_DIR}:/frozen \
                ubuntu:16.04 /frozen/Test_Hello ação ótica côncavo peña
        fi
    fi
    count=$(( $count + 1 ))
    TEST_NAME=$(python ${CI_DIR}/build-test-json.py ${TEST_SAMPLE} ${count})
done