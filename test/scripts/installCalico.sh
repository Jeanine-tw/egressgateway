#!/bin/bash
## SPDX-License-Identifier: Apache-2.0
## Copyright Authors of Spider

set -o errexit -o nounset -o pipefail

OS=$(uname | tr 'A-Z' 'a-z')
SED_COMMAND="sed"

CURRENT_FILENAME=$( basename $0 )
CURRENT_DIR_PATH=$(cd $(dirname $0); pwd)
PROJECT_ROOT_PATH=$( cd ${CURRENT_DIR_PATH}/../.. && pwd )

DEST_CALICO_YAML_DIR=${PROJECT_ROOT_PATH}/test/.tmp/yaml

mkdir -p ${DEST_CALICO_YAML_DIR}
cp ${PROJECT_ROOT_PATH}/test/yaml/calico.yaml ${DEST_CALICO_YAML_DIR}/calico.yaml

export CALICO_VERSION=${CALICO_VERSION}
export CALICO_AUTODETECTION_METHOD=interface=eth0

case ${E2E_IP_FAMILY} in
  ipv4)
      export CALICO_CNI_ASSIGN_IPV4=true
      export CALICO_CNI_ASSIGN_IPV6=false
      export CALICO_IP_AUTODETECT=autodetect
      export CALICO_IP6_AUTODETECT=autodetect
      export CALICO_FELIX_IPV6SUPPORT=false
    ;;
  ipv6)
      export CALICO_CNI_ASSIGN_IPV4=false
      export CALICO_CNI_ASSIGN_IPV6=true
      export CALICO_IP_AUTODETECT=autodetect
      export CALICO_IP6_AUTODETECT=autodetect
      export CALICO_FELIX_IPV6SUPPORT=true
    ;;
  dual)
      export CALICO_CNI_ASSIGN_IPV4=true
      export CALICO_CNI_ASSIGN_IPV6=true
      export CALICO_IP_AUTODETECT=autodetect
      export CALICO_IP6_AUTODETECT=autodetect
      export CALICO_FELIX_IPV6SUPPORT=true
    ;;
  *)
    echo "the value of E2E_IP_FAMILY: ipv4 or ipv6 or dual"
    exit 1
esac

if [ ${OS} == "darwin" ]; then SED_COMMAND=gsed ; fi

ENV_LIST=$(env | grep -E "^CALICO_")
for env in ${ENV_LIST}; do
    KEY="${env%%=*}"
    VALUE="${env#*=}"
    echo $KEY $VALUE
    ${SED_COMMAND} -i "s/<<${KEY}>>/${VALUE}/g" ${DEST_CALICO_YAML_DIR}/calico.yaml
done


# accelerate local cluster , in case that it times out to wait calico ready
IMAGE_LIST=`cat ${DEST_CALICO_YAML_DIR}/calico.yaml | grep "image: " | awk '{print $2}' | sort  | uniq`
for IMAGE in ${IMAGE_LIST}; do
    echo "load calico image ${IMAGE} to kind cluster"
    docker pull ${IMAGE}
    kind load docker-image ${IMAGE} --name ${KIND_CLUSTER_NAME}
done

kubectl apply -f  ${DEST_CALICO_YAML_DIR}/calico.yaml --kubeconfig ${E2E_KIND_KUBECONFIG_PATH}
sleep 3

kubectl wait --for=condition=ready -l k8s-app=calico-node --timeout=${INSTALL_TIME_OUT} pod -n kube-system --kubeconfig ${E2E_KIND_KUBECONFIG_PATH}
kubectl --kubeconfig ${E2E_KIND_KUBECONFIG_PATH} patch felixconfigurations.crd.projectcalico.org default --type='merge' -p '{"spec":{"chainInsertMode":"Append"}}' || { echo "failed to patch calico chainInsertMode"; exit 1; }
kubectl get po -n kube-system --kubeconfig ${E2E_KIND_KUBECONFIG_PATH}

echo -e "\033[35m Succeed to install Calico \033[0m"
