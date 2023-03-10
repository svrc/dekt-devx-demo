FROM ghcr.io/vmware-tanzu/carvel-docker-image:latest

# Installing prerequisite packages
RUN DEBIAN_FRONTEND="noninteractive" apt-get update && DEBIAN_FRONTEND="noninteractive" apt-get install -y tzdata keyboard-configuration
RUN apt-get -y install curl unzip groff less 
# AWS CLI installation commands
RUN	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN	unzip awscliv2.zip && ./aws/install
# Kubectl CLI installation
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin

