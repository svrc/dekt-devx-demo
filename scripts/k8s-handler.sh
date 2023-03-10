#!/usr/bin/env bash

#azure configs
AZURE_LOCATION=$(yq .clouds.azure.location .config/demo-values.yaml)
AZURE_RESOURCE_GROUP=$(yq .clouds.azure.resourceGroup .config/demo-values.yaml)
AZURE_NODE_TYPE=$(yq .clouds.azure.nodeType .config/demo-values.yaml)
#aws configs
AWS_ACCOUNT_ID=$(yq .clouds.aws.accountID .config/demo-values.yaml)
AWS_IAM_USER=$(yq .clouds.aws.IAMuser .config/demo-values.yaml)
AWS_REGION=$(yq .clouds.aws.region .config/demo-values.yaml)
AWS_INSTANCE_TYPE=$(yq .clouds.aws.instanceType .config/demo-values.yaml)
#gcp configs
GCP_REGION=$(yq .clouds.gcp.region .config/demo-values.yaml)
GCP_PROJECT_ID=$(yq .clouds.gcp.projectID .config/demo-values.yaml)
GCP_MACHINE_TYPE=$(yq .clouds.gcp.machineType .config/demo-values.yaml)


#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating AKS cluster named $cluster_name with $number_of_nodes nodes"
		
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION

	az aks create --name $cluster_name \
		--resource-group $AZURE_RESOURCE_GROUP \
		--node-count $number_of_nodes \
		--node-vm-size $AZURE_NODE_TYPE \
		--generate-ssh-keys
}

#delete-aks-cluster
delete-aks-cluster() {

	cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of AKS cluster $cluster_name"

	az aks delete --name $cluster_name --resource-group $AZURE_RESOURCE_GROUP --yes
}


#create-eks-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating EKS cluster $cluster_name with $number_of_nodes nodes"

#	eksctl create cluster \
#		--name $cluster_name \
#		--managed \
#		--region $AWS_REGION \
#		--instance-types $AWS_INSTANCE_TYPE \
#		--version 1.23 \
#                --with-oidc \
#		-N $number_of_nodes
#
#	eksctl create iamserviceaccount \
#  		--name ebs-csi-controller-sa \
#  		--namespace kube-system \
#  		--cluster $cluster_name \
#  		--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
#  		--approve \
#  		--role-only \
#  		--role-name AmazonEKS_EBS_CSI_DriverRole-$cluster_name
#
#	eksctl create addon \
#		--name aws-ebs-csi-driver \
#		--cluster $cluster_name \
#		--service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole-$cluster_name \
#		--force

OIDCPROVIDER=$(aws eks describe-cluster --name $cluster_name --region $AWS_REGION --output json | jq '.cluster.identity.oidc.issuer' | tr -d '"' | sed 's/https:\/\///')
cat << EOF > /tmp/${cluster_name}-build-service-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDCPROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDCPROVIDER}:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "${OIDCPROVIDER}:sub": [
                        "system:serviceaccount:kpack:controller",
                        "system:serviceaccount:build-service:dependency-updater-controller-serviceaccount"
                    ]
                }
            }
        }
    ]
}
EOF


cat << EOF > /tmp/${cluster_name}-workload-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDCPROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDCPROVIDER}:sub": [ "system:serviceaccount:dev:default","system:serviceaccount:team:default","system:serviceaccount:application:default"],
                    "${OIDCPROVIDER}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

