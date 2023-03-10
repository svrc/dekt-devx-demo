#!/usr/bin/env bash

SYSTEM_REPO=$(yq .repositories.system .config/demo-values.yaml)
CARVEL_BUNDLE=$(yq .tap.carvelBundle .config/demo-values.yaml)
TANZU_NETWORK_REGISTRY="registry.tanzu.vmware.com"
TANZU_NETWORK_USER=$(yq .tanzu_network.username .config/demo-values.yaml)
TANZU_NETWORK_PASSWORD=$(yq .tanzu_network.password .config/demo-values.yaml)
TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
TDS_VERSION=$(yq .data_services.tdsVersion .config/demo-values.yaml)
GW_INSTALL_DIR=$(yq .brownfield_apis.scgwInstallDirectory .config/demo-values.yaml)
AWS_REGION=$(yq .clouds.aws.region .config/demo-values.yaml)
export IMGPKG_REGISTRY_HOSTNAME=$(yq .private_registry.hostname .config/demo-values.yaml)
#export IMGPKG_REGISTRY_USERNAME=$(yq .private_registry.username .config/demo-values.yaml)
#export IMGPKG_REGISTRY_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)

#relocate-tap-images
relocate-tap-images() {

    scripts/dektecho.sh status "relocating TAP $TAP_VERSION images to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages"
    imgpkg copy \
        --bundle $TANZU_NETWORK_REGISTRY/tanzu-application-platform/tap-packages:$TAP_VERSION \
        --to-tar .config/tap-packages-$TAP_VERSION.tar \
        --include-non-distributable-layers

    
 #   IMGPKG_USERNAME=$IMGPKG_REGISTRY_USERNAME
 #   IMGPKG_PASSWORD=$IMGPKG_REGISTRY_PASSWORD
    imgpkg copy --concurrency 1  \
        --tar .config/tap-packages-$TAP_VERSION.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages \
        --include-non-distributable-layers

    rm -f .config/tap-packages-$TAP_VERSION.tar
            
}

#relocate-carvel-bundle
relocate-carvel-bundle() {

    scripts/dektecho.sh status "relocating cluster-essentials to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle"

    imgpkg copy \
        --bundle $TANZU_NETWORK_REGISTRY/tanzu-cluster-essentials/cluster-essentials-bundle@$CARVEL_BUNDLE \
        --to-tar .config/carvel-bundle.tar \
        --include-non-distributable-layers

 #   IMGPKG_USERNAME=$IMGPKG_REGISTRY_USERNAME
 #   IMGPKG_PASSWORD=$IMGPKG_REGISTRY_PASSWORD
    imgpkg copy \
        --tar .config/carvel-bundle.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle \
        --include-non-distributable-layers

    rm -f .config/carvel-bundle.tar
}

#relocate-tbs-images
relocate-tbs-images() {

    #obtain available tbs version
    tbs_package=$(tanzu package available list -n tap-install | grep 'buildservice')
    tbs_version=$(echo ${tbs_package: -20} | sed 's/[[:space:]]//g')
    
    scripts/dektecho.sh status "relocating TBS $tbs_version images to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tbs-full-deps"

    imgpkg copy \
        --bundle $TANZU_NETWORK_REGISTRY/tanzu-application-platform/full-tbs-deps-package-repo:$tbs_version \
        --to-tar=.config/tbs-full-deps.tar
    
 #   IMGPKG_USERNAME=$IMGPKG_REGISTRY_USERNAME
 #   IMGPKG_PASSWORD=$IMGPKG_REGISTRY_PASSWORD
    imgpkg copy \
        --tar .config/tbs-full-deps.tar \
        --to-repo=$IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tbs-full-deps

    rm -f .config/tbs-full-deps.tar

}

#relocate-gw-images
relocate-scgw-images() {

    scripts/dektecho.sh status "relocating Spring Cloud Gateway images $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO"

    $GW_INSTALL_DIR/scripts/relocate-images.sh $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO
}

#relocate-tds-images
relocate-tds-images() {

    scripts/dektecho.sh status "relocating Tanzu Data Services $TDS_VERSION to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tds-packages"
        
#    IMGPKG_USERNAME=$IMGPKG_REGISTRY_USERNAME
#    IMGPKG_PASSWORD=$IMGPKG_REGISTRY_PASSWORD
    imgpkg copy --concurrency 1  \
        --bundle $TANZU_NETWORK_REGISTRY/packages-for-vmware-tanzu-data-services/tds-packages:$TDS_VERSION \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tds-packages
}
#add-carvel
add-carvel () {

    scripts/dektecho.sh status "Add Carvel tools to cluster $(kubectl config current-context)"

    pushd scripts/carvel
    
    INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle@$CARVEL_BUNDLE \
    INSTALL_REGISTRY_HOSTNAME=$IMGPKG_REGISTRY_HOSTNAME \
    INSTALL_REGISTRY_USERNAME=AWS \
    INSTALL_REGISTRY_PASSWORD=$( aws ecr get-login-password --region $AWS_REGION ) \
    ./install.sh --yes

    pushd
}