cat << EOF > /tmp/${cluster_name}-build-service-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ecr:DescribeRegistry",
                "ecr:GetAuthorizationToken",
                "ecr:GetRegistryPolicy",
                "ecr:PutRegistryPolicy",
                "ecr:PutReplicationConfiguration",
                "ecr:DeleteRegistryPolicy"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "TAPEcrBuildServiceGlobal"
        },
        {
            "Action": [
                "ecr:DescribeImages",
                "ecr:ListImages",
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:BatchGetRepositoryScanningConfiguration",
                "ecr:DescribeImageReplicationStatus",
                "ecr:DescribeImageScanFindings",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:GetRegistryScanningConfiguration",
                "ecr:GetRepositoryPolicy",
                "ecr:ListTagsForResource",
                "ecr:TagResource",
                "ecr:UntagResource",
                "ecr:BatchDeleteImage",
                "ecr:BatchImportUpstreamImage",
                "ecr:CompleteLayerUpload",
                "ecr:CreatePullThroughCacheRule",
                "ecr:CreateRepository",
                "ecr:DeleteLifecyclePolicy",
                "ecr:DeletePullThroughCacheRule",
                "ecr:DeleteRepository",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:PutImageScanningConfiguration",
                "ecr:PutImageTagMutability",
                "ecr:PutLifecyclePolicy",
                "ecr:PutRegistryScanningConfiguration",
                "ecr:ReplicateImage",
                "ecr:StartImageScan",
                "ecr:StartLifecyclePolicyPreview",
                "ecr:UploadLayerPart",
                "ecr:DeleteRepositoryPolicy",
                "ecr:SetRepositoryPolicy"
            ],
            "Resource": [
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-build-service",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-images/tap-packages"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrBuildServiceScoped"
        }
    ]
}
EOF

cat << EOF > /tmp/${cluster_name}-workload-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ecr:DescribeRegistry",
                "ecr:GetAuthorizationToken",
                "ecr:GetRegistryPolicy",
                "ecr:PutRegistryPolicy",
                "ecr:PutReplicationConfiguration",
                "ecr:DeleteRegistryPolicy"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadGlobal"
        },
        {
            "Action": [
                "ecr:DescribeImages",
                "ecr:ListImages",
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:BatchGetRepositoryScanningConfiguration",
                "ecr:DescribeImageReplicationStatus",
                "ecr:DescribeImageScanFindings",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:GetRegistryScanningConfiguration",
                "ecr:GetRepositoryPolicy",
                "ecr:ListTagsForResource",
                "ecr:TagResource",
                "ecr:UntagResource",
                "ecr:BatchDeleteImage",
                "ecr:BatchImportUpstreamImage",
                "ecr:CompleteLayerUpload",
                "ecr:CreatePullThroughCacheRule",
                "ecr:CreateRepository",
                "ecr:DeleteLifecyclePolicy",
                "ecr:DeletePullThroughCacheRule",
                "ecr:DeleteRepository",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:PutImageScanningConfiguration",
                "ecr:PutImageTagMutability",
                "ecr:PutLifecyclePolicy",
                "ecr:PutRegistryScanningConfiguration",
                "ecr:ReplicateImage",
                "ecr:StartImageScan",
                "ecr:StartLifecyclePolicyPreview",
                "ecr:UploadLayerPart",
                "ecr:DeleteRepositoryPolicy",
                "ecr:SetRepositoryPolicy"
            ],
            "Resource": [
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-build-service",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-apps",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-apps/*"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadScoped"
        }
    ]
}
EOF
# Create the Tanzu Build Service Role
aws iam create-role --role-name ${cluster_name}-build-service --assume-role-policy-document file:///tmp/${cluster_name}-build-service-trust-policy.json
# Create the Workload Role
aws iam create-role --role-name ${cluster_name}-workload --assume-role-policy-document file:///tmp/${cluster_name}-workload-trust-policy.json
# Attach the Policy to the Build Role
aws iam put-role-policy --role-name ${cluster_name}-build-service --policy-name tapBuildServicePolicy --policy-document file:///tmp/${cluster_name}-build-service-policy.json

# Attach the Policy to the Workload Role
aws iam put-role-policy --role-name ${cluster_name}-workload --policy-name tapWorkload --policy-document file:///tmp/${cluster_name}-workload-policy.json
}

create-ecr-repos() {

  aws ecr create-repository --repository-name tap-images/cluster-essentials-bundle --region $AWS_REGION
  aws ecr create-repository --repository-name tap-images/carvel-docker-image --region $AWS_REGION
  aws ecr create-repository --repository-name tap-images/tap-packages --region $AWS_REGION
  aws ecr create-repository --repository-name tap-images/tds-packages --region $AWS_REGION
  aws ecr create-repository --repository-name tap-build-service --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mood-analyzer-application --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mood-analyzer-team --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mood-portal-application --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mood-portal-team --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mood-sensors-application --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mood-sensors-team --region $AWS_REGION
  aws ecr create-repository --repository-name tap-apps/mysensors-dev --region $AWS_REGION

}

#delete-eks-cluster
delete-eks-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of EKS cluster $cluster_name ..."

	eksctl delete cluster --name $cluster_name --force
}

#create-gke-cluster
create-gke-cluster () {

	cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating GKE cluster $cluster_name with $number_of_nodes nodes"
	
	gcloud container clusters create $cluster_name \
		--region $GCP_REGION \
		--project $GCP_PROJECT_ID \
		--num-nodes $number_of_nodes \
		--machine-type $GCP_MACHINE_TYPE

	gcloud container clusters get-credentials $cluster_name --region $GCP_REGION --project $GCP_PROJECT_ID 

	gcloud components install gke-gcloud-auth-plugin
}

#delete-eks-cluster
delete-gke-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of GKE cluster $cluster_name"
	
	gcloud container clusters delete $cluster_name \
		--region $GCP_REGION \
		--project $GCP_PROJECT_ID \
		--quiet

}

#get-creds
get-creds() {

	clusterProvider=$1
	clusterName=$2
	
	case $clusterProvider in
	aks)
  		az aks get-credentials --overwrite-existing --resource-group $AZURE_RESOURCE_GROUP --name $clusterName
    	;;
	eks)
		kubectl config rename-context $AWS_IAM_USER@$clusterName.$AWS_REGION.eksctl.io $clusterName
		;;
	gke)
		kubectl config rename-context gke_$GCP_PROJECT_ID"_"$GCP_REGION"_"$clusterName $clusterName
		;;
	*)
		incorrect-usage
		;;
	esac

}

#verify cluster
verify () {

	cluster_name=$1

	kubectl config use-context $cluster_name 
	kubectl get pods -A
	kubectl get svc -A
	scripts/dektecho.sh prompt  "Verfiy core components of $cluster_name have been created succefully. Continue?" && [ $? -eq 0 ] || exit
}

#wait-for-all-running-pods
wait-for-all-running-pods () {

		namespace=$1
        status=""
        printf "Waiting for all pods in namespace $namespace to be in 'running' state  ."
        while [ "$status" == "" ]
        do
            printf "."
            status="$(kubectl get pods -n $namespace  -o=json | grep 'running')" 
            sleep 1
        done
        echo
}

#################### main #######################

#incorrect-usage
incorrect-usage() {
	
	scripts/dektecho.sh err "Incorrect usage. Please specify:"
    echo "  create [aks/eks/gke cluster-name numbber-of-nodes]"
    echo "  delete [aks/eks/gke cluster-name]"
	echo "  init-cluster [aks/eks/gke cluster-name]"
    exit
}

operation=$1
clusterProvider=$2
clusterName=$3
numOfNodes=$4
case $operation in

create)
	case $clusterProvider in
	aks)
  		create-aks-cluster $clusterName $numOfNodes
    	;;
	eks)
		create-eks-cluster $clusterName $numOfNodes
		;;
	gke)
		create-gke-cluster $clusterName $numOfNodes
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
delete)
	case $clusterProvider in
	aks)
  		delete-aks-cluster $clusterName
    	;;
	eks)
		delete-eks-cluster $clusterName
		;;
	gke)
		delete-gke-cluster $clusterName
		;;
	*)
		incorrect-usage
		;;
	esac
	;;	
create-ecr-repos)
    create-ecr-repos
    ;;

init)
	get-creds $clusterProvider $clusterName
	verify $clusterName
	;;
*)
	incorrect-usage
	;;
esac