#remove-carvel
remove-carvel () {

    scripts/dektecho.sh status "remove Carvel tools to cluster $(kubectl config current-context)"

    pushd scripts/carvel

    INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle@$CARVEL_BUNDLE \
    INSTALL_REGISTRY_HOSTNAME=$IMGPKG_REGISTRY_HOSTNAME \
    INSTALL_REGISTRY_USERNAME=AWS \
    INSTALL_REGISTRY_PASSWORD=$( aws ecr get-login-password --region $AWS_REGION ) \
    ./uninstall.sh --yes

    pushd
}



#generate-config-yamls
generate-config-yamls() {

    scripts/dektecho.sh status "Generating demo configuration yamls"

    #ecr repo
    export IMGPKG_REGISTRY_HOSTNAME=$(aws sts get-caller-identity --output json | jq -r .Account).dkr.ecr.${AWS_REGION}.amazonaws.com   

    #tap-profiles
    mkdir -p .config/tap-profiles
    ytt -f config-templates/tap-profiles/tap-view.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-view.yaml
    ytt -f config-templates/tap-profiles/tap-iterate.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-iterate.yaml
    ytt -f config-templates/tap-profiles/tap-build.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-build.yaml
    ytt -f config-templates/tap-profiles/tap-run.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-run.yaml

    #supply-chains
    mkdir -p .config/supply-chains
    ytt -f config-templates/supply-chains/dekt-src-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-config.yaml
    ytt -f config-templates/supply-chains/dekt-src-scan-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-scan-config.yaml
    ytt -f config-templates/supply-chains/dekt-src-test-api-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-test-api-config.yaml
    ytt -f config-templates/supply-chains/dekt-src-test-scan-api-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-test-scan-api-config.yaml
    ytt -f config-templates/supply-chains/gitops-creds.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/gitops-creds.yaml
    cp config-templates/supply-chains/tekton-pipeline-dotnet.yaml .config/supply-chains/tekton-pipeline-dotnet.yaml
    cp config-templates/supply-chains/tekton-pipeline.yaml .config/supply-chains/tekton-pipeline.yaml

    #scanners
    mkdir -p .config/scanners
    ytt -f config-templates/scanners/carbonblack-creds.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/carbonblack-creds.yaml
    ytt -f config-templates/scanners/carbonblack-values.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/carbonblack-values.yaml
    ytt -f config-templates/scanners/snyk-creds.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/snyk-creds.yaml
    ytt -f config-templates/scanners/snyk-values.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/snyk-values.yaml
    cp config-templates/scanners/scan-policy.yaml .config/scanners/scan-policy.yaml

    #cluster-configs
    mkdir -p .config/cluster-configs
    cp -a config-templates/cluster-configs/ .config/cluster-configs/
    ytt -f config-templates/cluster-configs/single-user-access.yaml -v cluster_type=dev --data-values-file=.config/demo-values.yaml > .config/cluster-configs/single-user-access-dev.yaml
    ytt -f config-templates/cluster-configs/single-user-access.yaml -v cluster_type=stage --data-values-file=.config/demo-values.yaml > .config/cluster-configs/single-user-access-stage.yaml
    ytt -f config-templates/cluster-configs/single-user-access.yaml -v cluster_type=prod --data-values-file=.config/demo-values.yaml > .config/cluster-configs/single-user-access-prod.yaml
    
    #data-services (WIP)
    cp -R config-templates/data-services .config
    ytt -f config-templates/data-services/rds-postgres/crossplane-xrd-composition.yaml --data-values-file=.config/demo-values.yaml > .config/data-services/rds-postgres/crossplane-xrd-composition.yaml

    #workloads
    mkdir -p .config/workloads
    cp -a config-templates/workloads/ .config/workloads/
    
}

#################### main #######################

#incorrect-usage
incorrect-usage() {
    scripts/dektecho.sh err "Incorrect usage. Use one of the following: "
    echo "  relocate-tanzu-images tap|tbs|tds|scgw"
    echo 
    echo "  add-carvel-tools"
    echo "  remove-carvel-tools"
    echo 
    echo "  generate-configs"
    echo
}

case $1 in
relocate-tanzu-images)
    aws ecr get-login-password --region $AWS_REGION | docker login $IMGPKG_REGISTRY_HOSTNAME -u AWS --password-stdin
    docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
    case $2 in
    tap)
        relocate-carvel-bundle
        relocate-tap-images
        ;;
    tbs)
        scripts/dektecho.sh prompt  "Verfiy tanzu registry is installed on this k8s cluster. Continue?" && [ $? -eq 0 ] || exit
        relocate-tbs-images 
        ;;
    tds)    
        relocate-tds-images
        ;;
    scgw)
        relocate-scgw-images
        ;;
    *)
	    incorrect-usage
	    ;;
    esac
    ;;
add-carvel-tools)
  	add-carvel
    ;;
remove-carvel-tools)
  	remove-carvel
    ;;

generate-configs)
    generate-config-yamls
    ;;
*)
	incorrect-usage
	;;
esac
